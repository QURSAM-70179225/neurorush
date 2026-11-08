import '../../domain/entities/battle.dart';
import '../../domain/repositories/battle_repository.dart';
import '../../domain/repositories/cloud_repository.dart';

class OfflineBattleRepository implements BattleRepository {
  const OfflineBattleRepository();
  static const _e = CloudUnavailable('Battles need an online account.');

  @override
  bool get isAvailable => false;
  @override
  Future<MatchResult> findMatch() => Future.error(_e);
  @override
  Future<void> cancelMatch() async {}
  @override
  Stream<String?> watchMatch(String uid) => const Stream.empty();
  @override
  Future<String> startBotBattle() => Future.error(_e);
  @override
  Future<(String, String)> createInvite() => Future.error(_e);
  @override
  Future<String> joinInvite(String code) => Future.error(_e);
  @override
  Future<(String, String, bool)> challengeFriend(String friendUid) => Future.error(_e);
  @override
  Stream<Battle?> watchBattle(String battleId) => Stream.error(_e);
  @override
  Future<AnswerResult> submitAnswer(String battleId, int index, int choice) => Future.error(_e);
  @override
  Future<void> tick(String battleId) async {}
  @override
  Future<void> finish(String battleId) => Future.error(_e);
  @override
  Future<List<Battle>> recentBattles(String uid) async => const [];
}
