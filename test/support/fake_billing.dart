import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const String _customPetProductId = 'luffy.custom_pet.create.v1';

/// Replaces the store boundary while exercising the real BillingService.
/// It never opens StoreKit, contacts Apple, or starts a paid purchase.
class FakeBillingStore extends Fake implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String?>[];
  final purchaseRequests = <PurchaseParam>[];
  final productQueries = <Set<String>>[];
  int purchaseStarts = 0;
  int restoreCalls = 0;
  int streamReads = 0;
  bool available = true;
  bool startResult = true;
  Object? startError;
  Object? completionError;
  Object? restoreError;
  Future<void> Function()? onRestore;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    streamReads += 1;
    return updates.stream;
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    productQueries.add(Set<String>.of(identifiers));
    return ProductDetailsResponse(
      productDetails: identifiers.contains(_customPetProductId)
          ? [
              ProductDetails(
                id: _customPetProductId,
                title: '新增自訂寵物',
                description: '一個自訂寵物名額',
                price: 'NT\$30',
                rawPrice: 30,
                currencyCode: 'TWD',
                currencySymbol: 'NT\$',
              ),
            ]
          : [],
      notFoundIDs:
          identifiers.where((id) => id != _customPetProductId).toList(),
    );
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    purchaseStarts += 1;
    purchaseRequests.add(purchaseParam);
    final error = startError;
    if (error != null) throw error;
    return startResult;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    final error = completionError;
    if (error != null) throw error;
    completed.add(purchase.purchaseID);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls += 1;
    final error = restoreError;
    if (error != null) throw error;
    await onRestore?.call();
  }

  void emit(PurchaseDetails purchase) => updates.add([purchase]);

  Future<void> dispose() => updates.close();
}

/// In-memory stand-in for the two callable-function endpoints. Transaction
/// delivery is idempotent, as required of the actual backend.
class FakeBillingBackend {
  int credits = 0;
  int refreshCalls = 0;
  int verificationCalls = 0;
  Object? verificationError;
  Object? refreshError;
  Completer<void>? verificationGate;
  dynamic verificationResponseOverride;
  final delivered = <String>{};
  final refreshRequests = <Map<String, dynamic>>[];
  final verificationRequests = <Map<String, dynamic>>[];

  Future<dynamic> call(
    String name, {
    required Map<String, dynamic> data,
    required Duration timeout,
  }) async {
    switch (name) {
      case 'getCustomPetPurchaseCredit':
        refreshCalls += 1;
        refreshRequests.add(Map<String, dynamic>.of(data));
        final error = refreshError;
        if (error != null) throw error;
        return {
          'unusedCredits': credits,
          'productId': _customPetProductId,
        };
      case 'verifyCustomPetPurchase':
        verificationCalls += 1;
        verificationRequests.add(Map<String, dynamic>.of(data));
        await verificationGate?.future;
        final error = verificationError;
        if (error != null) throw error;
        final override = verificationResponseOverride;
        if (override != null) return override;
        final transactionId = data['transactionId'] as String;
        if (delivered.add(transactionId)) credits += 1;
        return {
          'ok': true,
          'unusedCredits': credits,
          'productId': _customPetProductId,
          'transactionId': transactionId,
          'environment': 'Sandbox',
        };
      default:
        throw StateError('Unexpected billing endpoint: $name');
    }
  }
}

PurchaseDetails billingPurchase({
  String id = 'tx-1',
  PurchaseStatus status = PurchaseStatus.purchased,
  bool pendingComplete = true,
}) =>
    PurchaseDetails(
      purchaseID: id,
      productID: _customPetProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'TEST-ONLY-LOCAL-RECEIPT-$id',
        serverVerificationData: 'TEST-ONLY-SERVER-RECEIPT-$id',
        source: 'app_store',
      ),
      transactionDate: '1700000000000',
      status: status,
    )..pendingCompletePurchase = pendingComplete;
