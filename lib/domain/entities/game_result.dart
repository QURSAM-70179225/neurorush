import 'game_type.dart';

/// Upload state of a locally stored round.
enum SyncState { pending, synced, rejected }

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
    this.syncState = SyncState.pending,
    this.ownerUid,
    this.rejectReason,
    this.xpBoosted = false,
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

  /// Whether this round has been uploaded and accepted by the server.
  final SyncState syncState;

  /// The account this round belongs to (local history is per player).
  final String? ownerUid;

  /// Why the server refused the round (anti-cheat), if it did.
  final String? rejectReason;

  /// XP was doubled by a rewarded ad.
  final bool xpBoosted;

  bool get synced => syncState == SyncState.synced;

  int get attempts => correct + wrong;

  /// Accuracy in the range 0..1.
  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  int get accuracyPercent => (accuracy * 100).round();

  GameResult copyWith({
    bool? isPersonalBest,
    SyncState? syncState,
    String? ownerUid,
    String? rejectReason,
    int? xp,
    bool? xpBoosted,
  }) =>
      GameResult(
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
        xp: xp ?? this.xp,
        playedAt: playedAt,
        durationSeconds: durationSeconds,
        isPersonalBest: isPersonalBest ?? this.isPersonalBest,
        syncState: syncState ?? this.syncState,
        ownerUid: ownerUid ?? this.ownerUid,
        rejectReason: rejectReason ?? this.rejectReason,
        xpBoosted: xpBoosted ?? this.xpBoosted,
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
        'syncState': syncState.name,
        'ownerUid': ownerUid,
        'rejectReason': rejectReason,
        'xpBoosted': xpBoosted,
      };

  /// Payload for the submitGameSession Cloud Function.
  Map<String, Object?> toSubmitPayload() => {
        'id': id,
        'gameId': gameType.id,
        'score': score,
        'correct': correct,
        'wrong': wrong,
        'maxCombo': maxCombo,
        'maxLevel': maxLevel,
        'avgReactionMs': avgReactionMs,
        'bestReactionMs': bestReactionMs,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'durationSeconds': durationSeconds,
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
        syncState: SyncState.values.firstWhere(
          (s) => s.name == map['syncState'],
          // Phase 1/2 records stored a boolean.
          orElse: () => map['synced'] == true ? SyncState.synced : SyncState.pending,
        ),
        ownerUid: map['ownerUid'] as String?,
        rejectReason: map['rejectReason'] as String?,
        xpBoosted: map['xpBoosted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
