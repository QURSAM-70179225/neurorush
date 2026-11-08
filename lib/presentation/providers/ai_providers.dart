import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/hive_coach_cache.dart';
import '../../domain/entities/ai_models.dart';
import '../../domain/repositories/coach_cache.dart';
import '../../domain/repositories/cloud_repository.dart';
import 'app_providers.dart';
import 'cloud_providers.dart';

final coachCacheProvider = Provider<CoachTipCache>((ref) => HiveCoachCache(ref.watch(hiveStoreProvider).settings));

sealed class CoachState {
  const CoachState();
}

/// The daily workout is not finished yet.
class CoachLocked extends CoachState {
  const CoachLocked();
}

/// Workout done; its rounds are still uploading.
class CoachSyncing extends CoachState {
  const CoachSyncing();
}

class CoachReady extends CoachState {
  const CoachReady(this.tip);
  final CoachTip tip;
}

class CoachUnavailable extends CoachState {
  const CoachUnavailable(this.message);
  final String message;
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Coach tip for today's completed workout. AI tips are cached on the device.
final coachProvider = FutureProvider<CoachState>((ref) async {
  final uid = ref.watch(currentUidProvider);
  final workout = ref.watch(dailyWorkoutProvider);
  if (uid == null || !workout.isComplete) return const CoachLocked();
  final day = dayKey(workout.day);
  final cache = ref.watch(coachCacheProvider);
  final cached = cache.read(uid, day);
  if (cached != null) return CoachReady(cached);

  final cloud = ref.watch(cloudRepositoryProvider);
  if (!cloud.isAvailable) {
    return const CoachUnavailable('The Brain Coach needs an online account.');
  }
  if (ref.watch(pendingSyncCountProvider) > 0) {
    final phase = ref.watch(syncProvider.select((s) => s.phase));
    return phase == SyncPhase.offline
        ? const CoachUnavailable('Connect to the internet to get today’s coach tip.')
        : const CoachSyncing();
  }
  try {
    final tip = await cloud.getCoachTip(day, ref.read(clockProvider)().timeZoneOffset.inMinutes);
    if (tip.isAi) await cache.write(uid, day, tip);
    return CoachReady(tip);
  } on CloudUnavailable {
    return const CoachUnavailable('Connect to the internet to get today’s coach tip.');
  } on CloudFailure catch (e) {
    return CoachUnavailable(e.message);
  }
});
