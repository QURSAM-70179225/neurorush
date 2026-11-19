import 'package:flutter/material.dart';

import '../../domain/entities/app_settings.dart';
import 'app_palette.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Premium neon themes (dark, high-contrast accents).
  static ThemeData neon(AppThemeMode mode) {
    final (primary, secondary, bg, surface) = switch (mode) {
      AppThemeMode.neonOcean => (const Color(0xFF00E5FF), const Color(0xFF448AFF), const Color(0xFF021024), const Color(0xFF0A2238)),
      AppThemeMode.neonSunset => (const Color(0xFFFF9100), const Color(0xFFFF4081), const Color(0xFF1A0612), const Color(0xFF2E0C1F)),
      _ => (const Color(0xFFE040FB), const Color(0xFF18FFFF), const Color(0xFF07021A), const Color(0xFF170A33)),
    };
    return _build(Brightness.dark, primary: primary, secondary: secondary, background: bg, surfaceColor: surface);
  }

  /// Colours used to preview a theme in Settings.
  static (Color, Color, Color) preview(AppThemeMode mode) {
    final t = switch (mode) {
      AppThemeMode.light => light(),
      AppThemeMode.dark || AppThemeMode.system => dark(),
      _ => neon(mode),
    };
    return (t.scaffoldBackgroundColor, t.colorScheme.primary, t.colorScheme.secondary);
  }

  /// Dark-mode accents: lighter tints of the brand colours so text buttons
  /// and links keep a WCAG AA contrast ratio (≥ 4.5:1) on the dark background.
  static const _darkViolet = Color(0xFFB3A1FF);
  static const _darkPink = Color(0xFFFF8AC0);

  /// Text colour with the best contrast on [c].
  static Color _on(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF1E1B33);

  static ThemeData _build(Brightness b, {Color? primary, Color? secondary, Color? background, Color? surfaceColor}) {
    final dark = b == Brightness.dark;
    final p = primary ?? (dark ? _darkViolet : AppPalette.violet);
    final sec = secondary ?? (dark ? _darkPink : AppPalette.pink);
    final scheme = ColorScheme.fromSeed(
      seedColor: p,
      brightness: b,
      primary: p,
      onPrimary: _on(p),
      secondary: sec,
      onSecondary: _on(sec),
      tertiary: AppPalette.cyan,
      surface: surfaceColor ?? (dark ? AppPalette.darkSurface : Colors.white),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    final text = base.textTheme.apply(
      bodyColor: dark ? Colors.white : const Color(0xFF1E1B33),
      displayColor: dark ? Colors.white : const Color(0xFF1E1B33),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    return base.copyWith(
      scaffoldBackgroundColor: background ?? (dark ? AppPalette.darkBg : AppPalette.lightBg),
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
        backgroundColor: surfaceColor ?? (dark ? AppPalette.darkSurface : Colors.white),
        indicatorColor: (primary ?? AppPalette.violet).withValues(alpha: 0.18),
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
