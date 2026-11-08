import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/app.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/entities/user_profile.dart';

import '../helpers.dart';

void main() {
  testWidgets('first launch: onboarding → guest sign-in → home → tabs', (tester) async {
    usePhoneSize(tester);
    final settings = MemorySettingsRepository();
    final auth = FakeAuthRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(auth: auth, settings: settings),
      child: const NeuroRushApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Train your brain'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's go!"));
    await tester.pumpAndSettle();
    expect(settings.value.onboardingDone, isTrue);

    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Play as guest'));
    await tester.pumpAndSettle();

    // The Brain Test is offered once after the first sign-in.
    expect(find.text('Start Brain Test'), findsOneWidget);
    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();
    expect(settings.value.brainTestOffered, isTrue);

    expect(find.text('Take the Brain Test'), findsOneWidget);
    expect(find.text('Rookie Brain I'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    await scrollTo(tester, find.text('Daily Brain Workout'));
    await scrollTo(tester, find.text('Quick play'));

    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    for (final t in GameType.values) {
      await tester.scrollUntilVisible(find.text(t.title), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text(t.title), findsOneWidget);
    }

    await tester.tap(find.text('Battle'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Live battles need an online account'), findsOneWidget);

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    // Offline build: online boards explain themselves; Records still work.
    expect(find.textContaining('Leaderboards need an online account'), findsOneWidget);
    await tester.ensureVisible(find.text('Records'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    expect(find.text('Not played yet'), findsWidgets);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Save your progress with a free account.'), findsOneWidget);

    // Sign out returns to the auth screen.
    await tester.scrollUntilVisible(find.text('Sign out'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Play as guest'), findsOneWidget);
  });

  testWidgets('returning user skips onboarding and auth', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(
        settings: MemorySettingsRepository(const AppSettings(onboardingDone: true, brainTestOffered: true)),
        auth: FakeAuthRepository(
            user: const UserProfile(uid: 'u', provider: AuthProviderKind.google, displayName: 'Bilal')),
      ),
      child: const NeuroRushApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Bilal'), findsOneWidget);
    await scrollTo(tester, find.text('Quick play'));
  });

  testWidgets('email sign-in validates input and shows errors', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(
        auth: FakeAuthRepository(),
        settings: MemorySettingsRepository(const AppSettings(onboardingDone: true, brainTestOffered: true)),
      ),
      child: const NeuroRushApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use email'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'sara@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrongpw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('sara'), findsOneWidget);
    expect(find.text('Daily Brain Workout'), findsOneWidget);
  });

  testWidgets('settings: dark mode and large text are saved', (tester) async {
    usePhoneSize(tester);
    final settings = MemorySettingsRepository(const AppSettings(onboardingDone: true, brainTestOffered: true));
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(
        settings: settings,
        auth: FakeAuthRepository(user: const UserProfile(uid: 'u', provider: AuthProviderKind.guest)),
      ),
      child: const NeuroRushApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.value.themeMode, AppThemeMode.dark);
    expect(Theme.of(tester.element(find.text('Dark'))).brightness, Brightness.dark);

    await scrollTo(tester, find.text('Large text'));
    await tester.tap(find.text('Large text'));
    await tester.pumpAndSettle();
    expect(settings.value.largeText, isTrue);
    expect(MediaQuery.of(tester.element(find.byType(Scaffold).last)).textScaler.scale(10), 12.5);
  });
}
