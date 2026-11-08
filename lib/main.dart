import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/feedback/feedback_service.dart';
import 'data/local/hive_store.dart';
import 'data/repositories/firebase_auth_repository.dart';
import 'data/repositories/local_auth_repository.dart';
import 'domain/repositories/auth_repository.dart';
import 'presentation/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final store = await HiveStore.open();
  final auth = await _createAuthRepository(store);
  final feedback = FeedbackService();
  unawaited(feedback.preload());

  runApp(
    ProviderScope(
      overrides: [
        hiveStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(auth),
        feedbackServiceProvider.overrideWithValue(feedback),
      ],
      child: const NeuroRushApp(),
    ),
  );
}

/// Uses Firebase when the project is configured (google-services.json on
/// Android). If Firebase cannot start, the app still works fully offline with
/// a local guest profile.
Future<AuthRepository> _createAuthRepository(HiveStore store) async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    final auth = FirebaseAuth.instance;
    // Wait for the persisted session to be restored before routing.
    await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
    return FirebaseAuthRepository(auth);
  } catch (e) {
    debugPrint('Firebase unavailable, running in offline mode: $e');
    return LocalAuthRepository(store.auth);
  }
}
