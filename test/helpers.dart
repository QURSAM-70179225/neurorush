import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/core/feedback/feedback_service.dart';
import 'package:neurorush/data/repositories/offline_cloud_repository.dart';
import 'package:neurorush/domain/entities/achievement.dart';
import 'package:neurorush/domain/entities/ai_models.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/domain/repositories/cloud_repository.dart';
import 'package:neurorush/presentation/providers/cloud_providers.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/entities/progress_state.dart';
import 'package:neurorush/domain/entities/user_profile.dart';
import 'package:neurorush/domain/repositories/auth_repository.dart';
import 'package:neurorush/domain/repositories/game_history_repository.dart';
import 'package:neurorush/domain/repositories/progress_repository.dart';
import 'package:neurorush/domain/repositories/settings_repository.dart';
import 'package:neurorush/presentation/providers/app_providers.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({UserProfile? user, this.cloud = true}) : _user = user; // ignore: prefer_initializing_formals
  UserProfile? _user;
  final bool cloud;
  final _c = StreamController<UserProfile?>.broadcast();
  int googleCalls = 0;

  void _set(UserProfile? u) {
    _user = u;
    _c.add(u);
  }

  @override
  bool get supportsCloudAccounts => cloud;
  @override
  UserProfile? get currentUser => _user;
  @override
  Stream<UserProfile?> authStateChanges() async* {
    yield _user;
    yield* _c.stream;
  }

  @override
  Future<UserProfile> continueAsGuest() async {
    final u = const UserProfile(uid: 'guest-1', provider: AuthProviderKind.guest);
    _set(u);
    return u;
  }

  @override
  Future<UserProfile> signInWithGoogle() async {
    googleCalls++;
    final u = const UserProfile(uid: 'g', provider: AuthProviderKind.google, displayName: 'Ayesha');
    _set(u);
    return u;
  }

  @override
  Future<UserProfile> signInWithEmail(String email, String password) async {
    if (password != 'secret1') throw const AuthFailure('Email or password is incorrect.');
    final u = UserProfile(uid: 'e', provider: AuthProviderKind.email, email: email);
    _set(u);
    return u;
  }

  @override
  Future<UserProfile> registerWithEmail(String email, String password, String displayName) async {
    final u = UserProfile(uid: 'e', provider: AuthProviderKind.email, email: email, displayName: displayName);
    _set(u);
    return u;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<UserProfile> upgradeGuestWithGoogle() => signInWithGoogle();
  @override
  Future<UserProfile> upgradeGuestWithEmail(String e, String p, String n) => registerWithEmail(e, p, n);
  @override
  Future<void> signOut() async => _set(null);
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([this.value = const AppSettings()]);
  AppSettings value;
  @override
  AppSettings load() => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

/// Uid of the player signed in by default in tests.
const testUid = 'test-user';
const testUser = UserProfile(uid: testUid, provider: AuthProviderKind.guest);

class MemoryHistoryRepository implements GameHistoryRepository {
  MemoryHistoryRepository([List<GameResult>? initial]) : items = [...?initial];
  final List<GameResult> items;
  @override
  List<GameResult> all(String uid) =>
      items.where((r) => r.ownerUid == uid).toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  @override
  Future<void> save(GameResult result) async {
    items.removeWhere((r) => r.id == result.id);
    items.add(result);
  }

  @override
  Future<void> clear(String uid) async => items.removeWhere((r) => r.ownerUid == uid);
  @override
  Future<int> claimUnowned(String uid) async {
    var n = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].ownerUid == null) {
        items[i] = items[i].copyWith(ownerUid: uid);
        n++;
      }
    }
    return n;
  }
}

/// Single-player progress store (ignores the uid).
class MemoryProgressRepository implements ProgressRepository {
  MemoryProgressRepository([this.value = const ProgressState()]);
  ProgressState value;
  @override
  ProgressState load(String uid) => value;
  @override
  Future<void> save(String uid, ProgressState state) async => value = state;
}

/// The real badge catalogue shared with the server.
final testCatalogue = Achievement.parseCatalogue(File('shared/achievements.json').readAsStringSync());

List<Override> testOverrides({
  FakeAuthRepository? auth,
  MemorySettingsRepository? settings,
  MemoryHistoryRepository? history,
  MemoryProgressRepository? progress,
  DateTime Function()? clock,
  CloudRepository? cloud,
}) =>
    [
      cloudRepositoryProvider.overrideWithValue(cloud ?? const OfflineCloudRepository()),
      achievementCatalogProvider.overrideWithValue(testCatalogue),
      progressRepositoryProvider.overrideWithValue(progress ?? MemoryProgressRepository()),
      if (clock != null) clockProvider.overrideWithValue(clock),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository(user: testUser)),
      settingsRepositoryProvider.overrideWithValue(settings ?? MemorySettingsRepository()),
      gameHistoryRepositoryProvider.overrideWithValue(history ?? MemoryHistoryRepository()),
      feedbackServiceProvider.overrideWithValue(FeedbackService(enableAudio: false)),
    ];

/// Phone-sized viewport for widget tests.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Simulates the system "remove animations" setting (also disables confetti,
/// whose physics use wall-clock time and never settle under fake test time).
void useReducedMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Minimal evaluator for the expressions SpeedMath produces, so the test
/// checks answers independently of the generator.
int evaluate(String expr) {
  var e = expr.replaceAll('−', '-').replaceAll('×', '*').replaceAll('÷', '/').replaceAll(' ', '');
  final pct = RegExp(r'^(\d+)%of(\d+)$').firstMatch(e);
  if (pct != null) return int.parse(pct[1]!) * int.parse(pct[2]!) ~/ 100;
  e = e.replaceAllMapped(RegExp(r'(\d+)²'), (m) => '(${m[1]}*${m[1]})');
  var pos = 0;
  late int Function() parseExpr;
  int parseAtom() {
    if (e[pos] == '(') {
      pos++;
      final v = parseExpr();
      pos++; // ')'
      return v;
    }
    final start = pos;
    while (pos < e.length && RegExp(r'\d').hasMatch(e[pos])) {
      pos++;
    }
    return int.parse(e.substring(start, pos));
  }

  int parseTerm() {
    var v = parseAtom();
    while (pos < e.length && (e[pos] == '*' || e[pos] == '/')) {
      final op = e[pos++];
      final r = parseAtom();
      if (op == '/') {
        expect(v % r, 0, reason: 'division must be exact in "$expr"');
        v ~/= r;
      } else {
        v *= r;
      }
    }
    return v;
  }

  parseExpr = () {
    var v = parseTerm();
    while (pos < e.length && (e[pos] == '+' || e[pos] == '-')) {
      final op = e[pos++];
      final r = parseTerm();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  };
  return parseExpr();
}


/// A finished round for seeding histories in tests.
GameResult sampleResult({
  GameType type = GameType.speedMath,
  int score = 1000,
  int correct = 8,
  int wrong = 2,
  int maxLevel = 4,
  int xp = 50,
  int durationSeconds = 60,
  DateTime? at,
  String? id,
  String? ownerUid = testUid,
  SyncState syncState = SyncState.pending,
  int? bestReactionMs = 500,
  int stars = 2,
  int maxCombo = 3,
}) =>
    GameResult(
      id: id ?? '${type.id}-${at?.millisecondsSinceEpoch ?? score}-$xp',
      gameType: type,
      score: score,
      correct: correct,
      wrong: wrong,
      maxCombo: maxCombo,
      maxLevel: maxLevel,
      avgReactionMs: bestReactionMs == null ? null : 800,
      bestReactionMs: bestReactionMs,
      stars: stars,
      xp: xp,
      playedAt: at ?? DateTime(2026, 3, 10, 12),
      durationSeconds: durationSeconds,
      ownerUid: ownerUid,
      syncState: syncState,
    );

/// Finds a [Semantics] widget by its exact label (works without enabling the
/// semantics tree).
Finder semanticsWidget(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

/// Scrolls the innermost visible list until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250, scrollable: find.byType(Scrollable).last);
  // Let entrance animations of newly built items finish.
  await tester.pumpAndSettle();
}

/// In-memory stand-in for Firestore + Cloud Functions.
class FakeCloudRepository implements CloudRepository {
  FakeCloudRepository({this.online = true});

  bool online;
  final List<GameResult> submitted = [];
  final List<GameResult> remoteSessions = [];
  final Map<String, Map<String, Object?>> profileUpdates = {};
  final Map<String, CloudProfile> profiles = {};
  final Set<String> rejectIds = {};
  final List<LeaderboardEntry> board = [];
  final List<String> friendUids = [];
  final List<FriendRequest> requests = [];
  final Map<String, DateTime> serverBadges = {};
  final Map<String, String> usernames = {};
  final List<String> calls = [];
  final _profileCtl = StreamController<CloudProfile?>.broadcast();
  final _requestsCtl = StreamController<List<FriendRequest>>.broadcast();
  final _friendsCtl = StreamController<List<String>>.broadcast();

  void _check() {
    if (!online) throw const CloudUnavailable();
  }

  @override
  bool get isAvailable => true;

  @override
  Future<SubmitOutcome> submitSession(GameResult result) async {
    _check();
    calls.add('submit:${result.id}');
    if (rejectIds.contains(result.id)) return const SubmitOutcome(status: SubmitStatus.rejected, reason: 'score_too_high');
    if (submitted.any((r) => r.id == result.id)) return const SubmitOutcome(status: SubmitStatus.duplicate);
    submitted.add(result);
    return const SubmitOutcome(status: SubmitStatus.accepted);
  }

  @override
  Future<List<GameResult>> fetchRecentSessions(String uid, {int limit = 300}) async {
    _check();
    calls.add('fetch');
    return remoteSessions;
  }

  @override
  Stream<CloudProfile?> watchProfile(String uid) async* {
    yield profiles[uid];
    yield* _profileCtl.stream;
  }

  void emitProfile(CloudProfile p) {
    profiles[p.uid] = p;
    _profileCtl.add(p);
  }

  @override
  Future<List<CloudProfile>> fetchProfiles(List<String> uids) async {
    _check();
    return [for (final u in uids) if (profiles[u] != null) profiles[u]!];
  }

  @override
  Future<void> updateProfile(String uid, Map<String, Object?> fields) async {
    _check();
    (profileUpdates[uid] ??= {}).addAll(fields);
  }

  @override
  Future<String> claimUsername(String username) async {
    _check();
    final n = username.toLowerCase();
    if (usernames.containsKey(n)) throw const CloudFailure('That username is taken.');
    usernames[n] = 'me';
    return n;
  }

  @override
  Future<LeaderboardPage> leaderboard(LeaderboardQuery query, String myUid) async {
    _check();
    calls.add('board:${query.scope.name}:${query.field}');
    final list = query.scope == LeaderboardScope.friends
        ? board.where((e) => query.friendUids.contains(e.uid) || e.uid == myUid).toList()
        : board;
    return LeaderboardPage(entries: list, me: board.where((e) => e.uid == myUid).firstOrNull);
  }

  @override
  Stream<List<String>> watchFriendUids(String uid) async* {
    yield List.of(friendUids);
    yield* _friendsCtl.stream;
  }

  @override
  Stream<List<FriendRequest>> watchFriendRequests(String uid) async* {
    yield List.of(requests);
    yield* _requestsCtl.stream;
  }

  @override
  Future<FriendRequestResult> sendFriendRequest(String username) async {
    _check();
    calls.add('request:$username');
    if (username == 'ghost') throw const CloudFailure('No player called "ghost".');
    return FriendRequestResult.requested;
  }

  @override
  Future<void> respondFriendRequest(String fromUid, {required bool accept}) async {
    _check();
    calls.add('respond:$fromUid:$accept');
    requests.removeWhere((r) => r.fromUid == fromUid);
    _requestsCtl.add(List.of(requests));
    if (accept) {
      friendUids.add(fromUid);
      _friendsCtl.add(List.of(friendUids));
    }
  }

  @override
  Future<void> removeFriend(String friendUid) async {
    _check();
    friendUids.remove(friendUid);
    _friendsCtl.add(List.of(friendUids));
  }

  @override
  Stream<Map<String, DateTime>> watchUnlockedAchievements(String uid) => Stream.value(serverBadges);

  @override
  Future<void> saveDailyWorkout(String uid, String day, List<String> games, List<String> completed) async {
    _check();
    calls.add('workout:$day');
  }

  // --- AI ----------------------------------------------------------------------
  CoachTip? coachTip;
  Object? coachError;
  int coachCalls = 0;

  @override
  Future<CoachTip> getCoachTip(String day, int tzOffsetMinutes) async {
    _check();
    coachCalls++;
    if (coachError != null) throw coachError!;
    return coachTip!;
  }

  /// Puzzles to serve, with their correct answer index.
  final List<(EndlessPuzzle, int, String)> endlessQueue = [];
  final Map<String, (int, String)> _answers = {};
  int endlessRun = 0, endlessLives = 3, endlessBest = 0;
  Object? endlessError;
  final List<String> endlessAnswers = [];

  @override
  Future<EndlessPuzzle> getEndlessPuzzle({bool newRun = false}) async {
    _check();
    if (endlessError != null) throw endlessError!;
    if (newRun || endlessLives == 0) {
      endlessRun = 0;
      endlessLives = 3;
    }
    final (p, answer, explanation) = endlessQueue.removeAt(0);
    _answers[p.id] = (answer, explanation);
    return EndlessPuzzle(
      id: p.id, kind: p.kind, question: p.question, choices: p.choices, difficulty: p.difficulty, isAi: p.isAi,
      run: endlessRun, lives: endlessLives, bestRun: endlessBest, remainingToday: p.remainingToday,
    );
  }

  @override
  Future<EndlessVerdict> submitEndlessAnswer(String puzzleId, int answerIndex) async {
    _check();
    endlessAnswers.add('$puzzleId:$answerIndex');
    final (answer, explanation) = _answers.remove(puzzleId)!;
    final correct = answer == answerIndex;
    if (correct) {
      endlessRun++;
      if (endlessRun > endlessBest) endlessBest = endlessRun;
    } else {
      endlessLives--;
    }
    return EndlessVerdict(
      correct: correct, answerIndex: answer, explanation: explanation, run: endlessRun, lives: endlessLives,
      bestRun: endlessBest, gameOver: endlessLives == 0, timedOut: answerIndex == -1,
    );
  }
}
