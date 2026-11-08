import '../entities/game_result.dart';

/// Local (offline-first) store of finished rounds, kept per player.
abstract interface class GameHistoryRepository {
  /// Rounds of [uid], newest first.
  List<GameResult> all(String uid);

  Future<void> save(GameResult result);

  /// Deletes the rounds of [uid].
  Future<void> clear(String uid);

  /// Assigns rounds stored before accounts existed (no owner) to [uid].
  /// Returns how many were claimed.
  Future<int> claimUnowned(String uid);
}
