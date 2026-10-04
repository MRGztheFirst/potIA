import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({required ApiService api}) : _api = api;

  final ApiService _api;
  final List<ChatMessage> _messages = [];
  StreamSubscription<String>? _subscription;
  bool _waitingFirstToken = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isEmpty => _messages.isEmpty;

  bool get isStreaming => _subscription != null;

  bool get isWaitingFirstToken => _waitingFirstToken;

  void sendMessage(String text) {
    final content = text.trim();
    if (content.isEmpty || isStreaming) return;
    _messages.add(ChatMessage.user(content));
    _requestAnswer();
  }

  void retryLastAnswer() {
    if (isStreaming || _messages.isEmpty || !_messages.last.hasError) return;
    _messages.removeLast();
    _requestAnswer();
  }

  void stopGeneration() {
    if (!isStreaming) return;
    _subscription?.cancel();
    _api.cancelChatStream();
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

  void clearConversation() {
    if (isStreaming) stopGeneration();
    _messages.clear();
    notifyListeners();
  }

  void _requestAnswer() {
    final history = _messages.where((m) => !m.hasError && m.content.trim().isNotEmpty).toList();
    final placeholder = ChatMessage.assistantPlaceholder();
    _messages.add(placeholder);
    _waitingFirstToken = true;
    notifyListeners();

    final buffer = StringBuffer();
    _subscription = _api.streamChat(history).listen(
      (chunk) {
        _waitingFirstToken = false;
        buffer.write(chunk);
        _updateMessage(placeholder.id, (m) => m.copyWith(content: buffer.toString()));
        notifyListeners();
      },
      onError: (Object error) {
        final text = error is ApiException ? error.message : 'Algo deu errado: $error';
        _updateMessage(placeholder.id, (m) => m.copyWith(status: MessageStatus.error, errorText: text));
        _finishStreaming();
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

  void _updateMessage(String id, ChatMessage Function(ChatMessage) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) _messages[index] = update(_messages[index]);
  }

  void _finishStreaming() {
    _subscription = null;
    _waitingFirstToken = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _api.cancelChatStream();
    super.dispose();
  }
}
