import '../entities/game_result.dart';
import '../entities/game_type.dart';
import '../entities/skill.dart';
import 'brain_score.dart';
import 'streak_logic.dart';

class DailyWorkout {
  const DailyWorkout({required this.day, required this.games, required this.completed});

  final DateTime day;

  /// Three games targeting the player's weakest skills.
  final List<GameType> games;

  /// Games from [games] already played today.
  final Set<GameType> completed;

  bool get isComplete => completed.length == games.length;
  GameType? get nextGame => games.where((g) => !completed.contains(g)).firstOrNull;

  /// Picks 3 games for the weakest skills (ties broken by fewest rounds
  /// played). When a skill has several games, the choice rotates by day.
  static DailyWorkout build({required List<GameResult> history, required DateTime now}) {
    final day = dayOf(now);
    final score = BrainScore.fromHistory(history);
    final counts = {for (final s in Skill.values) s: 0};
    for (final r in history) {
      counts[r.gameType.skill] = counts[r.gameType.skill]! + 1;
    }
    final skills = [...Skill.values]
      ..sort((a, b) {
        final c = score.of(a).compareTo(score.of(b));
        return c != 0 ? c : counts[a]!.compareTo(counts[b]!);
      });
    final dayNumber = day.difference(DateTime(2024)).inDays;
    final games = <GameType>[
      for (final s in skills.take(3))
        () {
          final options = GameType.values.where((g) => g.skill == s).toList();
          return options[dayNumber % options.length];
        }(),
    ];
    final playedToday = history.where((r) => dayOf(r.playedAt) == day).map((r) => r.gameType).toSet();
    return DailyWorkout(day: day, games: games, completed: games.where(playedToday.contains).toSet());
  }
}
