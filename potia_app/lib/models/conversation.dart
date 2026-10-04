import 'chat_message.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.preview = '',
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Conversa',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        preview: json['preview'] as String? ?? '',
      );

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String preview;

  ConversationSummary copyWith({String? title}) => ConversationSummary(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        preview: preview,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'preview': preview,
      };
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Conversa',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        messages: [
          for (final item in json['messages'] as List<dynamic>? ?? const [])
            ChatMessage.fromJson(item as Map<String, dynamic>),
        ],
      );

  static const int _titleLength = 42;

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  static String titleFor(ChatMessage first) {
    final text = first.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isNotEmpty) {
      return text.length <= _titleLength ? text : '${text.substring(0, _titleLength).trimRight()}…';
    }
    if (first.images.isNotEmpty) return first.images.length == 1 ? 'Foto' : '${first.images.length} fotos';
    if (first.documents.isNotEmpty) return first.documents.first.name;
    return 'Nova conversa';
  }

  ConversationSummary get summary {
    final withText = messages.where((m) => m.content.trim().isNotEmpty);
    final preview = withText.isEmpty ? '' : withText.last.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    return ConversationSummary(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      preview: preview.length > 80 ? preview.substring(0, 80) : preview,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };
}
