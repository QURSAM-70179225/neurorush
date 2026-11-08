import '../entities/battle.dart';

/// 1v1 battles. Every write goes through Cloud Functions; the client only
/// watches battle documents.
abstract interface class BattleRepository {
  bool get isAvailable;

  /// Joins the queue or pairs with a waiting player.
  Future<MatchResult> findMatch();
  Future<void> cancelMatch();

  /// Emits the battle id once another player pairs with us.
  Stream<String?> watchMatch(String uid);

  Future<String> startBotBattle();

  /// Returns (battleId, code).
  Future<(String, String)> createInvite();
  Future<String> joinInvite(String code);

  /// Invites a friend with a push notification; returns (battleId, code, notified).
  Future<(String, String, bool)> challengeFriend(String friendUid);

  Stream<Battle?> watchBattle(String battleId);
  Future<AnswerResult> submitAnswer(String battleId, int index, int choice);

  /// Advances practice-bot battles; also refines the server clock.
  Future<void> tick(String battleId);
  Future<void> finish(String battleId);

  Future<List<Battle>> recentBattles(String uid);
}
