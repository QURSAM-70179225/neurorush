import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/ads/ads_service.dart';
import 'core/billing/billing_service.dart';
import 'core/config/remote_config_service.dart';
import 'core/feedback/feedback_service.dart';
import 'core/push/push_service.dart';
import 'data/local/hive_store.dart';
import 'data/repositories/firebase_auth_repository.dart';
import 'data/repositories/firebase_battle_repository.dart';
import 'data/repositories/firebase_cloud_repository.dart';
import 'data/repositories/firebase_push_repository.dart';
import 'data/repositories/local_auth_repository.dart';
import 'data/repositories/offline_battle_repository.dart';
import 'data/repositories/offline_cloud_repository.dart';
import 'domain/entities/achievement.dart';
import 'domain/entities/app_config.dart';
import 'domain/logic/server_clock.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/battle_repository.dart';
import 'domain/repositories/cloud_repository.dart';
import 'domain/repositories/push_repository.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/battle_providers.dart';
import 'presentation/providers/cloud_providers.dart';
import 'presentation/providers/shop_providers.dart';

/// `flutter run --dart-define=USE_EMULATORS=true` talks to local Firebase
/// emulators (see SETUP.md). 10.0.2.2 is the host machine from an Android emulator.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final store = await HiveStore.open();
  final clock = ServerClock();
  final b = await _createBackends(store, clock);
  final catalogue = Achievement.parseCatalogue(await rootBundle.loadString('shared/achievements.json'));
  final feedback = FeedbackService();
  unawaited(feedback.preload());
  // Consent (UMP) + ad SDK start in the background; ads are never needed at launch.
  unawaited(b.ads.init());

  runApp(
    ProviderScope(
      overrides: [
        hiveStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(b.auth),
        cloudRepositoryProvider.overrideWithValue(b.cloud),
        battleRepositoryProvider.overrideWithValue(b.battles),
        pushServiceProvider.overrideWithValue(b.push),
        pushRepositoryProvider.overrideWithValue(b.pushRepo),
        serverClockProvider.overrideWithValue(clock),
        appConfigProvider.overrideWithValue(b.config),
        adsServiceProvider.overrideWithValue(b.ads),
        billingServiceProvider.overrideWithValue(b.billing),
        achievementCatalogProvider.overrideWithValue(catalogue),
        feedbackServiceProvider.overrideWithValue(feedback),
        connectivityRestoredProvider.overrideWithValue(_connectivityRestored()),
      ],
      child: const NeuroRushApp(),
    ),
  );
}

/// Uses Firebase when the project is configured (google-services.json on
/// Android). If Firebase cannot start, the app still works fully offline with
/// a local guest profile.
typedef _Backends = ({
  AuthRepository auth,
  CloudRepository cloud,
  BattleRepository battles,
  PushService push,
  PushRepository? pushRepo,
  AppConfig config,
  AdsService ads,
  BillingService billing,
});

Future<_Backends> _createBackends(HiveStore store, ServerClock clock) async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    final functions = FirebaseFunctions.instanceFor(region: functionsRegion);
    if (_useEmulators) {
      await auth.useAuthEmulator(_emulatorHost, 9099);
      db.useFirestoreEmulator(_emulatorHost, 8080);
      functions.useFunctionsEmulator(_emulatorHost, 5001);
    }
    // App Check: Play Integrity attests that calls come from the real app.
    await FirebaseAppCheck.instance
        .activate(providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider())
        .catchError((Object e) => debugPrint('App Check unavailable: $e'));
    final config = await loadAppConfig(FirebaseRemoteConfig.instance);
    // Offline cache so profiles and boards open instantly and work offline.
    db.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 50 * 1024 * 1024);
    // Wait for the persisted session to be restored before routing.
    await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
    return (
      auth: FirebaseAuthRepository(auth),
      cloud: FirebaseCloudRepository(db, functions),
      battles: FirebaseBattleRepository(db, functions, clock),
      push: FirebasePushService(FirebaseMessaging.instance),
      pushRepo: FirebasePushRepository(db),
      config: config,
      ads: kIsWeb ? const NoopAdsService() : GoogleAdsService(),
      billing: kIsWeb ? const UnavailableBillingService() : PlayBillingService(InAppPurchase.instance),
    );
  } catch (e) {
    debugPrint('Firebase unavailable, running in offline mode: $e');
    return (
      auth: LocalAuthRepository(store.auth),
      cloud: const OfflineCloudRepository(),
      battles: const OfflineBattleRepository(),
      push: const NoopPushService(),
      pushRepo: null,
      config: const AppConfig(),
      // Ads still work offline-first; purchases need the server to verify.
      ads: kIsWeb ? const NoopAdsService() : GoogleAdsService(),
      billing: const UnavailableBillingService(),
    );
  }
}

/// Emits each time the device goes from offline to online.
Stream<void> _connectivityRestored() {
  var wasOffline = false;
  return Connectivity().onConnectivityChanged.handleError((Object _) {}).where((results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final restored = online && wasOffline;
    wasOffline = !online;
    return restored;
  }).map((_) {});
}
