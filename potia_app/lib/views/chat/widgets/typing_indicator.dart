import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'PotIA está cozinhando sua resposta',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍳', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'PotIA está cozinhando sua resposta',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = (_controller.value - index * 0.18) % 1.0;
                final bounce = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0;
                return Transform.translate(
                  offset: Offset(0, -4 * bounce),
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.35 + 0.65 * bounce),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 16,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
