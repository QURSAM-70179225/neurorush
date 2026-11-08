import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/presentation/screens/achievements/achievements_screen.dart';
import 'package:neurorush/presentation/screens/friends/friends_screen.dart';
import 'package:neurorush/presentation/screens/leaderboard/leaderboard_screen.dart';

import '../helpers.dart';

Widget app(Widget home, {required FakeCloudRepository cloud, MemoryHistoryRepository? history}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/friends', builder: (_, _) => const Scaffold(body: Text('friends page'))),
  ]);
  return ProviderScope(
    overrides: testOverrides(cloud: cloud, history: history, clock: () => DateTime(2026, 11, 8, 12)),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('Leaderboard: entries, my rank, per-game metric, friends empty state', (tester) async {
    usePhoneSize(tester);
    final cloud = FakeCloudRepository()
      ..board.addAll(const [
        LeaderboardEntry(uid: 'x', value: 1200, rank: 1, username: 'ayesha', displayName: 'Ayesha', country: 'PK', level: 7),
        LeaderboardEntry(uid: 'y', value: 900, rank: 2, username: 'omar', level: 5),
        LeaderboardEntry(uid: testUid, value: 450, rank: 3, username: 'me_brain', level: 3),
      ]);
    await tester.pumpWidget(app(const LeaderboardScreen(), cloud: cloud));
    await tester.pumpAndSettle();

    expect(find.text('Ayesha'), findsOneWidget);
    expect(find.text('1,200 XP'), findsOneWidget);
    expect(find.text('me_brain (you)'), findsNWidgets(2)); // pinned + in list
    expect(find.textContaining('Resets in'), findsOneWidget);
    expect(cloud.calls, contains('board:global:xp'));

    await tester.tap(find.text('Memory Grid'));
    await tester.pumpAndSettle();
    expect(cloud.calls, contains('board:global:bestScores.memory_grid'));
    expect(find.text('1,200 pts'), findsOneWidget);

    final friendsTab = find.widgetWithText(Tab, 'Friends');
    await tester.ensureVisible(friendsTab);
    await tester.pumpAndSettle();
    await tester.tap(friendsTab);
    await tester.pumpAndSettle();
    expect(find.text('Find friends'), findsOneWidget);
    await tester.tap(find.text('Find friends'));
    await tester.pumpAndSettle();
    expect(find.text('friends page'), findsOneWidget);
  });

  testWidgets('Leaderboard offline shows a retry', (tester) async {
    usePhoneSize(tester);
    final cloud = FakeCloudRepository(online: false);
    await tester.pumpWidget(app(const LeaderboardScreen(), cloud: cloud));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    cloud.online = true;
    cloud.board.add(const LeaderboardEntry(uid: 'x', value: 10, rank: 1, username: 'zed'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('zed'), findsOneWidget);
  });

  testWidgets('Friends: requests, accept, add by username, errors, streaks', (tester) async {
    usePhoneSize(tester);
    final cloud = FakeCloudRepository()
      ..requests.add(const FriendRequest(fromUid: 'bilal-uid', fromUsername: 'bilal'))
      ..friendUids.add('sara-uid')
      ..profiles['sara-uid'] = const CloudProfile(uid: 'sara-uid', username: 'sara', displayName: 'Sara', level: 9, currentStreak: 12, streakDay: '2026-11-08')
      ..profiles['bilal-uid'] = const CloudProfile(uid: 'bilal-uid', username: 'bilal', displayName: 'Bilal')
      ..profiles[testUid] = const CloudProfile(uid: testUid, username: 'me_brain');
    await tester.pumpWidget(app(const FriendsScreen(), cloud: cloud));
    await tester.pumpAndSettle();

    expect(find.text('@me_brain'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    expect(semanticsWidget('12 day streak'), findsOneWidget);
    expect(find.text('Requests (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    expect(cloud.calls, contains('respond:bilal-uid:true'));
    expect(find.text('You and @bilal are now friends!'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@hamza');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(cloud.calls, contains('request:hamza'));
    expect(find.text('Friend request sent to @hamza'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ghost');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('No player called "ghost".'), findsOneWidget);
  });

  testWidgets('Achievements: local rounds unlock badges', (tester) async {
    usePhoneSize(tester);
    final history = MemoryHistoryRepository([sampleResult(id: 'r1', bestReactionMs: 280)]);
    await tester.pumpWidget(app(const AchievementsScreen(), cloud: FakeCloudRepository(), history: history));
    await tester.pumpAndSettle();
    expect(find.text('3 of 30 badges'), findsOneWidget); // First Steps, Quick Draw, Lightning Reflexes
    Finder label(RegExp re) => find.byWidgetPredicate((w) => w is Semantics && re.hasMatch(w.properties.label ?? ''));
    expect(label(RegExp(r'^Lightning Reflexes\..*Unlocked$')), findsOneWidget);
    await scrollTo(tester, label(RegExp(r'^Warming Up\..*Locked, 10 percent$')));
  });
}
