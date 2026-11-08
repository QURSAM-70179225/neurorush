import 'dart:math' as math;

import '../entities/game_type.dart';

/// Stars and XP rules shared by every mini-game.
class Rewards {
  const Rewards._();

  /// Minimum accuracy needed for 3 stars.
  static const double threeStarAccuracy = 0.8;

  /// 1 star for finishing a round with at least one correct answer, 2 or 3
  /// for reaching the game's thresholds. 0 if nothing was answered correctly.
  static int starsFor({
    required GameType type,
    required int score,
    required double accuracy,
    required int correct,
  }) {
    if (correct == 0) return 0;
    final t = type.starThresholds;
    if (score >= t[2] && accuracy >= threeStarAccuracy) return 3;
    if (score >= t[1]) return 2;
    return 1;
  }

  /// XP earned: score-based, plus a bonus per star and for high accuracy.
  /// Every finished round earns at least 5 XP to reward practice.
  static int xpFor({
    required int score,
    required int stars,
    required double accuracy,
  }) {
    final base = score ~/ 20;
    final starBonus = stars * 15;
    final accuracyBonus = accuracy >= 0.9 ? 20 : 0;
    return math.max(5, base + starBonus + accuracyBonus);
  }
}
