import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_service.dart';
import '../../data/repositories/offline_battle_repository.dart';
import '../../domain/entities/battle.dart';
import '../../domain/logic/server_clock.dart';
import '../../domain/repositories/battle_repository.dart';
import '../../domain/repositories/push_repository.dart';
import 'app_providers.dart';
import 'cloud_providers.dart';

/// Shared estimate of server time, refined by every battle call.
final serverClockProvider = Provider<ServerClock>((ref) => ServerClock());

/// Overridden in main() with Firebase when available.
final battleRepositoryProvider = Provider<BattleRepository>((ref) => const OfflineBattleRepository());

final pushServiceProvider = Provider<PushService>((ref) => const NoopPushService());

/// Null when push is unavailable (no Firebase).
final pushRepositoryProvider = Provider<PushRepository?>((ref) => null);

final battleProvider = StreamProvider.autoDispose.family<Battle?, String>(
  (ref, id) => ref.watch(battleRepositoryProvider).watchBattle(id),
);

final recentBattlesProvider = FutureProvider.autoDispose<List<Battle>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  return ref.watch(battleRepositoryProvider).recentBattles(uid);
});

/// Registers this device for push and keeps the server-side settings in sync
/// with the app's notification preferences, time zone and token.
class PushRegistrar extends Notifier<bool> {
  StreamSubscription<String>? _refresh;

  @override
  bool build() {
    final uid = ref.watch(currentUidProvider);
    final repo = ref.watch(pushRepositoryProvider);
    final s = ref.watch(settingsProvider);
    final prefs = PushPrefs(streak: s.notifyStreak, workout: s.notifyWorkout, friends: s.notifyFriends, battle: s.notifyBattle);
    ref.onDispose(() => _refresh?.cancel());
    if (uid == null || repo == null || !ref.watch(cloudRepositoryProvider).isAvailable) return false;
    final push = ref.watch(pushServiceProvider);
    final tz = ref.read(clockProvider)().timeZoneOffset.inMinutes;
    Future<void> save(String token) => repo.saveTarget(uid, token: token, tzOffsetMinutes: tz, prefs: prefs).catchError((Object _) {});
    Future.microtask(() async {
      final token = await push.register();
      if (token == null) return;
      await save(token);
      if (ref.mounted) state = true;
      _refresh = push.tokenRefreshes.listen(save);
    });
    return false;
  }
}

final pushRegistrarProvider = NotifierProvider<PushRegistrar, bool>(PushRegistrar.new);
