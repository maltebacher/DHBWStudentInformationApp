import 'dart:async';
import 'dart:io';

import 'package:dhbwstudentapp/common/data/preferences/preferences_provider.dart';
import 'package:dhbwstudentapp/common/logging/analytics.dart';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart';

typedef PurchaseCompletedCallback = Function(
  String productId,
  bool isPurchased,
);

class InAppPurchaseHelper {
  static const String WidgetProductId = "app_widget";
  static const String DonateToDeveloperProductId = "donate_to_developer";

  final PreferencesProvider _preferencesProvider;

  StreamSubscription _purchaseUpdatedSubscription;
  StreamSubscription _purchaseErrorSubscription;

  PurchaseCompletedCallback _purchaseCallback;

  InAppPurchaseHelper(this._preferencesProvider);

  Future<void> initialize() async {
    print("Initializing in app purchases...");

    await FlutterInappPurchase.instance.initConnection;

    _purchaseUpdatedSubscription =
        FlutterInappPurchase.purchaseUpdated.listen(_completePurchase);

    _purchaseErrorSubscription =
        FlutterInappPurchase.purchaseError.listen(_onPurchaseError);

    print("In app purchases initialized");

    _completePendingPurchases();
  }

  Future<void> buyById(String id) async {
    print("Attempting to buy $id");

    await analytics.logEvent(name: "purchase_$id");

    await _preferencesProvider.setHasPurchasedSomething(true);

    await FlutterInappPurchase.instance.getProducts([id]);
    await FlutterInappPurchase.instance.requestPurchase(id);
  }

  Future<bool> didBuyId(String id) async {
    var allPurchases =
        await FlutterInappPurchase.instance.getAvailablePurchases();

    var productIdPurchases =
        allPurchases.where((element) => element.productId == id);

    if (productIdPurchases.isEmpty) {
      return false;
    }

    return productIdPurchases.any((element) => _isPurchased(element));
  }

  void setPurchaseCompleteCallback(PurchaseCompletedCallback callback) {
    _purchaseCallback = callback;
  }

  Future<void> _completePurchase(PurchasedItem item) async {
    print("Completing purchase: ${item.orderId} (${item.productId})");

    var isPurchased = _isPurchased(item);

    _purchaseCallback(item.productId, isPurchased);

    if (!isPurchased) return;

    await FlutterInappPurchase.instance.finishTransaction(
      item,
      isConsumable: _isConsumable(item.productId),
    );

    await analytics.logEvent(name: "purchaseCompleted_${item.productId}");
  }

  Future<void> _completePendingPurchases() async {
    print("Completing pending purchases");

    if (!await _preferencesProvider.getHasPurchasedSomething()) return;

    List<PurchasedItem> purchasedItems = [];

    if (Platform.isAndroid) {
      purchasedItems =
          await FlutterInappPurchase.instance.getAvailablePurchases();
    } else if (Platform.isIOS) {
      purchasedItems =
          await FlutterInappPurchase.instance.getPendingTransactionsIOS();
    }

    print("Found ${purchasedItems.length} pending purchases");

    purchasedItems.forEach(_completePurchase);
  }

  void _onPurchaseError(PurchaseResult event) {
    print("Failed to purchase:");
    print(event.message);
    print(event.debugMessage);
  }

  bool _isConsumable(String id) {
    return id == DonateToDeveloperProductId;
  }

  bool _isPurchased(PurchasedItem item) {
    if (Platform.isAndroid) {
      return item.purchaseStateAndroid == PurchaseState.purchased;
    } else if (Platform.isIOS) {
      return item.transactionStateIOS == TransactionState.purchased;
    }

    return false;
  }

  void dispose() {
    _purchaseUpdatedSubscription?.cancel();
    _purchaseUpdatedSubscription = null;

    _purchaseErrorSubscription?.cancel();
    _purchaseErrorSubscription = null;
  }
}
