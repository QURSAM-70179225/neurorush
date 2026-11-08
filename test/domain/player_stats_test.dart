import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/logic/player_stats.dart';

GameResult result(GameType t, int score, DateTime at, {int correct = 8, int wrong = 2, int? best}) => GameResult(
      id: '$t$score${at.millisecondsSinceEpoch}',
      gameType: t,
      score: score,
      correct: correct,
      wrong: wrong,
      maxCombo: 4,
      maxLevel: 3,
      avgReactionMs: 700,
      bestReactionMs: best,
      stars: 2,
      xp: 50,
      playedAt: at,
      durationSeconds: 60,
    );

void main() {
  test('aggregates XP, stars, accuracy, bests and today count', () {
    final now = DateTime(2026, 5, 10, 15);
    final stats = PlayerStats.fromHistory([
      result(GameType.speedMath, 900, now, best: 450),
      result(GameType.speedMath, 1200, now.subtract(const Duration(days: 1)), best: 380),
      result(GameType.colorClash, 500, now, correct: 5, wrong: 5),
    ], now: now);
    expect(stats.gamesPlayed, 3);
    expect(stats.gamesToday, 2);
    expect(stats.totalXp, 150);
    expect(stats.totalStars, 6);
    expect(stats.bestScoreFor(GameType.speedMath), 1200);
    expect(stats.bestScoreFor(GameType.memoryGrid), 0);
    expect(stats.averageAccuracy, closeTo(21 / 30, 1e-9));
    expect(stats.bestReactionMs, 380);
  });

  test('empty history', () {
    expect(PlayerStats.empty.gamesPlayed, 0);
    expect(PlayerStats.empty.averageAccuracy, 0);
  });

  test('GameResult survives a storage round trip', () {
    final r = result(GameType.memoryGrid, 777, DateTime(2026, 1, 2, 3, 4), best: 300).copyWith(isPersonalBest: true);
    final back = GameResult.tryFromMap(r.toMap())!;
    expect(back.toMap(), r.toMap());
    expect(back.accuracyPercent, 80);
  });

  test('corrupt or unknown records are skipped', () {
    expect(GameResult.tryFromMap({'gameId': 'nope'}), isNull);
    expect(GameResult.tryFromMap({'gameId': 'speed_math', 'score': 'x'}), isNull);
  });
}
