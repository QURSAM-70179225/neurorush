import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/app_config.dart';

/// Loads [AppConfig] from Firebase Remote Config (cached; refreshed hourly).
Future<AppConfig> loadAppConfig(FirebaseRemoteConfig rc) async {
  try {
    await rc.setDefaults(AppConfig.defaults);
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 8),
      minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));
    await rc.fetchAndActivate().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Remote Config fetch failed, using cached/default values: $e');
  }
  return AppConfig(
    interstitialEveryNGames: rc.getInt('interstitial_every_n_games'),
    interstitialMinIntervalSeconds: rc.getInt('interstitial_min_interval_seconds'),
    adsEnabled: rc.getBool('ads_enabled'),
    themePriceCoins: rc.getInt('theme_price_coins'),
    freezePriceCoins: rc.getInt('freeze_price_coins'),
    freeEndlessPerDay: rc.getInt('free_endless_per_day'),
  );
}
