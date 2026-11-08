import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../domain/entities/shop.dart';

enum PurchaseUpdateStatus { pending, purchased, error, canceled }

class PurchaseUpdate {
  const PurchaseUpdate({required this.productId, required this.status, this.token, this.error, this.raw});
  final String productId;
  final PurchaseUpdateStatus status;

  /// Google Play purchase token (sent to the server for verification).
  final String? token;
  final String? error;
  final Object? raw;
}

abstract interface class BillingService {
  Future<bool> isAvailable();
  Future<List<StoreProduct>> products(Set<String> ids);

  /// [accountId] is the obfuscated account id bound to the purchase.
  Future<void> buy(StoreProduct product, {required String accountId});
  Future<void> restore({required String accountId});

  /// Purchases to verify (including unfinished ones re-delivered at startup).
  Stream<PurchaseUpdate> get updates;

  /// Finishes a verified purchase with the store.
  Future<void> complete(PurchaseUpdate update);
}

class UnavailableBillingService implements BillingService {
  const UnavailableBillingService();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => const [];
  @override
  Future<void> buy(StoreProduct product, {required String accountId}) async {}
  @override
  Future<void> restore({required String accountId}) async {}
  @override
  Stream<PurchaseUpdate> get updates => const Stream.empty();
  @override
  Future<void> complete(PurchaseUpdate update) async {}
}

class PlayBillingService implements BillingService {
  PlayBillingService(this._iap);
  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    final res = await _iap.queryProductDetails(ids);
    final seen = <String>{};
    return [
      // Subscriptions return one entry per offer; keep the first (base plan).
      for (final p in res.productDetails)
        if (seen.add(p.id)) StoreProduct(id: p.id, title: p.title, price: p.price, raw: p),
    ];
  }

  @override
  Future<void> buy(StoreProduct product, {required String accountId}) async {
    final param = PurchaseParam(productDetails: product.raw! as ProductDetails, applicationUserName: accountId);
    if (ProductIds.consumables.contains(product.id)) {
      // The server consumes after verifying, so the client must not.
      await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restore({required String accountId}) => _iap.restorePurchases(applicationUserName: accountId);

  @override
  Stream<PurchaseUpdate> get updates => _iap.purchaseStream.expand((list) => list.map((p) => PurchaseUpdate(
        productId: p.productID,
        status: switch (p.status) {
          PurchaseStatus.pending => PurchaseUpdateStatus.pending,
          PurchaseStatus.purchased || PurchaseStatus.restored => PurchaseUpdateStatus.purchased,
          PurchaseStatus.canceled => PurchaseUpdateStatus.canceled,
          PurchaseStatus.error => PurchaseUpdateStatus.error,
        },
        token: p.verificationData.serverVerificationData,
        error: p.error?.message,
        raw: p,
      )));

  @override
  Future<void> complete(PurchaseUpdate update) async {
    final p = update.raw;
    if (p is PurchaseDetails && p.pendingCompletePurchase) await _iap.completePurchase(p);
  }
}
