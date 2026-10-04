import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color primary = Colors.deepOrange;
  static const Color accent = Colors.orangeAccent;
  static const Color cream = Color(0xFFFFF8F0);
  static const Color creamDeep = Color(0xFFFCEBD9);
  static const Color assistantBubble = Color(0xFFFFE8D2);
  static const Color userBubble = Color(0xFFEFEAE6);
  static const Color textDark = Color(0xFF3E2723);
  static const Color textMuted = Color(0xFF8D6E63);
  static const Color error = Color(0xFFC62828);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Colors.deepOrange, Colors.orangeAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.cream,
      error: AppColors.error,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.cream,
    );

    final body = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textDark,
      displayColor: AppColors.textDark,
    );

    TextStyle? rounded(TextStyle? style) =>
        GoogleFonts.quicksand(textStyle: style, fontWeight: FontWeight.w700);

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
    final buttonText = GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800);

    return base.copyWith(
      textTheme: body.copyWith(
        displaySmall: rounded(body.displaySmall),
        headlineLarge: rounded(body.headlineLarge),
        headlineMedium: rounded(body.headlineMedium),
        headlineSmall: rounded(body.headlineSmall),
        titleLarge: rounded(body.titleLarge),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.primary, width: 1.6),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  static TextStyle brandTitle({double size = 40, Color color = AppColors.primary}) =>
      GoogleFonts.quicksand(fontSize: size, fontWeight: FontWeight.w700, color: color);

  static InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffix,
    String? hint,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, color: AppColors.textMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(AppColors.creamDeep),
      enabledBorder: border(AppColors.creamDeep),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.6),
    );
  }
}
