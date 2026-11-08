import 'dart:math' as math;

import '../entities/game_result.dart';
import '../entities/game_type.dart';
import '../entities/skill.dart';
import 'streak_logic.dart';

/// Overall 0–1000 Brain Score: five skills worth 0–200 each.
class BrainScore {
  const BrainScore(this.skills);

  static const maxPerSkill = 200;
  static const maxTotal = maxPerSkill * 5;

  /// How many recent rounds per skill are considered.
  static const window = 12;

  /// Weight multiplier per older round (newest round weighs most).
  static const decay = 0.8;

  final Map<Skill, int> skills;

  int get total => skills.values.fold(0, (a, b) => a + b);
  int of(Skill s) => skills[s] ?? 0;
  bool get hasData => skills.values.any((v) => v > 0);

  Skill? get weakest {
    if (!hasData) return null;
    return Skill.values.reduce((a, b) => of(b) < of(a) ? b : a);
  }

  /// Performance of a single round in 0..1, independent of round length:
  /// score per minute vs. the 3-star target, accuracy and level reached.
  static double sessionRating(GameResult r) {
    final perMinute = r.durationSeconds <= 0 ? 0 : r.score * 60 / r.durationSeconds;
    final target = r.gameType.starThresholds[2];
    final scorePart = math.min(1.0, perMinute / target);
    final levelPart = (r.maxLevel - 1).clamp(0, 9) / 9;
    return (0.55 * scorePart + 0.3 * r.accuracy + 0.15 * levelPart).clamp(0.0, 1.0);
  }

  /// [history] must be newest first.
  factory BrainScore.fromHistory(List<GameResult> history) {
    final bySkill = {for (final s in Skill.values) s: <GameResult>[]};
    for (final r in history) {
      final list = bySkill[r.gameType.skill]!;
      if (list.length < window) list.add(r);
    }
    return BrainScore({
      for (final e in bySkill.entries) e.key: _skillScore(e.value),
    });
  }

  static int _skillScore(List<GameResult> recent) {
    if (recent.isEmpty) return 0;
    var weight = 1.0, sum = 0.0, weights = 0.0;
    for (final r in recent) {
      sum += sessionRating(r) * weight;
      weights += weight;
      weight *= decay;
    }
    return (sum / weights * maxPerSkill).round();
  }

  /// Daily skill score snapshots (for progress charts): for each of the last
  /// [days] days, the skill score using rounds played up to that day.
  static List<(DateTime, BrainScore)> dailyTrend(List<GameResult> history, {int days = 7, DateTime? now}) {
    final today = dayOf(now ?? DateTime.now());
    final oldestFirst = history.reversed.toList();
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          final end = DateTime(day.year, day.month, day.day + 1);
          final upTo = oldestFirst.where((r) => r.playedAt.isBefore(end)).toList().reversed.toList();
          return (day, BrainScore.fromHistory(upTo));
        }(),
    ];
  }

  static GameType gameFor(Skill s) => GameType.values.firstWhere((g) => g.skill == s);
}
