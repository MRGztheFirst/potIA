import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum AttachmentSource { camera, gallery, document }

Future<AttachmentSource?> showAttachmentSheet(
  BuildContext context, {
  required bool canAddImage,
  required bool canAddDocument,
}) {
  return showModalBottomSheet<AttachmentSource>(
    context: context,
    backgroundColor: AppColors.cream,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 16),
              child: Text('Enviar para a PotIA', style: Theme.of(context).textTheme.titleLarge),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SourceButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Câmera',
                  color: Colors.deepOrange,
                  enabled: canAddImage,
                  onTap: () => Navigator.pop(context, AttachmentSource.camera),
                ),
                _SourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Galeria',
                  color: Colors.pink,
                  enabled: canAddImage,
                  onTap: () => Navigator.pop(context, AttachmentSource.gallery),
                ),
                _SourceButton(
                  icon: Icons.description_rounded,
                  label: 'Documento',
                  color: Colors.indigo,
                  enabled: canAddDocument,
                  onTap: () => Navigator.pop(context, AttachmentSource.document),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Fotos de ingredientes, da geladeira ou de um prato · PDF, DOCX, TXT, MD e CSV',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
