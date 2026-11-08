import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/app.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
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

    expect(find.text('Quick play'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);

    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(find.text('Memory Grid'), findsOneWidget);
    expect(find.text('Color Clash'), findsOneWidget);
    expect(find.text('Speed Math'), findsOneWidget);

    await tester.tap(find.text('Battle'));
    await tester.pumpAndSettle();
    expect(find.text('Random round'), findsOneWidget);

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(find.text('Not played yet'), findsNWidgets(3));

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Save your progress with a free account.'), findsOneWidget);

    // Sign out returns to the auth screen.
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
        settings: MemorySettingsRepository(const AppSettings(onboardingDone: true)),
        auth: FakeAuthRepository(
            user: const UserProfile(uid: 'u', provider: AuthProviderKind.google, displayName: 'Bilal')),
      ),
      child: const NeuroRushApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.text('Quick play'), findsOneWidget);
  });

  testWidgets('email sign-in validates input and shows errors', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(settings: MemorySettingsRepository(const AppSettings(onboardingDone: true))),
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
    expect(find.text('Quick play'), findsOneWidget);
    expect(find.text('sara'), findsOneWidget);
  });

  testWidgets('settings: dark mode and large text are saved', (tester) async {
    usePhoneSize(tester);
    final settings = MemorySettingsRepository(const AppSettings(onboardingDone: true));
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
    await tester.tap(find.text('Settings & accessibility'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.value.themeMode, AppThemeMode.dark);
    expect(Theme.of(tester.element(find.text('Dark'))).brightness, Brightness.dark);

    await tester.tap(find.text('Large text'));
    await tester.pumpAndSettle();
    expect(settings.value.largeText, isTrue);
    expect(MediaQuery.of(tester.element(find.text('Large text'))).textScaler.scale(10), 12.5);
  });
}
