import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/core/theme/app_theme.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/presentation/game/results_args.dart';
import 'package:neurorush/presentation/games/game_play_screen.dart';
import 'package:neurorush/presentation/screens/auth/auth_screen.dart';
import 'package:neurorush/presentation/screens/battle/battle_screen.dart';
import 'package:neurorush/presentation/screens/games/games_screen.dart';
import 'package:neurorush/presentation/screens/home/home_screen.dart';
import 'package:neurorush/presentation/screens/profile/profile_screen.dart';
import 'package:neurorush/presentation/screens/results/results_screen.dart';
import 'package:neurorush/presentation/screens/settings/settings_screen.dart';

import '../helpers.dart';

/// Automated accessibility checks (Flutter's guideline matchers) on the main
/// screens, in light and dark themes.
void main() {
  final screens = <String, Widget Function()>{
    'Auth': () => const AuthScreen(),
    'Home': () => const HomeScreen(),
    'Games': () => const GamesScreen(),
    'Battle': () => const BattleScreen(),
    'Profile': () => const ProfileScreen(),
    'Settings': () => const SettingsScreen(),
    'Results': () => ResultsScreen(args: ResultsArgs(result: sampleResult(stars: 3))),
    'Game intro': () => const GamePlayScreen(type: GameType.colorClash),
  };

  for (final dark in [false, true]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} meets accessibility guidelines (${dark ? 'dark' : 'light'})', (tester) async {
        usePhoneSize(tester);
        useReducedMotion(tester);
        final handle = tester.ensureSemantics();
        final cloud = FakeCloudRepository()..profiles[testUid] = const CloudProfile(uid: testUid, username: 'tester', trophies: 40);
        await tester.pumpWidget(ProviderScope(
          overrides: testOverrides(cloud: cloud, history: MemoryHistoryRepository([sampleResult(id: 'a11y-1')])),
          child: MaterialApp.router(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => e.value())]),
          ),
        ));
        await tester.pump(const Duration(seconds: 2));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
