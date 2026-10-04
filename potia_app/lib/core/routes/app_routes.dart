import 'package:flutter/material.dart';

import '../../views/auth/auth_view.dart';
import '../../views/chat/chat_view.dart';
import '../../views/onboarding/onboarding_view.dart';
import '../../views/splash/splash_view.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String chat = '/chat';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return _fade(const OnboardingView(), settings);
      case auth:
        final tab = settings.arguments is AuthTab ? settings.arguments! as AuthTab : AuthTab.login;
        return _slideUp(AuthView(initialTab: tab), settings);
      case chat:
        return _fade(const ChatView(), settings);
      case splash:
      default:
        return _fade(const SplashView(), settings);
    }
  }

  static PageRouteBuilder<dynamic> _fade(Widget page, RouteSettings settings) => PageRouteBuilder<dynamic>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  static PageRouteBuilder<dynamic> _slideUp(Widget page, RouteSettings settings) => PageRouteBuilder<dynamic>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        ),
      );
}
