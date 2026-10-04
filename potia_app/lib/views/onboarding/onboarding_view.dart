import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_view.dart';

class _OnboardingPage {
  const _OnboardingPage({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;
}

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  static const _pages = [
    _OnboardingPage(
      icon: Icons.soup_kitchen,
      title: 'Receitas na palma da mão',
      description: 'Pergunte como fazer qualquer prato e receba ingredientes e o passo a passo completo.',
    ),
    _OnboardingPage(
      icon: Icons.kitchen,
      title: 'Use o que tem em casa',
      description: 'Conte quais ingredientes estão na geladeira e a PotIA sugere o que cozinhar.',
    ),
    _OnboardingPage(
      icon: Icons.local_fire_department,
      title: 'Dicas de chef, sem complicação',
      description: 'Tempo de preparo, rendimento e técnicas como banho-maria e fogo brando explicadas de um jeito simples.',
    ),
  ];

  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openAuth(AuthTab tab) => Navigator.of(context).pushNamed(AppRoutes.auth, arguments: tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text('PotIA', style: AppTheme.brandTitle(size: 28)),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _OnboardingPageView(page: _pages[index]),
              ),
            ),
            _PageDots(count: _pages.length, current: _currentPage),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => _openAuth(AuthTab.register),
                    child: const Text('Criar minha conta'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _openAuth(AuthTab.login),
                    child: const Text('Já tenho conta'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.orange.shade100, AppColors.cream],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.orange.shade200, width: 2),
              ),
              child: Icon(page.icon, size: 96, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 40),
          Text(page.title, textAlign: TextAlign.center, style: textTheme.headlineSmall),
          const SizedBox(height: 14),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}
