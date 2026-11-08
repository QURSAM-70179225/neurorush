import 'package:flutter/material.dart';

import '../../domain/entities/game_type.dart';
import '../../domain/entities/skill.dart';

/// Brand colors and gradients. Feedback colors switch to a color-blind safe
/// pair (blue / orange) when the accessibility option is on.
class AppPalette {
  const AppPalette._();

  static const violet = Color(0xFF6C4DFF);
  static const pink = Color(0xFFFF4D9D);
  static const cyan = Color(0xFF22C7EE);
  static const amber = Color(0xFFFFB020);
  static const mint = Color(0xFF2ED3A0);
  static const flame = Color(0xFFFF7A1A);

  static const darkBg = Color(0xFF0F0B1E);
  static const darkSurface = Color(0xFF1B1533);
  static const lightBg = Color(0xFFF6F4FF);

  static const brandGradient = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color correct(bool colorBlind) =>
      colorBlind ? const Color(0xFF0072B2) : const Color(0xFF22C55E);
  static Color wrong(bool colorBlind) =>
      colorBlind ? const Color(0xFFE69F00) : const Color(0xFFEF4444);

  static LinearGradient gameGradient(GameType type) => switch (type) {
        GameType.memoryGrid => const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.colorClash => const LinearGradient(
            colors: [Color(0xFFFF4D9D), Color(0xFFFF7A1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.speedMath => const LinearGradient(
            colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.shapeMatch => const LinearGradient(
            colors: [Color(0xFF14B8A6), Color(0xFF0EA5E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.numberSequence => const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.wordScramble => const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.oddOneOut => const LinearGradient(
            colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        GameType.pathRecall => const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      };

  static IconData gameIcon(GameType type) => switch (type) {
        GameType.memoryGrid => Icons.grid_view_rounded,
        GameType.colorClash => Icons.palette_rounded,
        GameType.speedMath => Icons.calculate_rounded,
        GameType.shapeMatch => Icons.category_rounded,
        GameType.numberSequence => Icons.pin_rounded,
        GameType.wordScramble => Icons.abc_rounded,
        GameType.oddOneOut => Icons.search_rounded,
        GameType.pathRecall => Icons.route_rounded,
      };

  static Color skillColor(Skill s) => switch (s) {
        Skill.memory => const Color(0xFF7C3AED),
        Skill.focus => pink,
        Skill.speed => cyan,
        Skill.logic => amber,
        Skill.language => mint,
      };
}
