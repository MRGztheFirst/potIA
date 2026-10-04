enum AttachmentType { image, document }

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.type,
    required this.name,
    required this.path,
    this.sizeBytes = 0,
    this.text,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: json['id'] as String,
        type: AttachmentType.values.byName(json['type'] as String),
        name: json['name'] as String? ?? 'arquivo',
        path: json['path'] as String,
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
        text: json['text'] as String?,
      );

  final String id;
  final AttachmentType type;
  final String name;
  final String path;
  final int sizeBytes;
  final String? text;

  bool get isImage => type == AttachmentType.image;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  String get readableSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'path': path,
        'size': sizeBytes,
        if (text != null) 'text': text,
      };
}
