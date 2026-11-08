import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.violet,
      brightness: b,
      primary: AppPalette.violet,
      secondary: AppPalette.pink,
      tertiary: AppPalette.cyan,
      surface: dark ? AppPalette.darkSurface : Colors.white,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    final text = base.textTheme.apply(
      bodyColor: dark ? Colors.white : const Color(0xFF1E1B33),
      displayColor: dark ? Colors.white : const Color(0xFF1E1B33),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    return base.copyWith(
      scaffoldBackgroundColor: dark ? AppPalette.darkBg : AppPalette.lightBg,
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: dark ? Colors.white : const Color(0xFF1E1B33),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          shape: rounded,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          shape: rounded,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF261E45) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? AppPalette.darkSurface : Colors.white,
        indicatorColor: AppPalette.violet.withValues(alpha: 0.18),
        // 11sp keeps "Leaderboard" on one line with 5 tabs on 360dp phones.
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
