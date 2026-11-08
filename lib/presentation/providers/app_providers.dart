import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/feedback_service.dart';
import '../../data/local/hive_store.dart';
import '../../data/repositories/hive_game_history_repository.dart';
import '../../data/repositories/hive_progress_repository.dart';
import '../../data/repositories/hive_settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/entities/progress_state.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/logic/brain_score.dart';
import '../../domain/logic/daily_workout.dart';
import '../../domain/logic/player_stats.dart';
import '../../domain/logic/streak_logic.dart';
import '../../domain/logic/xp_levels.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/game_history_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import 'cloud_providers.dart';

/// Overridden in main() once Hive is open.
final hiveStoreProvider = Provider<HiveStore>(
  (ref) => throw UnimplementedError('hiveStoreProvider must be overridden'),
);

/// Overridden in main() with the Firebase or local implementation.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider must be overridden'),
);

/// Overridden in main() after sounds are preloaded.
final feedbackServiceProvider = Provider<FeedbackService>((ref) => FeedbackService());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HiveSettingsRepository(ref.watch(hiveStoreProvider).settings),
);

final gameHistoryRepositoryProvider = Provider<GameHistoryRepository>(
  (ref) => HiveGameHistoryRepository(ref.watch(hiveStoreProvider).sessions),
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => HiveProgressRepository(ref.watch(hiveStoreProvider).progress),
);

/// Overridable clock so streak logic can be tested.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = ref.watch(settingsRepositoryProvider).load();
    _applyToFeedback(s);
    return s;
  }

  void _applyToFeedback(AppSettings s) {
    ref.read(feedbackServiceProvider)
      ..soundOn = s.soundOn
      ..hapticsOn = s.hapticsOn;
  }

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    _applyToFeedback(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final authStateProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The current user, falling back to the repository's synchronous value while
/// the stream has not emitted yet.
final currentUserProvider = Provider<UserProfile?>((ref) {
  final async = ref.watch(authStateProvider);
  return async.hasValue ? async.value : ref.watch(authRepositoryProvider).currentUser;
});

/// Uid of the signed-in player (null when signed out).
final currentUidProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.uid);

/// Local history of the signed-in player, newest first.
class GameHistoryNotifier extends Notifier<List<GameResult>> {
  @override
  List<GameResult> build() {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const [];
    final repo = ref.watch(gameHistoryRepositoryProvider);
    // Rounds saved before accounts existed belong to the first player.
    Future.microtask(() async {
      if (await repo.claimUnowned(uid) > 0 && ref.mounted) ref.invalidateSelf();
    });
    return repo.all(uid);
  }

  /// Saves [result], marking it as a personal best when it beats every
  /// previous score in the same game. Returns the stored result.
  Future<GameResult> add(GameResult result) async {
    final previousBest = state
        .where((r) => r.gameType == result.gameType && r.durationSeconds == result.durationSeconds)
        .fold<int>(0, (best, r) => r.score > best ? r.score : best);
    final stored = result.copyWith(
      isPersonalBest: result.score > 0 && result.score > previousBest,
      ownerUid: ref.read(currentUidProvider),
    );
    await ref.read(gameHistoryRepositoryProvider).save(stored);
    state = [stored, ...state];
    await ref.read(progressProvider.notifier).refresh();
    unawaited(ref.read(syncProvider.notifier).sync());
    return stored;
  }

  /// Replaces a stored round (e.g. after it was synced).
  Future<void> replace(GameResult updated) async {
    await ref.read(gameHistoryRepositoryProvider).save(updated);
    state = [for (final r in state) r.id == updated.id ? updated : r];
  }

  /// Adds rounds downloaded from the cloud that are not stored locally.
  Future<int> mergeRemote(List<GameResult> remote) async {
    final have = {for (final r in state) r.id};
    final fresh = remote.where((r) => !have.contains(r.id)).toList();
    if (fresh.isEmpty) return 0;
    final repo = ref.read(gameHistoryRepositoryProvider);
    for (final r in fresh) {
      await repo.save(r);
    }
    state = [...state, ...fresh]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return fresh.length;
  }

  Future<void> clear() async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) await ref.read(gameHistoryRepositoryProvider).clear(uid);
    state = const [];
  }
}

final gameHistoryProvider =
    NotifierProvider<GameHistoryNotifier, List<GameResult>>(GameHistoryNotifier.new);

final playerStatsProvider = Provider<PlayerStats>(
  (ref) => PlayerStats.fromHistory(ref.watch(gameHistoryProvider)),
);

/// What changed in the streak during [ProgressNotifier.refresh].
class StreakUpdate {
  const StreakUpdate({this.frozenDays = 0, this.freezeEarned = false});
  final int frozenDays;
  final bool freezeEarned;
  bool get isEmpty => frozenDays == 0 && !freezeEarned;
}

class ProgressNotifier extends Notifier<ProgressState> {
  @override
  ProgressState build() {
    final uid = ref.watch(currentUidProvider);
    return uid == null ? const ProgressState() : ref.watch(progressRepositoryProvider).load(uid);
  }

  Future<void> _save(ProgressState s) async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) await ref.read(progressRepositoryProvider).save(uid, s);
  }

  Set<DateTime> _playedDays() => ref.read(gameHistoryProvider).map((r) => dayOf(r.playedAt)).toSet();

  /// Spends freezes to cover missed days and awards milestone freezes.
  /// Call on app start/resume and after each round.
  Future<StreakUpdate> refresh() async {
    // Online, the server applies and awards freezes (see submitGameSession).
    if (ref.read(cloudRepositoryProvider).isAvailable) return const StreakUpdate();
    final now = ref.read(clockProvider)();
    final played = _playedDays();
    var s = state;
    final toFreeze = StreakLogic.daysToFreeze(
      playedDays: played,
      frozenDays: s.frozenDays,
      freezesAvailable: s.freezes,
      today: now,
    );
    if (toFreeze.isNotEmpty) {
      s = s.copyWith(freezes: s.freezes - toFreeze.length, frozenDays: {...s.frozenDays, ...toFreeze});
    }
    final status = StreakLogic.compute(playedDays: played, frozenDays: s.frozenDays, today: now);
    final today = dayOf(now);
    var earned = false;
    if (status.playedToday &&
        StreakLogic.earnsFreeze(status.current) &&
        !s.freezeAwardDays.contains(today) &&
        s.freezes < StreakLogic.maxFreezes) {
      s = s.copyWith(freezes: s.freezes + 1, freezeAwardDays: {...s.freezeAwardDays, today});
      earned = true;
    }
    if (!identical(s, state)) {
      state = s;
      await _save(s);
    }
    return StreakUpdate(frozenDays: toFreeze.length, freezeEarned: earned);
  }

  Future<void> addFreezes(int n) async {
    state = state.copyWith(freezes: (state.freezes + n).clamp(0, StreakLogic.maxFreezes));
    await _save(state);
  }

  Future<void> markBrainTestDone() async {
    state = state.copyWith(brainTestDone: true);
    await _save(state);
  }

  Future<void> reset() async {
    state = const ProgressState();
    await _save(state);
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, ProgressState>(ProgressNotifier.new);

/// Streak computed from this device's rounds only (works offline).
final localStreakProvider = Provider<StreakStatus>((ref) {
  final history = ref.watch(gameHistoryProvider);
  final progress = ref.watch(progressProvider);
  return StreakLogic.compute(
    playedDays: history.map((r) => r.playedAt).toSet(),
    frozenDays: progress.frozenDays,
    today: ref.watch(clockProvider)(),
  );
});

final levelProvider = Provider<LevelInfo>((ref) => XpLevels.fromXp(ref.watch(playerStatsProvider).totalXp));

final brainScoreProvider = Provider<BrainScore>((ref) => BrainScore.fromHistory(ref.watch(gameHistoryProvider)));

final dailyWorkoutProvider = Provider<DailyWorkout>(
  (ref) => DailyWorkout.build(history: ref.watch(gameHistoryProvider), now: ref.watch(clockProvider)()),
);

/// Streak shown to the player: the server's (which applies freezes and counts
/// every device) merged with rounds on this device that are not uploaded yet.
final streakProvider = Provider<StreakStatus>((ref) {
  final local = ref.watch(localStreakProvider);
  final cloud = ref.watch(cloudRepositoryProvider);
  final p = ref.watch(cloudProfileProvider).value;
  if (!cloud.isAvailable || p == null) return local;
  final now = ref.watch(clockProvider)();
  final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final server = p.visibleStreak(now);
  return StreakStatus(
    current: server > local.current ? server : local.current,
    best: [p.bestStreak, local.best, server, local.current].reduce((a, b) => a > b ? a : b),
    playedToday: local.playedToday || p.streakDay == today,
  );
});

/// Streak freezes: server-held when online, device-held in offline mode.
final freezesProvider = Provider<int>((ref) {
  final cloud = ref.watch(cloudRepositoryProvider);
  final p = ref.watch(cloudProfileProvider).value;
  if (cloud.isAvailable && p != null) return p.entitlements.freezes;
  return ref.watch(progressProvider).freezes;
});
