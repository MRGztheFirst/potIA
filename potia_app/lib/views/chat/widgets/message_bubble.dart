import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat_message.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/potia_logo.dart';
import 'typing_indicator.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * (message.isUser ? 0.78 : 0.82);
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.userBubble : AppColors.assistantBubble,
          border: message.isUser ? null : Border.all(color: Colors.orange.shade100),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(message.isUser ? 20 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 20),
          ),
        ),
        child: _BubbleContent(message: message, onRetry: onRetry),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: message.isUser
          ? Align(alignment: Alignment.centerRight, child: bubble)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const PotiaLogo(size: 32),
                const SizedBox(width: 8),
                Flexible(child: bubble),
              ],
            ),
    );
  }
}

class _BubbleContent extends StatelessWidget {
  const _BubbleContent({required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45, color: AppColors.textDark);

    if (message.isStreaming && message.content.isEmpty) return const TypingIndicator();

    if (message.isStreaming) {
      return Text.rich(
        TextSpan(
          text: message.content,
          style: textStyle,
          children: const [WidgetSpan(alignment: PlaceholderAlignment.middle, child: BlinkingCursor())],
        ),
      );
    }

    if (message.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.content.isNotEmpty) ...[
            SelectableText(message.content, style: textStyle),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message.errorText ?? 'Algo deu errado.',
                  style: textStyle?.copyWith(color: AppColors.error, fontSize: 14),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
        ],
      );
    }

    if (message.isUser) return SelectableText(message.content, style: textStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(message.content, style: textStyle),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Copiar receita',
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.content));
              if (context.mounted) showAppSnackBar(context, 'Resposta copiada!');
            },
          ),
        ),
      ],
    );
  }
}
