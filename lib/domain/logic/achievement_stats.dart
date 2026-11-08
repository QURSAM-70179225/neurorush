import '../entities/achievement.dart';
import '../entities/game_result.dart';
import '../entities/game_type.dart';
import 'brain_score.dart';
import 'xp_levels.dart';

/// Reaction times below this are ignored for records (matches the server).
const minRecordedReactionMs = 100;

/// Rounds with 100% accuracy and at least this many answers are "perfect".
const perfectMinAnswers = 10;

/// Builds the metrics used by achievements from local data. Mirrors
/// `achievementStats` in functions/src/progress.ts so badges unlock offline
/// exactly as they will on the server.
Map<String, num?> achievementStats({
  required List<GameResult> history,
  required int bestStreak,
  int friends = 0,
}) {
  var xp = 0, threeStar = 0, perfect = 0, maxCombo = 0, maxDifficulty = 0;
  int? fastest;
  final tried = <GameType>{};
  final best = <GameType, int>{};
  for (final r in history) {
    xp += r.xp;
    if (r.stars == 3) threeStar++;
    if (r.accuracy == 1 && r.attempts >= perfectMinAnswers) perfect++;
    if (r.maxCombo > maxCombo) maxCombo = r.maxCombo;
    if (r.maxLevel > maxDifficulty) maxDifficulty = r.maxLevel;
    final b = r.bestReactionMs;
    if (b != null && b >= minRecordedReactionMs && (fastest == null || b < fastest)) fastest = b;
    tried.add(r.gameType);
    if (r.durationSeconds == GameType.roundSeconds && r.score > (best[r.gameType] ?? 0)) best[r.gameType] = r.score;
  }
  return {
    'rounds': history.length,
    'xp': xp,
    'level': XpLevels.fromXp(xp).level,
    'bestStreak': bestStreak,
    'threeStarRounds': threeStar,
    'perfectRounds': perfect,
    'maxCombo': maxCombo,
    'fastestReactionMs': fastest,
    'gamesTried': tried.length,
    'brainScore': BrainScore.fromHistory(history).total,
    'maxDifficulty': maxDifficulty,
    'friends': friends,
    for (final e in best.entries) 'best_${e.key.id}': e.value,
  };
}

Set<String> unlockedIds(List<Achievement> catalogue, Map<String, num?> stats) =>
    {for (final a in catalogue) if (a.isMet(stats[a.metric])) a.id};
