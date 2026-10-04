import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../widgets/potia_logo.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _logoScale = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.65, curve: Curves.elasticOut));
    _textFade = CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(_textFade);
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final results = await Future.wait<bool>([
      auth.tryAutoLogin(),
      Future<bool>.delayed(const Duration(milliseconds: 2200), () => true),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(results.first ? AppRoutes.chat : AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.cream, AppColors.creamDeep],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(scale: _logoScale, child: const AnimatedPotiaLogo(size: 120)),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: _textFade,
              child: SlideTransition(
                position: _textSlide,
                child: Column(
                  children: [
                    Text('PotIA', style: AppTheme.brandTitle(size: 48)),
                    const SizedBox(height: 6),
                    Text(
                      'Sua chef de bolso com inteligência artificial',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            FadeTransition(
              opacity: _textFade,
              child: const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
