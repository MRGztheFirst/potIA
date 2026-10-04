import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PotiaLogo extends StatelessWidget {
  const PotiaLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Icon(Icons.soup_kitchen, color: Colors.white, size: size * 0.52),
    );
  }
}

class AnimatedPotiaLogo extends StatefulWidget {
  const AnimatedPotiaLogo({super.key, this.size = 128});

  final double size;

  @override
  State<AnimatedPotiaLogo> createState() => _AnimatedPotiaLogoState();
}

class _AnimatedPotiaLogoState extends State<AnimatedPotiaLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          Widget ring(double phase) {
            final progress = (t + phase) % 1.0;
            return Opacity(
              opacity: (1 - progress) * 0.35,
              child: Container(
                width: size * (1 + progress * 0.6),
                height: size * (1 + progress * 0.6),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
              ),
            );
          }

          final breathing = 1 + 0.04 * (1 - (2 * t - 1).abs());
          return Stack(
            alignment: Alignment.center,
            children: [
              ring(0),
              ring(0.5),
              Transform.scale(scale: breathing, child: child),
            ],
          );
        },
        child: PotiaLogo(size: size),
      ),
    );
  }
}
