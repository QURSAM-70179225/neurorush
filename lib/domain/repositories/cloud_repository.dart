import '../entities/ai_models.dart';
import '../entities/cloud_models.dart';
import '../entities/game_result.dart';

/// Network / server unavailable: the operation can be retried later.
class CloudUnavailable implements Exception {
  const CloudUnavailable([this.message = 'You are offline. Connect to the internet and try again.']);
  final String message;
  @override
  String toString() => message;
}

/// The server refused the request; [message] is safe to show.
class CloudFailure implements Exception {
  const CloudFailure(this.message, {this.code});
  final String message;

  /// Server error code, e.g. "resource-exhausted" or "failed-precondition".
  final String? code;
  @override
  String toString() => message;
}

/// Online features (Firestore + Cloud Functions).
abstract interface class CloudRepository {
  /// False when the app runs without Firebase (offline-only build/start).
  bool get isAvailable;

  Future<SubmitOutcome> submitSession(GameResult result);
  Future<List<GameResult>> fetchRecentSessions(String uid, {int limit = 300});

  Stream<CloudProfile?> watchProfile(String uid);
  Future<List<CloudProfile>> fetchProfiles(List<String> uids);
  Future<void> updateProfile(String uid, Map<String, Object?> fields);
  Future<String> claimUsername(String username);

  Future<LeaderboardPage> leaderboard(LeaderboardQuery query, String myUid);

  Stream<List<String>> watchFriendUids(String uid);
  Stream<List<FriendRequest>> watchFriendRequests(String uid);
  Future<FriendRequestResult> sendFriendRequest(String username);
  Future<void> respondFriendRequest(String fromUid, {required bool accept});
  Future<void> removeFriend(String friendUid);

  /// Badge id → unlock time, as granted by the server.
  Stream<Map<String, DateTime>> watchUnlockedAchievements(String uid);

  Future<void> saveDailyWorkout(String uid, String day, List<String> games, List<String> completed);

  /// AI Brain Coach tip for the player's local [day] (yyyy-MM-dd).
  Future<CoachTip> getCoachTip(String day, int tzOffsetMinutes);

  /// Next Endless puzzle; [newRun] starts over with full lives.
  Future<EndlessPuzzle> getEndlessPuzzle({bool newRun = false});

  /// [answerIndex] -1 means the timer ran out.
  Future<EndlessVerdict> submitEndlessAnswer(String puzzleId, int answerIndex);
}
