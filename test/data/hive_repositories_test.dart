import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:neurorush/data/local/hive_store.dart';
import 'package:neurorush/data/repositories/hive_game_history_repository.dart';
import 'package:neurorush/data/repositories/hive_progress_repository.dart';
import 'package:neurorush/data/repositories/hive_settings_repository.dart';
import 'package:neurorush/data/repositories/local_auth_repository.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/entities/progress_state.dart';
import 'package:neurorush/domain/repositories/auth_repository.dart';

void main() {
  late Directory dir;
  late HiveStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('neurorush_hive');
    store = await HiveStore.openAt(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('settings persist', () async {
    final repo = HiveSettingsRepository(store.settings);
    expect(repo.load().soundOn, isTrue);
    await repo.save(const AppSettings(soundOn: false, themeMode: AppThemeMode.dark, onboardingDone: true));
    final s = repo.load();
    expect(s.soundOn, isFalse);
    expect(s.themeMode, AppThemeMode.dark);
    expect(s.onboardingDone, isTrue);
  });

  test('history is stored and returned newest first', () async {
    final repo = HiveGameHistoryRepository(store.sessions);
    GameResult r(String id, DateTime at) => GameResult(
          id: id,
          gameType: GameType.colorClash,
          score: 100,
          correct: 1,
          wrong: 0,
          maxCombo: 1,
          maxLevel: 1,
          avgReactionMs: null,
          bestReactionMs: null,
          stars: 1,
          xp: 10,
          playedAt: at,
          durationSeconds: 60,
        );
    await repo.save(r('old', DateTime(2026, 1, 1)).copyWith(ownerUid: 'a'));
    await repo.save(r('new', DateTime(2026, 2, 1)).copyWith(ownerUid: 'a'));
    await repo.save(r('other', DateTime(2026, 2, 2)).copyWith(ownerUid: 'b'));
    await store.sessions.put('junk', {'gameId': 'unknown'});
    expect(repo.all('a').map((e) => e.id), ['new', 'old']);
    expect(repo.all('b').map((e) => e.id), ['other']);
    await repo.clear('a');
    expect(repo.all('a'), isEmpty);
    expect(repo.all('b'), hasLength(1));
  });

  test('rounds from before accounts are claimed by the first player', () async {
    final repo = HiveGameHistoryRepository(store.sessions);
    // A Phase 1/2 record: no owner, boolean "synced".
    await store.sessions.put('legacy', {
      'id': 'legacy',
      'gameId': 'speed_math',
      'score': 10,
      'correct': 1,
      'wrong': 0,
      'maxCombo': 1,
      'maxLevel': 1,
      'avgReactionMs': null,
      'bestReactionMs': null,
      'stars': 1,
      'xp': 5,
      'playedAt': DateTime(2026).toUtc().toIso8601String(),
      'durationSeconds': 60,
      'synced': false,
    });
    expect(repo.all('a'), isEmpty);
    expect(await repo.claimUnowned('a'), 1);
    expect(await repo.claimUnowned('b'), 0);
    final r = repo.all('a').single;
    expect(r.syncState, SyncState.pending);
    expect(r.ownerUid, 'a');
  });

  test('progress is stored per player; legacy record migrates once', () async {
    final repo = HiveProgressRepository(store.progress);
    await store.progress.put('progress', const ProgressState(freezes: 2, brainTestDone: true).toMap());
    expect(repo.load('a').freezes, 2);
    expect(repo.load('a').brainTestDone, isTrue);
    expect(repo.load('b').brainTestDone, isFalse);
    await repo.save('b', const ProgressState(freezes: 0));
    expect(repo.load('b').freezes, 0);
    expect(repo.load('a').freezes, 2);
  });

  test('local guest keeps the same id after sign out', () async {
    final repo = LocalAuthRepository(store.auth);
    expect(repo.currentUser, isNull);
    final first = await repo.continueAsGuest();
    expect(first.isGuest, isTrue);
    await repo.signOut();
    expect(repo.currentUser, isNull);
    final again = await LocalAuthRepository(store.auth).continueAsGuest();
    expect(again.uid, first.uid);
  });

  test('local auth refuses cloud sign-in with a readable message', () async {
    final repo = LocalAuthRepository(store.auth);
    expect(repo.supportsCloudAccounts, isFalse);
    await expectLater(repo.signInWithGoogle(), throwsA(isA<AuthFailure>()));
  });
}
