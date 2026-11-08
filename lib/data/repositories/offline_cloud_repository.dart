import '../../domain/entities/ai_models.dart';
import '../../domain/entities/cloud_models.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/repositories/cloud_repository.dart';

/// Used when Firebase is not available: every online feature reports that it
/// is unavailable, streams stay empty, single-player keeps working.
class OfflineCloudRepository implements CloudRepository {
  const OfflineCloudRepository();

  static const _unavailable = CloudUnavailable(
    'Online features are unavailable right now. Your progress is saved on this device.',
  );

  @override
  bool get isAvailable => false;

  @override
  Future<SubmitOutcome> submitSession(GameResult result) => Future.error(_unavailable);
  @override
  Future<List<GameResult>> fetchRecentSessions(String uid, {int limit = 300}) => Future.error(_unavailable);
  @override
  Stream<CloudProfile?> watchProfile(String uid) => Stream.value(null);
  @override
  Future<List<CloudProfile>> fetchProfiles(List<String> uids) => Future.error(_unavailable);
  @override
  Future<void> updateProfile(String uid, Map<String, Object?> fields) => Future.error(_unavailable);
  @override
  Future<String> claimUsername(String username) => Future.error(_unavailable);
  @override
  Future<LeaderboardPage> leaderboard(LeaderboardQuery query, String myUid) => Future.error(_unavailable);
  @override
  Stream<List<String>> watchFriendUids(String uid) => Stream.value(const []);
  @override
  Stream<List<FriendRequest>> watchFriendRequests(String uid) => Stream.value(const []);
  @override
  Future<FriendRequestResult> sendFriendRequest(String username) => Future.error(_unavailable);
  @override
  Future<void> respondFriendRequest(String fromUid, {required bool accept}) => Future.error(_unavailable);
  @override
  Future<void> removeFriend(String friendUid) => Future.error(_unavailable);
  @override
  Stream<Map<String, DateTime>> watchUnlockedAchievements(String uid) => Stream.value(const {});
  @override
  Future<void> saveDailyWorkout(String uid, String day, List<String> games, List<String> completed) =>
      Future.error(_unavailable);

  @override
  Future<CoachTip> getCoachTip(String day, int tzOffsetMinutes) => Future.error(_unavailable);
  @override
  Future<EndlessPuzzle> getEndlessPuzzle({bool newRun = false}) => Future.error(_unavailable);
  @override
  Future<EndlessVerdict> submitEndlessAnswer(String puzzleId, int answerIndex) => Future.error(_unavailable);
}
