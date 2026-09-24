import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';
import '../config.dart';

class StoreProduct {
  StoreProduct(this.id, this.title, this.price, this.raw);
  final String id;
  final String title;
  final String price; // already formatted in the buyer's currency by Google Play
  final Object? raw;
}

enum PurchaseOutcome { success, pending, cancelled, failed }

/// Google Play subscriptions: the payment channel outside Tanzania.
abstract class StoreBilling {
  Future<bool> available();
  Future<List<StoreProduct>> products();
  Future<PurchaseOutcome> buy(StoreProduct product);

  /// Sends past purchases to the server again, e.g. one whose verification failed on a bad
  /// connection. Called once the learner is signed in.
  Future<void> restore();

  /// Called when a purchase is verified outside [buy] (for example by [restore]).
  VoidCallback? onVerified;
}

class NoBilling implements StoreBilling {
  @override
  VoidCallback? onVerified;
  @override
  Future<bool> available() async => false;
  @override
  Future<List<StoreProduct>> products() async => const [];
  @override
  Future<PurchaseOutcome> buy(StoreProduct product) async => PurchaseOutcome.failed;
  @override
  Future<void> restore() async {}
}

StoreBilling createBilling(MasomoApi api) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return PlayBilling(api);
  return NoBilling(); // iOS App Store billing is a later phase
}

class PlayBilling implements StoreBilling {
  PlayBilling(this.api) {
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (_) => _complete(PurchaseOutcome.failed));
  }

  final MasomoApi api;
  final _iap = InAppPurchase.instance;
  @override
  VoidCallback? onVerified;
  late final StreamSubscription<List<PurchaseDetails>> _sub;
  Completer<PurchaseOutcome>? _pending;

  @override
  Future<bool> available() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> products() async {
    final res = await _iap.queryProductDetails(AppConfig.playProductIds);
    final seen = <String>{};
    return [
      for (final p in res.productDetails)
        if (seen.add(p.id)) StoreProduct(p.id, p.title, p.price, p),
    ];
  }

  @override
  Future<PurchaseOutcome> buy(StoreProduct product) async {
    _pending = Completer<PurchaseOutcome>();
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product.raw! as ProductDetails),
    );
    if (!started) return PurchaseOutcome.failed;
    return _pending!.future;
  }

  @override
  Future<void> restore() async {
    if (await _iap.isAvailable()) await _iap.restorePurchases();
  }

  void _complete(PurchaseOutcome outcome) {
    final c = _pending;
    _pending = null;
    if (c != null && !c.isCompleted) c.complete(outcome);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      var finish = true;
      switch (p.status) {
        case PurchaseStatus.pending:
          finish = false;
        case PurchaseStatus.canceled:
          _complete(PurchaseOutcome.cancelled);
        case PurchaseStatus.error:
          _complete(PurchaseOutcome.failed);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            // The server checks the token with Google, turns Pro on and acknowledges it.
            await api.verifyPlayPurchase(p.verificationData.serverVerificationData);
            _complete(PurchaseOutcome.success);
            onVerified?.call();
          } on ApiException {
            // Leave it unfinished: restore() retries later, and if it is never verified
            // Google refunds an unacknowledged purchase after 3 days instead of keeping the money.
            finish = false;
            _complete(PurchaseOutcome.failed);
          }
      }
      if (finish && p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void dispose() => _sub.cancel();
}
