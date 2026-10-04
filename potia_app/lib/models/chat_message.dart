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
  });

  factory ChatMessage.user(String content) => ChatMessage(
        id: _nextId(),
        role: MessageRole.user,
        content: content,
        createdAt: DateTime.now(),
      );

  factory ChatMessage.assistantPlaceholder() => ChatMessage(
        id: _nextId(),
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
        status: MessageStatus.streaming,
      );

  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? errorText;

  bool get isUser => role == MessageRole.user;
  bool get isStreaming => status == MessageStatus.streaming;
  bool get hasError => status == MessageStatus.error;

  ChatMessage copyWith({String? content, MessageStatus? status, String? errorText}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        status: status ?? this.status,
        errorText: errorText ?? this.errorText,
      );

  Map<String, String> toApiJson() => {'role': role.name, 'content': content};

  static int _counter = 0;
  static String _nextId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
