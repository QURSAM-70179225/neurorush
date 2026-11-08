import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit ids. Release builds pass real ids with --dart-define; the defaults
/// are Google's official test units (safe to click, never pay out).
class AdUnits {
  const AdUnits._();
  static const interstitial =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const rewarded =
      String.fromEnvironment('ADMOB_REWARDED_ID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
}

abstract interface class AdsService {
  /// Asks for consent where required (UMP), then initialises ads.
  Future<void> init();

  /// Shows a loaded interstitial; returns false if none was ready.
  Future<bool> showInterstitial();

  /// Shows a rewarded ad. The reward is verified server-side through AdMob
  /// SSV using [userId] and [customData]. Returns true if the user earned it.
  Future<bool> showRewarded({required String userId, required String customData});

  /// Whether this user must be offered a way to change ad consent (e.g. EEA).
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
}

class NoopAdsService implements AdsService {
  const NoopAdsService();
  @override
  Future<void> init() async {}
  @override
  Future<bool> showInterstitial() async => false;
  @override
  Future<bool> showRewarded({required String userId, required String customData}) async => false;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

class GoogleAdsService implements AdsService {
  InterstitialAd? _interstitial;
  bool _ready = false;
  Completer<void>? _initializing;

  @override
  Future<void> init() {
    final existing = _initializing;
    if (existing != null) return existing.future;
    final c = _initializing = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => _start(c)),
      (error) {
        debugPrint('Consent info failed: ${error.message}');
        _start(c);
      },
    );
    return c.future;
  }

  Future<void> _start(Completer<void> c) async {
    try {
      if (await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
        _ready = true;
        _loadInterstitial();
      }
    } catch (e) {
      debugPrint('Ads init failed: $e');
    }
    if (!c.isCompleted) c.complete();
  }

  void _loadInterstitial() {
    if (!_ready) return;
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) => debugPrint('Interstitial failed: ${e.message}'),
      ),
    );
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return false;
    }
    _interstitial = null;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show();
    return done.future;
  }

  @override
  Future<bool> showRewarded({required String userId, required String customData}) async {
    await init();
    if (!_ready) return false;
    final loaded = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) {
          debugPrint('Rewarded failed: ${e.message}');
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (ad == null) return false;
    await ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId, customData: customData));
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    return earned;
  }

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((_) {});
}
