import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/core/feedback/feedback_service.dart';
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

class MemoryHistoryRepository implements GameHistoryRepository {
  MemoryHistoryRepository([List<GameResult>? initial]) : items = [...?initial];
  final List<GameResult> items;
  @override
  List<GameResult> all() => [...items]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  @override
  Future<void> save(GameResult result) async => items.add(result);
  @override
  Future<void> clear() async => items.clear();
}

class MemoryProgressRepository implements ProgressRepository {
  MemoryProgressRepository([this.value = const ProgressState()]);
  ProgressState value;
  @override
  ProgressState load() => value;
  @override
  Future<void> save(ProgressState state) async => value = state;
}

List<Override> testOverrides({
  FakeAuthRepository? auth,
  MemorySettingsRepository? settings,
  MemoryHistoryRepository? history,
  MemoryProgressRepository? progress,
  DateTime Function()? clock,
}) =>
    [
      progressRepositoryProvider.overrideWithValue(progress ?? MemoryProgressRepository()),
      if (clock != null) clockProvider.overrideWithValue(clock),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
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
}) =>
    GameResult(
      id: id ?? '${type.id}-${at?.millisecondsSinceEpoch ?? score}-$xp',
      gameType: type,
      score: score,
      correct: correct,
      wrong: wrong,
      maxCombo: 3,
      maxLevel: maxLevel,
      avgReactionMs: 800,
      bestReactionMs: 500,
      stars: 2,
      xp: xp,
      playedAt: at ?? DateTime(2026, 3, 10, 12),
      durationSeconds: durationSeconds,
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
