/// Google Play product ids (must match Play Console and functions/src/billingRules.ts).
class ProductIds {
  const ProductIds._();
  static const removeAds = 'remove_ads';
  static const premiumThemes = 'premium_themes';
  static const coinsSmall = 'coins_small';
  static const coinsMedium = 'coins_medium';
  static const coinsLarge = 'coins_large';
  static const pro = 'neurorush_pro';

  static const consumables = {coinsSmall, coinsMedium, coinsLarge};
  static const all = {removeAds, premiumThemes, coinsSmall, coinsMedium, coinsLarge, pro};
}

/// A product as listed by the store (localized title and price).
class StoreProduct {
  const StoreProduct({required this.id, required this.title, required this.price, this.raw});
  final String id;
  final String title;
  final String price;

  /// Platform object needed to start the purchase.
  final Object? raw;
}

/// What the player owns, as granted by the server.
class Entitlements {
  const Entitlements({
    this.removeAds = false,
    this.pro = false,
    this.proExpiresAt,
    this.themes = const [],
    this.coins = 0,
    this.freezes = 0,
  });

  final bool removeAds;
  final bool pro;
  final DateTime? proExpiresAt;
  final List<String> themes;
  final int coins;
  final int freezes;

  static const none = Entitlements();

  bool proActive(DateTime now) => pro && proExpiresAt != null && proExpiresAt!.isAfter(now);
  bool adFree(DateTime now) => removeAds || proActive(now);
  bool ownsTheme(String id, DateTime now) => proActive(now) || themes.contains(id);
}

enum RewardType {
  streakFreeze('streak_freeze'),
  doubleXp('double_xp'),
  extraLife('extra_life');

  const RewardType(this.wire);
  final String wire;
}

/// Outcome of a rewarded ad claim.
class RewardClaim {
  const RewardClaim({required this.applied, this.reason});
  final bool applied;
  final String? reason;
}
