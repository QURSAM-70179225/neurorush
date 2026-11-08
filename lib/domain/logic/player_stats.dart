import '../entities/game_result.dart';
import '../entities/game_type.dart';

/// Aggregated statistics derived from the local game history.
class PlayerStats {
  const PlayerStats._({
    required this.totalXp,
    required this.gamesPlayed,
    required this.gamesToday,
    required this.totalStars,
    required this.bestScores,
    required this.bestResults,
    required this.averageAccuracy,
    required this.bestReactionMs,
  });

  factory PlayerStats.fromHistory(List<GameResult> history, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var xp = 0, stars = 0, todayCount = 0, correct = 0, attempts = 0;
    int? bestReaction;
    final best = <GameType, GameResult>{};
    for (final r in history) {
      xp += r.xp;
      stars += r.stars;
      correct += r.correct;
      attempts += r.attempts;
      final p = r.playedAt;
      if (p.year == today.year && p.month == today.month && p.day == today.day) {
        todayCount++;
      }
      final b = r.bestReactionMs;
      if (b != null && (bestReaction == null || b < bestReaction)) bestReaction = b;
      final current = best[r.gameType];
      if (current == null || r.score > current.score) best[r.gameType] = r;
    }
    return PlayerStats._(
      totalXp: xp,
      gamesPlayed: history.length,
      gamesToday: todayCount,
      totalStars: stars,
      bestResults: best,
      bestScores: best.map((k, v) => MapEntry(k, v.score)),
      averageAccuracy: attempts == 0 ? 0 : correct / attempts,
      bestReactionMs: bestReaction,
    );
  }

  static final empty = PlayerStats.fromHistory(const []);

  final int totalXp;
  final int gamesPlayed;
  final int gamesToday;
  final int totalStars;
  final Map<GameType, int> bestScores;
  final Map<GameType, GameResult> bestResults;

  /// Accuracy across every answer ever given, 0..1.
  final double averageAccuracy;
  final int? bestReactionMs;

  int bestScoreFor(GameType type) => bestScores[type] ?? 0;
}
