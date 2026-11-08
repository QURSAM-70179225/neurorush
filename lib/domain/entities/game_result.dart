import 'game_type.dart';

/// The outcome of one completed 60-second round.
class GameResult {
  const GameResult({
    required this.id,
    required this.gameType,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.maxCombo,
    required this.maxLevel,
    required this.avgReactionMs,
    required this.bestReactionMs,
    required this.stars,
    required this.xp,
    required this.playedAt,
    required this.durationSeconds,
    this.isPersonalBest = false,
    this.synced = false,
  });

  final String id;
  final GameType gameType;
  final int score;
  final int correct;
  final int wrong;
  final int maxCombo;
  final int maxLevel;

  /// Average reaction time of answers in milliseconds, or null if none.
  final int? avgReactionMs;
  final int? bestReactionMs;
  final int stars;
  final int xp;
  final DateTime playedAt;
  final int durationSeconds;
  final bool isPersonalBest;

  /// Whether this session has been uploaded to the cloud (used from Phase 3).
  final bool synced;

  int get attempts => correct + wrong;

  /// Accuracy in the range 0..1.
  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  int get accuracyPercent => (accuracy * 100).round();

  GameResult copyWith({bool? isPersonalBest, bool? synced}) => GameResult(
        id: id,
        gameType: gameType,
        score: score,
        correct: correct,
        wrong: wrong,
        maxCombo: maxCombo,
        maxLevel: maxLevel,
        avgReactionMs: avgReactionMs,
        bestReactionMs: bestReactionMs,
        stars: stars,
        xp: xp,
        playedAt: playedAt,
        durationSeconds: durationSeconds,
        isPersonalBest: isPersonalBest ?? this.isPersonalBest,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'gameId': gameType.id,
        'score': score,
        'correct': correct,
        'wrong': wrong,
        'maxCombo': maxCombo,
        'maxLevel': maxLevel,
        'avgReactionMs': avgReactionMs,
        'bestReactionMs': bestReactionMs,
        'stars': stars,
        'xp': xp,
        'playedAt': playedAt.toUtc().toIso8601String(),
        'durationSeconds': durationSeconds,
        'isPersonalBest': isPersonalBest,
        'synced': synced,
      };

  /// Returns null for records of games that no longer exist or are corrupt.
  static GameResult? tryFromMap(Map<dynamic, dynamic> map) {
    try {
      final type = GameType.fromId(map['gameId'] as String);
      if (type == null) return null;
      return GameResult(
        id: map['id'] as String,
        gameType: type,
        score: (map['score'] as num).toInt(),
        correct: (map['correct'] as num).toInt(),
        wrong: (map['wrong'] as num).toInt(),
        maxCombo: (map['maxCombo'] as num).toInt(),
        maxLevel: (map['maxLevel'] as num).toInt(),
        avgReactionMs: (map['avgReactionMs'] as num?)?.toInt(),
        bestReactionMs: (map['bestReactionMs'] as num?)?.toInt(),
        stars: (map['stars'] as num).toInt(),
        xp: (map['xp'] as num).toInt(),
        playedAt: DateTime.parse(map['playedAt'] as String).toLocal(),
        durationSeconds: (map['durationSeconds'] as num).toInt(),
        isPersonalBest: map['isPersonalBest'] as bool? ?? false,
        synced: map['synced'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
