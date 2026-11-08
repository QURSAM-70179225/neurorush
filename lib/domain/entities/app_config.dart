/// Values from Firebase Remote Config, so ads and prices can change without
/// an app update. Defaults apply offline and before the first fetch.
class AppConfig {
  const AppConfig({
    this.interstitialEveryNGames = 3,
    this.interstitialMinIntervalSeconds = 120,
    this.adsEnabled = true,
    this.themePriceCoins = 300,
    this.freezePriceCoins = 100,
    this.freeEndlessPerDay = 10,
  });

  final int interstitialEveryNGames;
  final int interstitialMinIntervalSeconds;
  final bool adsEnabled;

  /// Display only — the server charges the price from its own template.
  final int themePriceCoins;
  final int freezePriceCoins;
  final int freeEndlessPerDay;

  static const defaults = <String, Object>{
    'interstitial_every_n_games': 3,
    'interstitial_min_interval_seconds': 120,
    'ads_enabled': true,
    'theme_price_coins': 300,
    'freeze_price_coins': 100,
    'free_endless_per_day': 10,
  };
}
