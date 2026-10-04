import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat_attachment.dart';

class AttachmentImage extends StatelessWidget {
  const AttachmentImage({super.key, required this.attachment, required this.size, this.radius = 14});

  final ChatAttachment attachment;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(attachment.path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: AppColors.creamDeep,
          child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class DocumentChip extends StatelessWidget {
  const DocumentChip({super.key, required this.attachment, this.maxWidth = 220});

  final ChatAttachment attachment;
  final double maxWidth;

  static (IconData, Color) iconFor(String extension) => switch (extension) {
        'pdf' => (Icons.picture_as_pdf_rounded, const Color(0xFFD32F2F)),
        'docx' => (Icons.article_rounded, const Color(0xFF1565C0)),
        'csv' => (Icons.table_chart_rounded, const Color(0xFF2E7D32)),
        _ => (Icons.description_rounded, AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = iconFor(attachment.extension);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.creamDeep),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark),
                  ),
                  Text(
                    '${attachment.extension.toUpperCase()} · ${attachment.readableSize}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageAttachments extends StatelessWidget {
  const MessageAttachments({super.key, required this.attachments, required this.maxWidth});

  final List<ChatAttachment> attachments;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final documents = attachments.where((a) => !a.isImage).toList();
    final tile = images.length == 1 ? maxWidth : (maxWidth - 6) / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              for (final image in images)
                GestureDetector(
                  onTap: () => openImageViewer(context, image),
                  child: Hero(tag: image.id, child: AttachmentImage(attachment: image, size: tile)),
                ),
            ],
          ),
        for (final document in documents)
          Padding(
            padding: EdgeInsets.only(top: images.isEmpty && document == documents.first ? 0 : 6),
            child: DocumentChip(attachment: document, maxWidth: maxWidth),
          ),
      ],
    );
  }
}

class PendingAttachments extends StatelessWidget {
  const PendingAttachments({super.key, required this.attachments, required this.onRemove, this.isLoading = false});

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onRemove;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          for (final attachment in attachments)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  attachment.isImage
                      ? AttachmentImage(attachment: attachment, size: 64, radius: 12)
                      : SizedBox(height: 64, child: DocumentChip(attachment: attachment, maxWidth: 180)),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Material(
                      color: AppColors.textDark,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onRemove(attachment),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isLoading)
            const SizedBox(
              width: 64,
              height: 64,
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
            ),
        ],
      ),
    );
  }
}

void openImageViewer(BuildContext context, ChatAttachment image) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(image.name, style: const TextStyle(fontSize: 16)),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Hero(
                tag: image.id,
                child: Image.file(
                  File(image.path),
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
