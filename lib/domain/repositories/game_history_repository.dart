import '../entities/game_result.dart';

abstract interface class GameHistoryRepository {
  /// All results, newest first.
  List<GameResult> all();
  Future<void> save(GameResult result);
  Future<void> clear();
}
