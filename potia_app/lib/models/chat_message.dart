import 'chat_attachment.dart';

enum MessageRole { user, assistant }

enum MessageStatus { streaming, done, error }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.done,
    this.errorText,
    this.attachments = const [],
    this.fromVoice = false,
  });

  factory ChatMessage.user(String content, {List<ChatAttachment> attachments = const [], bool fromVoice = false}) =>
      ChatMessage(
        id: newId(),
        role: MessageRole.user,
        content: content,
        createdAt: DateTime.now(),
        attachments: attachments,
        fromVoice: fromVoice,
      );

  factory ChatMessage.assistantPlaceholder() => ChatMessage(
        id: newId(),
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
        status: MessageStatus.streaming,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final status = MessageStatus.values.byName(json['status'] as String? ?? 'done');
    return ChatMessage(
      id: json['id'] as String,
      role: MessageRole.values.byName(json['role'] as String),
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      status: status == MessageStatus.streaming ? MessageStatus.done : status,
      errorText: json['errorText'] as String?,
      attachments: [
        for (final item in json['attachments'] as List<dynamic>? ?? const [])
          ChatAttachment.fromJson(item as Map<String, dynamic>),
      ],
      fromVoice: json['fromVoice'] as bool? ?? false,
    );
  }

  static const int maxDocumentChars = 8000;

  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? errorText;
  final List<ChatAttachment> attachments;
  final bool fromVoice;

  bool get isUser => role == MessageRole.user;
  bool get isStreaming => status == MessageStatus.streaming;
  bool get hasError => status == MessageStatus.error;
  bool get hasContent => content.trim().isNotEmpty || attachments.isNotEmpty;

  List<ChatAttachment> get images => attachments.where((a) => a.isImage).toList();
  List<ChatAttachment> get documents => attachments.where((a) => !a.isImage).toList();

  ChatMessage copyWith({String? content, MessageStatus? status, String? errorText}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        status: status ?? this.status,
        errorText: errorText ?? this.errorText,
        attachments: attachments,
        fromVoice: fromVoice,
      );

  String get apiContent {
    final parts = <String>[if (content.trim().isNotEmpty) content.trim()];
    for (final document in documents) {
      final text = (document.text ?? '').trim();
      final body = text.length > maxDocumentChars ? '${text.substring(0, maxDocumentChars)}\n[...documento cortado]' : text;
      parts.add('[Documento anexado: ${document.name}]\n${body.isEmpty ? '(sem texto legível)' : body}');
    }
    return parts.join('\n\n');
  }

  Map<String, dynamic> toApiJson({List<String> encodedImages = const []}) {
    var text = apiContent;
    if (encodedImages.isEmpty && images.isNotEmpty) {
      text = [if (text.isNotEmpty) text, '[${images.length} foto(s) enviada(s) antes nesta conversa]'].join('\n\n');
    }
    return {
      'role': role.name,
      'content': text,
      if (encodedImages.isNotEmpty) 'images': encodedImages,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'status': (isStreaming ? MessageStatus.done : status).name,
        if (errorText != null) 'errorText': errorText,
        if (attachments.isNotEmpty) 'attachments': attachments.map((a) => a.toJson()).toList(),
        if (fromVoice) 'fromVoice': true,
      };

  static int _counter = 0;
  static String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';
}
