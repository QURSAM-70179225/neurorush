import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/offline_cloud_repository.dart';
import '../../domain/entities/achievement.dart';
import '../../domain/entities/cloud_models.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/logic/achievement_stats.dart';
import '../../domain/logic/weeks.dart';
import '../../domain/repositories/cloud_repository.dart';
import 'app_providers.dart';

/// Overridden in main() with Firebase when available.
final cloudRepositoryProvider = Provider<CloudRepository>((ref) => const OfflineCloudRepository());

/// Badge catalogue from shared/achievements.json, loaded in main().
final achievementCatalogProvider = Provider<List<Achievement>>((ref) => const []);

/// Emits when the device regains a network connection. Overridden in tests.
final connectivityRestoredProvider = Provider<Stream<void>>((ref) => const Stream.empty());

/// The signed-in player's public cloud profile (null offline / not created yet).
final cloudProfileProvider = StreamProvider<CloudProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(cloudRepositoryProvider).watchProfile(uid);
});

/// Country used for the country leaderboard: profile → device → Pakistan.
final myCountryProvider = Provider<String>((ref) {
  final p = ref.watch(cloudProfileProvider).value?.country;
  return p ?? PlatformDispatcher.instance.locale.countryCode?.toUpperCase() ?? 'PK';
});

final friendUidsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(cloudRepositoryProvider).watchFriendUids(uid);
});

final friendRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(cloudRepositoryProvider).watchFriendRequests(uid);
});

/// Profiles of all friends, sorted by current streak then XP.
final friendProfilesProvider = FutureProvider<List<CloudProfile>>((ref) async {
  final uids = await ref.watch(friendUidsProvider.future);
  if (uids.isEmpty) return const [];
  final now = ref.read(clockProvider)();
  final list = await ref.watch(cloudRepositoryProvider).fetchProfiles(uids);
  return list
    ..sort((a, b) {
      final s = b.visibleStreak(now).compareTo(a.visibleStreak(now));
      return s != 0 ? s : b.xp.compareTo(a.xp);
    });
});

final leaderboardProvider = FutureProvider.autoDispose.family<LeaderboardPage, LeaderboardQuery>((ref, q) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const LeaderboardPage(entries: []);
  return ref.watch(cloudRepositoryProvider).leaderboard(q, uid);
});

final serverAchievementsProvider = StreamProvider<Map<String, DateTime>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const {});
  return ref.watch(cloudRepositoryProvider).watchUnlockedAchievements(uid);
});

/// Metrics for achievements from local history (works offline).
final achievementStatsProvider = Provider<Map<String, num?>>((ref) {
  final history = ref.watch(gameHistoryProvider);
  final streak = ref.watch(streakProvider);
  final friends = ref.watch(cloudProfileProvider).value?.friends ?? 0;
  final cloudBest = ref.watch(cloudProfileProvider).value?.bestStreak ?? 0;
  return achievementStats(history: history, bestStreak: streak.best > cloudBest ? streak.best : cloudBest, friends: friends);
});

/// Unlocked badges: earned locally or granted by the server. Value is the
/// server unlock time when known.
final unlockedAchievementsProvider = Provider<Map<String, DateTime?>>((ref) {
  final catalogue = ref.watch(achievementCatalogProvider);
  final local = unlockedIds(catalogue, ref.watch(achievementStatsProvider));
  final server = ref.watch(serverAchievementsProvider).value ?? const {};
  return {for (final id in local) id: server[id], ...server};
});

final pendingSyncCountProvider = Provider<int>(
  (ref) => ref.watch(gameHistoryProvider).where((r) => r.syncState == SyncState.pending).length,
);

// --- sync ----------------------------------------------------------------------

enum SyncPhase { idle, syncing, offline, error, unavailable }

class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSyncedAt, this.message});
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;
}

/// Uploads pending rounds, downloads rounds from other devices, and publishes
/// the streak to the cloud profile. Safe to call often; runs one at a time.
class SyncNotifier extends Notifier<SyncStatus> {
  bool _running = false;
  bool _again = false;
  final Set<String> _pulled = {};

  @override
  SyncStatus build() {
    final cloud = ref.watch(cloudRepositoryProvider);
    if (!cloud.isAvailable) return const SyncStatus(phase: SyncPhase.unavailable);
    ref.listen(currentUidProvider, (prev, next) {
      if (next != null && next != prev) Future.microtask(sync);
    });
    final sub = ref.watch(connectivityRestoredProvider).listen((_) => sync());
    ref.onDispose(sub.cancel);
    return const SyncStatus();
  }

  Future<void> sync() async {
    final cloud = ref.read(cloudRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (!cloud.isAvailable || uid == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = SyncStatus(phase: SyncPhase.syncing, lastSyncedAt: state.lastSyncedAt);
    try {
      final history = ref.read(gameHistoryProvider.notifier);
      if (!_pulled.contains(uid)) {
        await history.mergeRemote(await cloud.fetchRecentSessions(uid));
        _pulled.add(uid);
      }
      final pending = ref.read(gameHistoryProvider).where((r) => r.syncState == SyncState.pending).toList().reversed;
      for (final r in pending) {
        if (ref.read(currentUidProvider) != uid) break; // signed out mid-sync
        final outcome = await cloud.submitSession(r);
        await history.replace(outcome.status == SubmitStatus.rejected
            ? r.copyWith(syncState: SyncState.rejected, rejectReason: outcome.reason ?? 'rejected')
            : r.copyWith(syncState: SyncState.synced));
      }
      await _publishProfile(cloud, uid);
      state = SyncStatus(phase: SyncPhase.idle, lastSyncedAt: ref.read(clockProvider)());
    } on CloudUnavailable catch (e) {
      state = SyncStatus(phase: SyncPhase.offline, lastSyncedAt: state.lastSyncedAt, message: e.message);
    } on CloudFailure catch (e) {
      state = SyncStatus(phase: SyncPhase.error, lastSyncedAt: state.lastSyncedAt, message: e.message);
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _publishProfile(CloudRepository cloud, String uid) async {
    final streak = ref.read(streakProvider);
    final now = ref.read(clockProvider)();
    final profile = ref.read(cloudProfileProvider).value;
    final lastActiveDay = streak.playedToday ? now : now.subtract(const Duration(days: 1));
    final day = '${lastActiveDay.year.toString().padLeft(4, '0')}-'
        '${lastActiveDay.month.toString().padLeft(2, '0')}-${lastActiveDay.day.toString().padLeft(2, '0')}';
    final best = streak.best > (profile?.bestStreak ?? 0) ? streak.best : profile!.bestStreak;
    await cloud.updateProfile(uid, {
      'currentStreak': streak.current,
      'bestStreak': best < streak.current ? streak.current : best,
      'streakDay': day,
      if (profile?.country == null) 'country': ref.read(myCountryProvider),
      if (profile?.displayName == null && ref.read(currentUserProvider)?.displayName != null)
        'displayName': ref.read(currentUserProvider)!.displayName,
    });
    final w = ref.read(dailyWorkoutProvider);
    final wd = '${w.day.year.toString().padLeft(4, '0')}-${w.day.month.toString().padLeft(2, '0')}-${w.day.day.toString().padLeft(2, '0')}';
    await cloud.saveDailyWorkout(uid, wd, [for (final g in w.games) g.id], [for (final g in w.completed) g.id]);
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);

/// Week id of the current weekly leaderboard.
final currentWeekIdProvider = Provider<String>((ref) => isoWeekId(ref.watch(clockProvider)()));
