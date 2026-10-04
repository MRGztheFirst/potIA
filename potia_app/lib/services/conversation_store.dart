import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/conversation.dart';

class ConversationStore {
  ConversationStore({Future<Directory> Function()? root}) : _root = root ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _root;
  Future<void> _queue = Future.value();

  Future<Directory> attachmentsDir(int userId) => _dir(userId, 'anexos');

  Future<List<ConversationSummary>> list(int userId) => _serial(() async {
        final items = await _readIndex(userId);
        items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return items;
      });

  Future<Conversation?> load(int userId, String id) => _serial(() => _readConversation(userId, id));

  Future<void> save(int userId, Conversation conversation) => _serial(() async {
        await _writeJson(await _conversationFile(userId, conversation.id), conversation.toJson());
        final index = await _readIndex(userId)
          ..removeWhere((s) => s.id == conversation.id)
          ..add(conversation.summary);
        await _writeIndex(userId, index);
      });

  Future<void> rename(int userId, String id, String title) => _serial(() async {
        final conversation = await _readConversation(userId, id);
        if (conversation == null) return;
        final renamed = Conversation(
          id: conversation.id,
          title: title,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          messages: conversation.messages,
        );
        await _writeJson(await _conversationFile(userId, id), renamed.toJson());
        final index = await _readIndex(userId);
        await _writeIndex(userId, [for (final s in index) s.id == id ? s.copyWith(title: title) : s]);
      });

  Future<void> delete(int userId, String id) => _serial(() async {
        final conversation = await _readConversation(userId, id);
        for (final message in conversation?.messages ?? const []) {
          for (final attachment in message.attachments) {
            await _deleteQuietly(File(attachment.path));
          }
        }
        await _deleteQuietly(await _conversationFile(userId, id));
        final index = await _readIndex(userId)
          ..removeWhere((s) => s.id == id);
        await _writeIndex(userId, index);
      });

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _dir(int userId, String name) async {
    final base = await _root();
    final dir = Directory(_join([base.path, 'potia', 'u$userId', name]));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _conversationFile(int userId, String id) async =>
      File(_join([(await _dir(userId, 'conversas')).path, '$id.json']));

  Future<File> _indexFile(int userId) async => File(_join([(await _dir(userId, 'conversas')).path, 'index.json']));

  Future<Conversation?> _readConversation(int userId, String id) async {
    final json = await _readJson(await _conversationFile(userId, id));
    return json is Map<String, dynamic> ? Conversation.fromJson(json) : null;
  }

  Future<List<ConversationSummary>> _readIndex(int userId) async {
    final json = await _readJson(await _indexFile(userId));
    if (json is! List) return [];
    return [
      for (final item in json)
        if (item is Map<String, dynamic>) ConversationSummary.fromJson(item),
    ];
  }

  Future<void> _writeIndex(int userId, List<ConversationSummary> items) async =>
      _writeJson(await _indexFile(userId), items.map((s) => s.toJson()).toList());

  Future<Object?> _readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(File file, Object json) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);
}
