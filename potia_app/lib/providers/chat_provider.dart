import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../services/attachment_exception.dart';
import '../services/attachment_service.dart';
import '../services/conversation_store.dart';
import 'history_provider.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required ApiService api,
    required ConversationStore store,
    required HistoryProvider history,
    required AttachmentService attachments,
  })  : _api = api,
        _store = store,
        _history = history,
        _attachments = attachments;

  static const maxImagesPerMessage = 4;
  static const maxDocumentsPerMessage = 3;

  final ApiService _api;
  final ConversationStore _store;
  final HistoryProvider _history;
  final AttachmentService _attachments;

  final List<ChatMessage> _messages = [];
  final List<ChatAttachment> _pending = [];
  StreamSubscription<String>? _subscription;
  bool _streaming = false;
  bool _waitingFirstToken = false;
  bool _isAttaching = false;
  int _requestGeneration = 0;

  int? _userId;
  String? _conversationId;
  String? _title;
  DateTime? _createdAt;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<ChatAttachment> get pendingAttachments => List.unmodifiable(_pending);
  bool get isEmpty => _messages.isEmpty;
  bool get isStreaming => _streaming;
  bool get isWaitingFirstToken => _waitingFirstToken;
  bool get isAttaching => _isAttaching;
  String? get conversationId => _conversationId;

  int get remainingImageSlots => maxImagesPerMessage - _pending.where((a) => a.isImage).length;
  bool get canAddDocument => _pending.where((a) => !a.isImage).length < maxDocumentsPerMessage;

  void bindUser(int userId) {
    if (_userId == userId) return;
    reset();
    _userId = userId;
    unawaited(_history.loadFor(userId));
  }

  void reset() {
    _cancelStream();
    _messages.clear();
    unawaited(_attachments.discard(List.of(_pending)));
    _pending.clear();
    _userId = null;
    _clearConversation();
    _history.clear();
    notifyListeners();
  }

  void newConversation() {
    if (_streaming) stopGeneration();
    _messages.clear();
    _clearConversation();
    notifyListeners();
  }

  Future<bool> openConversation(String id) async {
    final userId = _userId;
    if (userId == null) return false;
    if (id == _conversationId) return true;
    if (_streaming) stopGeneration();
    final conversation = await _store.load(userId, id);
    if (conversation == null) return false;
    _messages
      ..clear()
      ..addAll(conversation.messages);
    _conversationId = conversation.id;
    _title = conversation.title;
    _createdAt = conversation.createdAt;
    notifyListeners();
    return true;
  }

  Future<void> renameConversation(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    if (id == _conversationId) _title = clean;
    await _history.rename(id, clean);
  }

  Future<void> deleteConversation(String id) async {
    if (id == _conversationId) newConversation();
    await _history.delete(id);
  }

  Future<String?> addPhotoFromCamera() => _addAttachments((dir) async {
        if (remainingImageSlots < 1) throw const AttachmentException('Você pode enviar até 4 fotos por mensagem.');
        final photo = await _attachments.takePhoto(dir);
        return photo == null ? const [] : [photo];
      });

  Future<String?> addPhotosFromGallery() => _addAttachments((dir) {
        if (remainingImageSlots < 1) throw const AttachmentException('Você pode enviar até 4 fotos por mensagem.');
        return _attachments.pickFromGallery(dir, limit: remainingImageSlots);
      });

  Future<String?> addDocument() => _addAttachments((dir) async {
        if (!canAddDocument) throw const AttachmentException('Você pode enviar até 3 documentos por mensagem.');
        final document = await _attachments.pickDocument(dir);
        return document == null ? const [] : [document];
      });

  void removePendingAttachment(String id) {
    final index = _pending.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final removed = _pending.removeAt(index);
    unawaited(_attachments.discard([removed]));
    notifyListeners();
  }

  void sendMessage(String text, {bool fromVoice = false}) {
    final content = text.trim();
    if (_streaming || _isAttaching || (content.isEmpty && _pending.isEmpty)) return;
    final message = ChatMessage.user(content, attachments: List.of(_pending), fromVoice: fromVoice);
    _pending.clear();
    if (_conversationId == null) {
      _conversationId = ChatMessage.newId();
      _title = Conversation.titleFor(message);
      _createdAt = DateTime.now();
    }
    _messages.add(message);
    _persist();
    unawaited(_requestAnswer());
  }

  void retryLastAnswer() {
    if (_streaming || _messages.isEmpty || !_messages.last.hasError) return;
    _messages.removeLast();
    unawaited(_requestAnswer());
  }

  void stopGeneration() {
    if (!_streaming) return;
    _cancelStream();
    final index = _messages.lastIndexWhere((m) => m.isStreaming);
    if (index != -1) {
      final message = _messages[index];
      if (message.content.trim().isEmpty) {
        _messages.removeAt(index);
      } else {
        _messages[index] = message.copyWith(status: MessageStatus.done);
      }
    }
    _finishStreaming();
  }

  Future<String?> _addAttachments(Future<List<ChatAttachment>> Function(Directory dir) pick) async {
    final userId = _userId;
    if (userId == null || _isAttaching) return null;
    _isAttaching = true;
    notifyListeners();
    try {
      final added = await pick(await _store.attachmentsDir(userId));
      if (_userId != userId) {
        await _attachments.discard(added);
        return null;
      }
      _pending.addAll(added);
      return null;
    } on AttachmentException catch (error) {
      return error.message;
    } on PlatformException catch (error) {
      return error.code.contains('camera') ? 'Não consegui abrir a câmera.' : 'Não foi possível anexar: ${error.message ?? error.code}';
    } catch (error) {
      return 'Não foi possível anexar o arquivo.';
    } finally {
      _isAttaching = false;
      notifyListeners();
    }
  }

  Future<void> _requestAnswer() async {
    final history = _messages.where((m) => !m.hasError && m.hasContent).toList();
    final placeholder = ChatMessage.assistantPlaceholder();
    _messages.add(placeholder);
    _streaming = true;
    _waitingFirstToken = true;
    final generation = ++_requestGeneration;
    notifyListeners();

    final List<Map<String, dynamic>> payload;
    try {
      payload = await _buildPayload(history);
    } catch (_) {
      if (generation != _requestGeneration) return;
      _fail(placeholder.id, 'Não consegui ler os anexos desta mensagem. Eles podem ter sido apagados.');
      return;
    }
    if (generation != _requestGeneration) return;

    final buffer = StringBuffer();
    _subscription = _api.streamChat(payload).listen(
      (chunk) {
        _waitingFirstToken = false;
        buffer.write(chunk);
        _updateMessage(placeholder.id, (m) => m.copyWith(content: buffer.toString()));
        notifyListeners();
      },
      onError: (Object error) {
        _fail(placeholder.id, error is ApiException ? error.message : 'Algo deu errado: $error');
      },
      onDone: () {
        _updateMessage(
          placeholder.id,
          (m) => buffer.isEmpty
              ? m.copyWith(status: MessageStatus.error, errorText: 'A PotIA não enviou nenhuma resposta.')
              : m.copyWith(status: MessageStatus.done),
        );
        _finishStreaming();
      },
      cancelOnError: true,
    );
  }

  Future<List<Map<String, dynamic>>> _buildPayload(List<ChatMessage> history) async {
    final lastUser = history.lastIndexWhere((m) => m.isUser);
    return [
      for (var i = 0; i < history.length; i++)
        history[i].toApiJson(encodedImages: i == lastUser ? await _encodeImages(history[i]) : const []),
    ];
  }

  Future<List<String>> _encodeImages(ChatMessage message) async => [
        for (final image in message.images) base64Encode(await File(image.path).readAsBytes()),
      ];

  void _fail(String messageId, String errorText) {
    _updateMessage(messageId, (m) => m.copyWith(status: MessageStatus.error, errorText: errorText));
    _finishStreaming();
  }

  void _updateMessage(String id, ChatMessage Function(ChatMessage) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) _messages[index] = update(_messages[index]);
  }

  void _finishStreaming() {
    _subscription = null;
    _streaming = false;
    _waitingFirstToken = false;
    _persist();
    notifyListeners();
  }

  void _cancelStream() {
    _requestGeneration++;
    _subscription?.cancel();
    _subscription = null;
    _api.cancelChatStream();
    _streaming = false;
    _waitingFirstToken = false;
  }

  void _clearConversation() {
    _conversationId = null;
    _title = null;
    _createdAt = null;
  }

  void _persist() {
    final userId = _userId;
    final id = _conversationId;
    if (userId == null || id == null) return;
    final saved = _messages.where((m) => !(m.isStreaming && m.content.isEmpty)).toList();
    if (saved.isEmpty) return;
    final conversation = Conversation(
      id: id,
      title: _title ?? 'Conversa',
      createdAt: _createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      messages: saved,
    );
    _history.upsert(conversation.summary);
    unawaited(_store.save(userId, conversation).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _cancelStream();
    super.dispose();
  }
}
