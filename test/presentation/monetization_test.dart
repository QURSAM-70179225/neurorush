import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/core/billing/billing_service.dart';
import 'package:neurorush/domain/entities/app_config.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/domain/entities/shop.dart';
import 'package:neurorush/domain/logic/interstitial_policy.dart';
import 'package:neurorush/domain/repositories/cloud_repository.dart';
import 'package:neurorush/presentation/game/results_args.dart';
import 'package:neurorush/presentation/providers/shop_providers.dart';
import 'package:neurorush/presentation/screens/privacy/privacy_screen.dart';
import 'package:neurorush/presentation/screens/profile/profile_screen.dart';
import 'package:neurorush/presentation/screens/results/results_screen.dart';
import 'package:neurorush/presentation/screens/settings/settings_screen.dart';
import 'package:neurorush/presentation/screens/shop/shop_screen.dart';

import '../helpers.dart';

void main() {
  group('rules', () {
    test('interstitial frequency cap', () {
      final p = InterstitialPolicy(everyNGames: 3, minInterval: const Duration(minutes: 2));
      final t = DateTime(2026, 1, 1, 12);
      p.gameFinished();
      p.gameFinished();
      expect(p.shouldShow(t, adFree: false), isFalse);
      p.gameFinished();
      expect(p.shouldShow(t, adFree: false), isTrue);
      expect(p.shouldShow(t, adFree: true), isFalse);
      p.shown(t);
      for (var i = 0; i < 3; i++) {
        p.gameFinished();
      }
      expect(p.shouldShow(t.add(const Duration(minutes: 1)), adFree: false), isFalse, reason: 'too soon');
      expect(p.shouldShow(t.add(const Duration(minutes: 2)), adFree: false), isTrue);
    });

    test('entitlements', () {
      final now = DateTime(2026, 6, 1);
      final pro = Entitlements(pro: true, proExpiresAt: now.add(const Duration(days: 3)));
      expect(pro.adFree(now), isTrue);
      expect(pro.ownsTheme('neon_ocean', now), isTrue);
      expect(Entitlements(pro: true, proExpiresAt: now.subtract(const Duration(days: 1))).adFree(now), isFalse);
      expect(const Entitlements(removeAds: true).adFree(now), isTrue);
      expect(const Entitlements(themes: ['neon_pulse']).ownsTheme('neon_ocean', now), isFalse);
    });

    test('obfuscated account id matches the server', () {
      // Same value as functions/src/billingRules.ts obfuscatedAccountId('user-1').
      expect(obfuscatedAccountId('user-1'), hasLength(64));
      expect(obfuscatedAccountId('user-1'), isNot(obfuscatedAccountId('user-2')));
      expect(obfuscatedAccountId('user-1'), '916b6a144c140a0f785a809ddb90962a33d4446c82abc9fd6de9b83278039d65');
    });
  });

  late FakeCloudRepository cloud;
  late FakeAdsService ads;
  late FakeBillingService billing;
  late MemoryHistoryRepository history;

  setUp(() {
    cloud = FakeCloudRepository();
    ads = FakeAdsService();
    billing = FakeBillingService();
    history = MemoryHistoryRepository();
  });

  Widget app(Widget home, {List<GoRoute> extra = const [], CloudProfile? profile, MemorySettingsRepository? settings}) {
    if (profile != null) cloud.profiles[testUid] = profile;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(path: '/shop', builder: (_, _) => const Scaffold(body: Text('shop page'))),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home page'))),
      GoRoute(path: '/play/:id', builder: (_, s) => Scaffold(body: Text('play ${s.pathParameters['id']}'))),
      ...extra,
    ]);
    return ProviderScope(
      overrides: [
        ...testOverrides(cloud: cloud, history: history, settings: settings),
        adsServiceProvider.overrideWithValue(ads),
        billingServiceProvider.overrideWithValue(billing),
        appConfigProvider.overrideWithValue(const AppConfig(interstitialEveryNGames: 1, interstitialMinIntervalSeconds: 0)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('Shop: purchase is verified on the server before it is finished with Play', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(const ShopScreen(), profile: const CloudProfile(uid: testUid, entitlements: Entitlements(coins: 250, freezes: 1))));
    await tester.pumpAndSettle();
    expect(find.text('250'), findsOneWidget);
    expect(find.text('Subscribe · Rs 450 / month'), findsOneWidget);

    await scrollTo(tester, find.text('Remove ads'));
    await tester.tap(find.widgetWithText(FilledButton, 'Rs 290').first);
    await tester.pumpAndSettle();
    expect(billing.bought.single, startsWith('remove_ads:${obfuscatedAccountId(testUid)}'));
    expect(cloud.verified, ['remove_ads:token-remove_ads']);
    expect(billing.completed, ['remove_ads']);
    expect(find.text('Thank you! Your purchase is ready.'), findsOneWidget);

    // Server unreachable: purchase is NOT finished (Play re-delivers it later).
    cloud.verifyError = const CloudUnavailable();
    billing.emit(const PurchaseUpdate(productId: 'coins_small', status: PurchaseUpdateStatus.purchased, token: 't2'));
    await tester.pumpAndSettle();
    expect(billing.completed, ['remove_ads']);
    expect(find.textContaining('we’ll confirm it when you’re back online'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // let the snackbar go away
    await scrollTo(tester, find.text('Restore purchases'));
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(billing.restores, 1);
  });

  testWidgets('Shop: streak freeze with coins and with a verified rewarded ad', (tester) async {
    usePhoneSize(tester);
    cloud
      ..coins = 250
      ..claimNotFoundTimes = 2; // AdMob's server callback arrives a moment later
    await tester.pumpWidget(app(const ShopScreen(), profile: const CloudProfile(uid: testUid, entitlements: Entitlements(coins: 250))));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('100 coins'));
    await tester.tap(find.text('100 coins'));
    await tester.pumpAndSettle();
    expect(cloud.spent, ['streak_freeze']);
    expect(find.text('🧊 Streak freeze added!'), findsOneWidget);

    await tester.tap(find.text('Watch ad'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(ads.rewarded.single, matches(RegExp(r'^test-user\|streak_freeze:[0-9a-f-]{36}$')));
    expect(cloud.claims, hasLength(3));
    expect(find.text('🧊 Streak freeze added!'), findsOneWidget);
  });

  testWidgets('Results: double XP via rewarded ad; interstitial only when leaving, never for ad-free players', (tester) async {
    usePhoneSize(tester);
    final r = sampleResult(id: 'round-123456', xp: 80);
    history.items.add(r);
    await tester.pumpWidget(app(ResultsScreen(args: ResultsArgs(result: r, justPlayed: true)), profile: const CloudProfile(uid: testUid)));
    await tester.pumpAndSettle();
    expect(ads.interstitials, 0);
    await scrollTo(tester, find.text('Watch an ad: double to +160 XP'));
    await tester.tap(find.text('Watch an ad: double to +160 XP'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(ads.rewarded.single, contains('double_xp:'));
    expect(ads.rewarded.single, endsWith(':round-123456'));
    expect(history.items.single.xp, 160);
    expect(history.items.single.xpBoosted, isTrue);
    expect(find.text('Watch an ad: double to +320 XP'), findsNothing);

    // ProviderScope's policy counts finished games; simulate one.
    final container = ProviderScope.containerOf(tester.element(find.byType(ResultsScreen)));
    container.read(interstitialPolicyProvider).gameFinished();
    await scrollTo(tester, find.text('Play again'));
    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    expect(ads.interstitials, 1);
    expect(find.text('play speed_math'), findsOneWidget);
  });

  testWidgets('Results: Remove Ads owners never see interstitials', (tester) async {
    usePhoneSize(tester);
    final r = sampleResult(id: 'round-abcdef');
    await tester.pumpWidget(app(ResultsScreen(args: ResultsArgs(result: r, justPlayed: true)),
        profile: const CloudProfile(uid: testUid, entitlements: Entitlements(removeAds: true))));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(ResultsScreen))).read(interstitialPolicyProvider).gameFinished();
    await scrollTo(tester, find.text('Back to home'));
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();
    expect(ads.interstitials, 0);
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('Settings: locked neon theme opens the shop; owned theme applies', (tester) async {
    usePhoneSize(tester);
    final settings = MemorySettingsRepository();
    await tester.pumpWidget(app(const SettingsScreen(),
        settings: settings, profile: const CloudProfile(uid: testUid, entitlements: Entitlements(themes: ['neon_ocean']))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neon Pulse'));
    await tester.pumpAndSettle();
    expect(find.text('shop page'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neon Ocean'));
    await tester.pumpAndSettle();
    expect(settings.value.themeMode, AppThemeMode.neonOcean);
    await scrollTo(tester, find.text('Ad privacy choices'));
  });

  testWidgets('Account deletion requires typing DELETE, then wipes server and device data', (tester) async {
    usePhoneSize(tester);
    history.items.add(sampleResult(id: 'mine-1'));
    final auth = FakeAuthRepository(user: testUser);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...testOverrides(cloud: cloud, history: history, auth: auth),
        adsServiceProvider.overrideWithValue(ads),
        billingServiceProvider.overrideWithValue(billing),
      ],
      child: MaterialApp.router(routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const ProfileScreen())])),
    ));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'delete');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(find.text('Type DELETE in capitals'), findsOneWidget);
    expect(cloud.deleted, isFalse);

    await tester.enterText(find.byType(TextFormField), 'DELETE');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(cloud.deleted, isTrue);
    expect(history.items, isEmpty);
    expect(auth.currentUser, isNull);
  });

  testWidgets('Results: coins earned appear once the server balance goes up', (tester) async {
    usePhoneSize(tester);
    final r = sampleResult(id: 'round-coins1');
    await tester.pumpWidget(app(ResultsScreen(args: ResultsArgs(result: r, justPlayed: true, coinsBefore: 100)),
        profile: const CloudProfile(uid: testUid, entitlements: Entitlements(coins: 100))));
    await tester.pumpAndSettle();
    expect(find.textContaining('coins', skipOffstage: false), findsNothing);
    cloud.emitProfile(const CloudProfile(uid: testUid, entitlements: Entitlements(coins: 145)));
    await tester.pumpAndSettle();
    expect(find.text('+45 coins', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Shop explains how to earn coins', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(const ShopScreen(), profile: const CloudProfile(uid: testUid)));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Earn coins by playing'));
    expect(find.textContaining('Up to 300 coins a day'), findsOneWidget);
  });

  testWidgets('Privacy policy screen', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
    expect(find.text('Data we collect'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Keeping and deleting your data'), 300);
    expect(find.textContaining('Profile → Delete account'), findsOneWidget);
  });
}
