import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/user_profile.dart';
import 'package:neurorush/presentation/providers/app_providers.dart';
import 'package:neurorush/presentation/providers/cloud_providers.dart';

import '../helpers.dart';

void main() {
  final now = DateTime(2026, 3, 10, 18);

  ProviderContainer make({
    required FakeCloudRepository cloud,
    required MemoryHistoryRepository history,
    FakeAuthRepository? auth,
  }) {
    final c = ProviderContainer(overrides: testOverrides(cloud: cloud, history: history, clock: () => now, auth: auth));
    addTearDown(c.dispose);
    // Keep the sync notifier alive for the whole test.
    c.listen(syncProvider, (_, _) {});
    return c;
  }

  test('uploads pending rounds, marks accepted and rejected ones', () async {
    final cloud = FakeCloudRepository()..rejectIds.add('cheat');
    final history = MemoryHistoryRepository([
      sampleResult(id: 'a', at: now.subtract(const Duration(hours: 2))),
      sampleResult(id: 'cheat', at: now.subtract(const Duration(hours: 1))),
      sampleResult(id: 'old', syncState: SyncState.synced, at: now.subtract(const Duration(days: 1))),
    ]);
    final c = make(cloud: cloud, history: history);
    expect(c.read(pendingSyncCountProvider), 2);

    await c.read(syncProvider.notifier).sync();

    expect(cloud.submitted.map((r) => r.id), ['a']);
    final byId = {for (final r in history.items) r.id: r};
    expect(byId['a']!.syncState, SyncState.synced);
    expect(byId['cheat']!.syncState, SyncState.rejected);
    expect(byId['cheat']!.rejectReason, 'score_too_high');
    expect(c.read(pendingSyncCountProvider), 0);
    expect(c.read(syncProvider).phase, SyncPhase.idle);
    // Country and daily workout are published; streaks are computed by the server.
    expect(cloud.profileUpdates[testUid]!.containsKey('country'), isTrue);
    expect(cloud.profileUpdates[testUid]!.containsKey('currentStreak'), isFalse);
    expect(cloud.calls, contains('workout:2026-03-10'));
  });

  test('offline: rounds stay pending, then sync when back online', () async {
    final cloud = FakeCloudRepository(online: false);
    final history = MemoryHistoryRepository([sampleResult(id: 'a', at: now)]);
    final c = make(cloud: cloud, history: history);

    await c.read(syncProvider.notifier).sync();
    expect(c.read(syncProvider).phase, SyncPhase.offline);
    expect(c.read(pendingSyncCountProvider), 1);

    cloud.online = true;
    await c.read(syncProvider.notifier).sync();
    expect(c.read(pendingSyncCountProvider), 0);
    expect(cloud.submitted, hasLength(1));
  });

  test('downloads rounds played on another device once', () async {
    final cloud = FakeCloudRepository()
      ..remoteSessions.addAll([
        sampleResult(id: 'remote1', syncState: SyncState.synced, at: now.subtract(const Duration(days: 2))),
        sampleResult(id: 'local', syncState: SyncState.synced, at: now),
      ]);
    final history = MemoryHistoryRepository([sampleResult(id: 'local', syncState: SyncState.synced, at: now)]);
    final c = make(cloud: cloud, history: history);
    await c.read(syncProvider.notifier).sync();
    expect(c.read(gameHistoryProvider).map((r) => r.id), ['local', 'remote1']);
    await c.read(syncProvider.notifier).sync();
    expect(cloud.calls.where((x) => x == 'fetch'), hasLength(1));
  });

  test('history and progress are separate per player', () async {
    final auth = FakeAuthRepository(user: testUser);
    final history = MemoryHistoryRepository([
      sampleResult(id: 'mine', at: now),
      sampleResult(id: 'theirs', ownerUid: 'someone-else', at: now),
    ]);
    final c = make(cloud: FakeCloudRepository(online: false), history: history, auth: auth);
    expect(c.read(gameHistoryProvider).map((r) => r.id), ['mine']);

    await auth.signInWithEmail('x@y.z', 'secret1'); // uid "e"
    await Future<void>.delayed(Duration.zero);
    expect(c.read(currentUserProvider)?.provider, AuthProviderKind.email);
    expect(c.read(gameHistoryProvider), isEmpty);

    await c.read(gameHistoryProvider.notifier).add(sampleResult(id: 'new', ownerUid: null, at: now));
    expect(history.items.firstWhere((r) => r.id == 'new').ownerUid, 'e');
  });
}
