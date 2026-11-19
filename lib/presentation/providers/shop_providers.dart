import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/ads/ads_service.dart';
import '../../core/billing/billing_service.dart';
import '../../domain/entities/app_config.dart';
import '../../domain/entities/shop.dart';
import '../../domain/logic/interstitial_policy.dart';
import '../../domain/repositories/cloud_repository.dart';
import 'app_providers.dart';
import 'cloud_providers.dart';
import 'telemetry_providers.dart';

/// Overridden in main() after Remote Config is fetched.
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final adsServiceProvider = Provider<AdsService>((ref) => const NoopAdsService());
final billingServiceProvider = Provider<BillingService>((ref) => const UnavailableBillingService());

/// What the signed-in player owns (server-granted; none when offline).
final entitlementsProvider = Provider<Entitlements>(
  (ref) => ref.watch(cloudProfileProvider).value?.entitlements ?? Entitlements.none,
);

final interstitialPolicyProvider = Provider<InterstitialPolicy>((ref) {
  final c = ref.watch(appConfigProvider);
  return InterstitialPolicy(everyNGames: c.interstitialEveryNGames, minInterval: Duration(seconds: c.interstitialMinIntervalSeconds));
});

/// The obfuscated account id attached to purchases (matches the server).
String obfuscatedAccountId(String uid) => sha256.convert(utf8.encode('neurorush:$uid')).toString().substring(0, 64);

/// Shows an interstitial between rounds when the frequency cap allows it.
Future<void> maybeShowInterstitial(WidgetRef ref) async {
  final config = ref.read(appConfigProvider);
  if (!config.adsEnabled) return;
  final policy = ref.read(interstitialPolicyProvider);
  final now = DateTime.now();
  if (!policy.shouldShow(now, adFree: ref.read(entitlementsProvider).adFree(now))) return;
  if (await ref.read(adsServiceProvider).showInterstitial()) policy.shown(now);
}

/// Rewarded-ad nonces whose AdMob verification had not arrived yet; claimed
/// on the next sync.
abstract interface class PendingRewardStore {
  List<String> read();
  Future<void> write(List<String> nonces);
}

class HivePendingRewardStore implements PendingRewardStore {
  HivePendingRewardStore(this._box);
  final Box<dynamic> _box;
  static const _key = 'pending_reward_nonces';
  @override
  List<String> read() => [...(_box.get(_key) as List? ?? const [])].cast<String>();
  @override
  Future<void> write(List<String> nonces) => _box.put(_key, nonces);
}

final pendingRewardStoreProvider =
    Provider<PendingRewardStore>((ref) => HivePendingRewardStore(ref.watch(hiveStoreProvider).settings));

/// Shows a rewarded ad and claims the server-verified reward. Returns null
/// when the ad was not watched to the end.
Future<RewardClaim?> watchRewardedAd(WidgetRef ref, RewardType type, {String? sessionId}) async {
  final uid = ref.read(currentUidProvider);
  final cloud = ref.read(cloudRepositoryProvider);
  if (uid == null || !cloud.isAvailable) throw const CloudUnavailable('Rewards need an online account.');
  final nonce = const Uuid().v4();
  final customData = [type.wire, nonce, ?sessionId].join(':');
  final earned = await ref.read(adsServiceProvider).showRewarded(userId: uid, customData: customData);
  if (!earned) return null;
  // AdMob's server callback usually lands within a few seconds.
  for (final delay in const [500, 1000, 1500, 2000, 3000, 4000]) {
    await Future<void>.delayed(Duration(milliseconds: delay));
    try {
      final claim = await cloud.claimAdReward(nonce);
      unawaited(ref.read(analyticsProvider).rewardedReward(type.wire, applied: claim.applied));
      return claim;
    } on CloudFailure catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }
  final store = ref.read(pendingRewardStoreProvider);
  await store.write([...store.read(), nonce]);
  return const RewardClaim(applied: false, reason: 'pending');
}

/// Retries rewards that were verified late (called during sync).
Future<void> claimPendingRewards(Ref ref) async {
  final store = ref.read(pendingRewardStoreProvider);
  final pending = store.read();
  if (pending.isEmpty) return;
  final cloud = ref.read(cloudRepositoryProvider);
  final left = <String>[];
  for (final nonce in pending) {
    try {
      await cloud.claimAdReward(nonce);
    } on CloudFailure catch (e) {
      if (e.code == 'not-found') left.add(nonce);
    } on CloudUnavailable {
      left.add(nonce);
    }
  }
  await store.write(left);
}

// --- purchases ------------------------------------------------------------------

class ShopState {
  const ShopState({this.products = const {}, this.available = false, this.busy = false, this.message});
  final Map<String, StoreProduct> products;
  final bool available;
  final bool busy;

  /// Last purchase outcome to show the player (null = nothing new).
  final String? message;

  ShopState copyWith({Map<String, StoreProduct>? products, bool? available, bool? busy, String? message, bool clearMessage = false}) =>
      ShopState(
        products: products ?? this.products,
        available: available ?? this.available,
        busy: busy ?? this.busy,
        message: clearMessage ? null : message ?? this.message,
      );
}

/// Loads store products and verifies every purchase on the server before
/// finishing it with Google Play. Unverified purchases are left unfinished so
/// Play re-delivers them on the next start.
class ShopNotifier extends Notifier<ShopState> {
  StreamSubscription<PurchaseUpdate>? _sub;

  @override
  ShopState build() {
    final billing = ref.watch(billingServiceProvider);
    _sub?.cancel();
    _sub = billing.updates.listen(_onUpdate);
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_load);
    return const ShopState();
  }

  Future<void> _load() async {
    final billing = ref.read(billingServiceProvider);
    if (!await billing.isAvailable()) return;
    final list = await billing.products(ProductIds.all);
    if (ref.mounted) state = state.copyWith(available: true, products: {for (final p in list) p.id: p});
  }

  Future<void> buy(String productId) async {
    final uid = ref.read(currentUidProvider);
    final product = state.products[productId];
    if (uid == null || product == null) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await ref.read(billingServiceProvider).buy(product, accountId: obfuscatedAccountId(uid));
    } catch (e) {
      state = state.copyWith(busy: false, message: 'Purchase could not start: $e');
    }
  }

  Future<void> restore() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    state = state.copyWith(busy: true, message: 'Restoring purchases…');
    await ref.read(billingServiceProvider).restore(accountId: obfuscatedAccountId(uid));
    state = state.copyWith(busy: false);
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  Future<void> _onUpdate(PurchaseUpdate u) async {
    switch (u.status) {
      case PurchaseUpdateStatus.pending:
        state = state.copyWith(busy: true, message: 'Payment pending…');
      case PurchaseUpdateStatus.canceled:
        state = state.copyWith(busy: false, clearMessage: true);
      case PurchaseUpdateStatus.error:
        state = state.copyWith(busy: false, message: u.error ?? 'Purchase failed.');
      case PurchaseUpdateStatus.purchased:
        try {
          await ref.read(cloudRepositoryProvider).verifyPurchase(u.productId, u.token ?? '');
          await ref.read(billingServiceProvider).complete(u);
          unawaited(ref.read(analyticsProvider).purchaseVerified(u.productId));
          state = state.copyWith(busy: false, message: 'Thank you! Your purchase is ready.');
        } on CloudUnavailable {
          state = state.copyWith(busy: false, message: 'Purchase received — we’ll confirm it when you’re back online.');
        } on CloudFailure catch (e) {
          state = state.copyWith(busy: false, message: e.message);
        }
    }
  }
}

final shopProvider = NotifierProvider<ShopNotifier, ShopState>(ShopNotifier.new);
