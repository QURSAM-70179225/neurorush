import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Product analytics. Only gameplay events and counts are logged — never
/// names, emails or free text.
abstract interface class Analytics {
  Future<void> gameEnd({required String gameId, required int score, required int stars, required int accuracyPercent, required int seconds});
  Future<void> levelUp(int level);
  Future<void> brainTestComplete(int brainScore);
  Future<void> workoutComplete();
  Future<void> battleEnd({required String mode, required String outcome});
  Future<void> endlessRunEnd(int run);
  Future<void> rewardedReward(String reward, {required bool applied});
  Future<void> purchaseVerified(String productId);
  Future<void> setUser(String? uid);

  /// Observer that logs screen views from the router.
  NavigatorObserver? get observer;
}

class NoopAnalytics implements Analytics {
  const NoopAnalytics();
  @override
  Future<void> gameEnd({required String gameId, required int score, required int stars, required int accuracyPercent, required int seconds}) async {}
  @override
  Future<void> levelUp(int level) async {}
  @override
  Future<void> brainTestComplete(int brainScore) async {}
  @override
  Future<void> workoutComplete() async {}
  @override
  Future<void> battleEnd({required String mode, required String outcome}) async {}
  @override
  Future<void> endlessRunEnd(int run) async {}
  @override
  Future<void> rewardedReward(String reward, {required bool applied}) async {}
  @override
  Future<void> purchaseVerified(String productId) async {}
  @override
  Future<void> setUser(String? uid) async {}
  @override
  NavigatorObserver? get observer => null;
}

class FirebaseAnalyticsImpl implements Analytics {
  FirebaseAnalyticsImpl(this._fa);
  final FirebaseAnalytics _fa;

  Future<void> _log(String name, [Map<String, Object>? params]) =>
      _fa.logEvent(name: name, parameters: params).catchError((Object e) => debugPrint('analytics: $e'));

  @override
  Future<void> gameEnd({required String gameId, required int score, required int stars, required int accuracyPercent, required int seconds}) =>
      _log('game_end', {'game_id': gameId, 'score': score, 'stars': stars, 'accuracy': accuracyPercent, 'seconds': seconds});
  @override
  Future<void> levelUp(int level) => _fa.logLevelUp(level: level).catchError((Object _) {});
  @override
  Future<void> brainTestComplete(int brainScore) => _log('brain_test_complete', {'brain_score': brainScore});
  @override
  Future<void> workoutComplete() => _log('workout_complete');
  @override
  Future<void> battleEnd({required String mode, required String outcome}) => _log('battle_end', {'mode': mode, 'outcome': outcome});
  @override
  Future<void> endlessRunEnd(int run) => _log('endless_run_end', {'run': run});
  @override
  Future<void> rewardedReward(String reward, {required bool applied}) =>
      _log('rewarded_reward', {'reward': reward, 'applied': applied ? 1 : 0});
  @override
  Future<void> purchaseVerified(String productId) => _log('purchase_verified', {'product_id': productId});
  @override
  Future<void> setUser(String? uid) => _fa.setUserId(id: uid).catchError((Object _) {});
  @override
  NavigatorObserver get observer => FirebaseAnalyticsObserver(analytics: _fa);
}

/// Sends uncaught Flutter and platform errors to Crashlytics (release only).
void installCrashReporting(FirebaseCrashlytics crashlytics) {
  unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode));
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
