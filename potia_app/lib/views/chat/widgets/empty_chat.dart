import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/potia_logo.dart';

class EmptyChat extends StatelessWidget {
  const EmptyChat({super.key, required this.firstName, required this.onSuggestion});

  final String firstName;
  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    'Como fazer brigadeiro de panela?',
    'Tenho ovos e cenoura. O que faço?',
    'Como assar pudim em banho-maria?',
    'Ideia de almoço rápido com frango',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final greeting = firstName.isEmpty ? 'Olá!' : 'Olá, $firstName!';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          const PotiaLogo(size: 88),
          const SizedBox(height: 20),
          Text(greeting, style: textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'O que vamos cozinhar hoje?',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final suggestion in _suggestions)
                ActionChip(
                  avatar: const Icon(Icons.restaurant_menu_rounded, size: 18, color: AppColors.primary),
                  label: Text(suggestion),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.orange.shade100),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onPressed: () => onSuggestion(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
