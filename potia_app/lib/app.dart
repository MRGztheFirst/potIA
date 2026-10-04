import 'package:flutter/material.dart';

import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

class PotiaApp extends StatelessWidget {
  const PotiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PotIA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
