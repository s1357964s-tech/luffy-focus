import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';

/// StoreKit 彈窗關閉後的即時結果
/// 此訊號在收到 Apple 回呼後「立即」發出，不等待後端驗證完成
enum CustomPetPurchaseOutcome {
  purchased, // 付款已被 Apple 確認，等待後端收據驗證
  canceled, // 用戶主動關閉彈窗或取消
  failed, // 付款流程出現錯誤
}

enum CustomPetPurchaseState {
  idle,
  loading,
  purchasing,
  pending,
  purchased,
  error,
}

class _BillingVerificationException implements Exception {
  const _BillingVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef BillingFunctionCaller = Future<dynamic> Function(
  String name, {
  required Map<String, dynamic> data,
  required Duration timeout,
});

typedef BillingSignIn = Future<bool> Function({required int attempts});

class BillingService extends ChangeNotifier {
  static const String customPetProductId = 'luffy.custom_pet.create.v1';
  static const bool _bypassIap =
      bool.fromEnvironment('BYPASS_CUSTOM_PET_IAP', defaultValue: false);
  static const List<Duration> _purchaseStartRecoveryDelays = [
    Duration(milliseconds: 350),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1400),
    Duration(milliseconds: 2200),
  ];
  static const Duration _purchaseFlowRecoveryTimeout = Duration(seconds: 12);

  final InAppPurchase? _iapOverride;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;
  final bool _storeKitReady;
  final BillingFunctionCaller _functionCaller;
  final BillingSignIn _ensureSignedIn;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _customPetProduct;
  final Map<String, PurchaseDetails> _pendingPurchases = {};
  final Map<String, Future<void>> _verificationFutures = {};
  final Set<String> _verifiedTransactions = {};
  Future<void> _verificationQueue = Future<void>.value();
  int _balanceRevision = 0;
  bool _storePaymentPending = false;
  Timer? _purchaseFlowRecoveryTimer;
  Future<void>? _initializationFuture;
  Future<void>? _creditRefreshFuture;
  Future<void>? _purchaseStartFuture;
  bool _disposed = false;

  /// 用於 [waitForCreditConfirmation] 等待後端 credit 確認結果
  /// 在 [_verifyAndDeliver] 完成後由 [_completeCreditConfirmation] 觸發
  Completer<bool>? _creditConfirmationCompleter;

  /// 廣播 StoreKit 彈窗的即時結果給 UI
  /// 使用 broadcast 讓多個 listener 可同時訂閱（例如不同 widget 重建後重新 listen）
  final StreamController<CustomPetPurchaseOutcome> _purchaseOutcomeController =
      StreamController<CustomPetPurchaseOutcome>.broadcast();

  CustomPetPurchaseState _state = CustomPetPurchaseState.idle;
  String? _errorMessage;
  int _unusedCredits = 0;
  bool _isAvailable = false;
  bool _isInitialized = false;

  static const String _localCreditsKey = 'luffy_local_unused_credits';
  static const String _localUnverifiedCreditsKey =
      'luffy_local_unverified_credits';

  void _updateUnusedCredits(int value) {
    if (_unusedCredits != value) {
      _unusedCredits = value;
      if (!_disposed) notifyListeners();
    }
  }

  BillingService({
    InAppPurchase? inAppPurchase,
    BillingFunctionCaller? callFunction,
    BillingSignIn? ensureSignedIn,
    bool storeKitReady = true,
  })  : _iapOverride = inAppPurchase,
        _storeKitReady = storeKitReady,
        _functionCaller = callFunction ?? FirebaseService.callFunction,
        _ensureSignedIn = ensureSignedIn ??
            (({required int attempts}) =>
                FirebaseService.ensureSignedIn(attempts: attempts)) {
    if (_storeKitReady) {
      _purchaseSubscription = _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error) {
          _setError('內購連線失敗，請稍後再試。');
          _completeCreditConfirmation(false);
        },
      );
    }
    unawaited(_initLocalCreditsAndRefresh());
  }

  Future<void> _initLocalCreditsAndRefresh() async {
    // These legacy values could include credits whose Apple receipt was never
    // verified. Only the current Firebase user's server balance can unlock AI.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localCreditsKey);
      await prefs.remove(_localUnverifiedCreditsKey);
    } catch (error) {
      debugPrint('[Billing] legacy credit cache cleanup failed: $error');
    }
    if (_disposed) return;
    await refreshCustomPetCredit();
  }

  CustomPetPurchaseState get state => _state;
  String? get errorMessage => _errorMessage;
  int get unusedCredits => _unusedCredits;
  bool get isPaymentPending => _storePaymentPending;

  /// 是否有可用的新增寵物名額（含開發繞過模式）
  bool get hasUnusedCredit => _bypassIap || _unusedCredits > 0;

  /// StoreKit 彈窗即時結果 Stream
  /// UI 應在 initState 訂閱並在 dispose 取消，收到訊號後決定下一步動作
  Stream<CustomPetPurchaseOutcome> get purchaseOutcomeStream =>
      _purchaseOutcomeController.stream;

  /// 從 App Store Connect 動態取得的本地化價格文字（如 NT$30）
  String get customPetPriceLabel => _customPetProduct?.price ?? '—';

  // ──────────────────────────────────────────────────────────────────────────
  // 公開 API
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize({bool forceProductRefresh = false}) async {
    if (_isInitialized && _customPetProduct != null && !forceProductRefresh) {
      return;
    }
    if (_initializationFuture != null && !forceProductRefresh) {
      return _initializationFuture!;
    }

    final future =
        _initializeStoreKit(forceProductRefresh: forceProductRefresh);
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  /// 發起自定義寵物解鎖購買（fire-and-forget）
  ///
  /// 此方法只負責啟動 StoreKit 購買流程，結果透過 [purchaseOutcomeStream] 通知 UI。
  /// UI 收到 [CustomPetPurchaseOutcome.purchased] 後，應呼叫 [waitForCreditConfirmation]
  /// 等待後端收據驗證完成，再進入上傳圖片流程。
  Future<void> purchaseCustomPetUnlock() async {
    if (_purchaseStartFuture != null) return _purchaseStartFuture!;
    final future = _purchaseCustomPetUnlock();
    _purchaseStartFuture = future;
    try {
      await future;
    } finally {
      if (identical(_purchaseStartFuture, future)) _purchaseStartFuture = null;
    }
  }

  Future<void> _purchaseCustomPetUnlock() async {
    if (_pendingPurchases.isNotEmpty) {
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
      await refreshCustomPetCredit();
      return;
    }
    if (_storePaymentPending ||
        _state == CustomPetPurchaseState.purchasing ||
        _state == CustomPetPurchaseState.pending) {
      return;
    }
    // 開發繞過模式：直接給一個 credit 並通知購買成功
    if (_bypassIap) {
      _updateUnusedCredits(1);
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
      return;
    }

    // 已有名額，不需再購買，直接通知可進入上傳流程
    if (_unusedCredits > 0) {
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
      return;
    }

    // 清理殘留的失敗或暫停狀態
    if (_state == CustomPetPurchaseState.error) {
      _setState(CustomPetPurchaseState.idle);
    }

    // 確保 StoreKit 初始化完成並取得商品資訊
    debugPrint(
        '[Billing] before initialize, _customPetProduct=${_customPetProduct?.id}, state=$_state, error=$_errorMessage');
    await initialize(forceProductRefresh: _customPetProduct == null);
    debugPrint(
        '[Billing] after initialize, _customPetProduct=${_customPetProduct?.id}, _isAvailable=$_isAvailable, state=$_state');

    // 初始化後再次確認是否已有名額（刷新 credit 可能帶入新資料）
    if (_unusedCredits > 0) {
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
      return;
    }

    if (_customPetProduct == null) {
      debugPrint(
          '[Billing] FAILED: _customPetProduct is null after initialize, errorMessage=$_errorMessage');
      _setError('連接 App Store 逾時，請稍後再試。');
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.failed);
      return;
    }

    // Confirm delivery is reachable before opening a new paid transaction.
    await refreshCustomPetCredit();
    if (_errorMessage != null) {
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.failed);
      return;
    }
    if (hasUnusedCredit) {
      _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
      return;
    }

    // 發起 StoreKit 消耗性商品購買
    try {
      await _finishStaleStoreKitFailedTransactions();
      _setState(CustomPetPurchaseState.purchasing);
      _schedulePurchaseFlowRecovery();
      debugPrint(
          '[Billing] starting consumable purchase for ${_customPetProduct!.id}');
      await _startConsumablePurchase();
      debugPrint('[Billing] _startConsumablePurchase returned successfully');
    } catch (error) {
      debugPrint('[Billing] purchase start error: $error');
      if (error.toString().contains('storekit_duplicate_product_object') &&
          _pendingPurchases.isNotEmpty) {
        debugPrint(
            '[Billing] Duplicate transaction found in memory. Retrying verification.');
        _setState(CustomPetPurchaseState.pending);
        _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
        unawaited(refreshCustomPetCredit());
        return;
      }
      final recovered = await _recoverAndRestartPurchaseAfterStartError(error);
      if (!recovered) {
        _storePaymentPending = false;
        if (_isRecoverableStoreKitStartError(error)) {
          _setState(CustomPetPurchaseState.idle);
        } else {
          _setError('付款流程啟動失敗，請稍後再試。');
          debugPrint(
              '[Billing] purchase start failed (non-recoverable): $error');
        }
        _emitPurchaseOutcome(CustomPetPurchaseOutcome.failed);
      }
    }
  }

  /// 在收到 [CustomPetPurchaseOutcome.purchased] 後，等待後端收據驗證完成
  ///
  /// 回傳 true 代表 credit 已成功入帳，可進入上傳流程。
  /// 回傳 false 代表驗證失敗或逾時，應顯示錯誤訊息。
  Future<bool> waitForCreditConfirmation({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    // 已有名額或狀態已確認，直接回傳
    if (_unusedCredits > 0) return true;
    if (_state == CustomPetPurchaseState.error) return false;

    // 建立或複用 Completer 等待 _verifyAndDeliver 完成
    _creditConfirmationCompleter ??= Completer<bool>();
    return _creditConfirmationCompleter!.future.timeout(
      timeout,
      onTimeout: () => false,
    );
  }

  /// 恢復歷史購買（StoreKit 恢復流程）
  Future<void> restorePurchases() async {
    if (!_storeKitReady) {
      const message = '內購初始化未完成，請重新啟動 App 後再試。';
      _setError(message);
      throw const _BillingVerificationException(message);
    }
    _setState(CustomPetPurchaseState.loading);
    try {
      await _iap.restorePurchases();
      // StoreKit publishes restored transactions on its stream. Let that event
      // arrive, then await verification and refresh the server-owned balance.
      await Future<void>.delayed(Duration.zero);
      await refreshCustomPetCredit();
      if (_errorMessage != null) {
        throw _BillingVerificationException(_errorMessage!);
      }
      if (_state == CustomPetPurchaseState.loading) {
        _setState(hasUnusedCredit
            ? CustomPetPurchaseState.purchased
            : CustomPetPurchaseState.idle);
      }
    } catch (error) {
      _setError('恢復購買失敗：$error');
      rethrow;
    }
  }

  Future<void> refreshCustomPetCredit({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_creditRefreshFuture != null) return _creditRefreshFuture!;

    final future = _refreshCreditAndPendingPurchases(timeout);
    _creditRefreshFuture = future;
    try {
      await future;
    } finally {
      if (identical(_creditRefreshFuture, future)) {
        _creditRefreshFuture = null;
      }
    }
  }

  Future<void> _refreshCreditAndPendingPurchases(Duration timeout) async {
    final pending = _pendingPurchases.values.toList();
    if (pending.isNotEmpty) {
      await Future.wait(pending.map(_verifyAndDeliver));
    } else {
      await _refreshCustomPetCredit(timeout: timeout);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 私有方法
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _initializeStoreKit({required bool forceProductRefresh}) async {
    if (!_storeKitReady) {
      _setError('內購初始化未完成，請重新啟動 App 後再試。');
      return;
    }
    try {
      unawaited(refreshCustomPetCredit());

      _isAvailable = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!_isAvailable) {
        _setError('App Store 內購目前無法使用，請稍後再試。');
        return;
      }

      final productReady = await _loadCustomPetProduct(
        force: forceProductRefresh,
      ).timeout(const Duration(seconds: 12));
      if (!productReady) return;

      unawaited(refreshCustomPetCredit());
      _isInitialized = true;
      _setState(CustomPetPurchaseState.idle);
    } catch (error) {
      _setError(_readableStoreError(error.toString()));
      if (kDebugMode) {
        debugPrint('[Billing] initialize failed: $error');
      }
    }
  }

  Future<bool> _loadCustomPetProduct({bool force = false}) async {
    if (_customPetProduct != null && !force) return true;

    final response = await _iap.queryProductDetails({customPetProductId});
    if (kDebugMode) {
      debugPrint(
        '[Billing] product query product=$customPetProductId '
        'details=${response.productDetails.map((p) => p.id).join(',')} '
        'notFound=${response.notFoundIDs.join(',')} '
        'error=${response.error?.code}:${response.error?.message}',
      );
    }

    if (response.error != null) {
      _setError(_readableStoreError(response.error!.message));
      return false;
    }
    if (response.productDetails.isEmpty) {
      final notFound = response.notFoundIDs.isEmpty
          ? customPetProductId
          : response.notFoundIDs.join(', ');
      _setError(
        'App Store 找不到新增寵物名額商品（$notFound）。請確認商品 ID、Bundle ID、'
        'Paid Apps 合約，以及 App Store Connect 商品已同步到 Sandbox。',
      );
      return false;
    }

    _customPetProduct = response.productDetails.first;
    return true;
  }

  Future<void> _refreshCustomPetCredit({required Duration timeout}) async {
    if (_bypassIap) {
      _updateUnusedCredits(1);
      return;
    }
    final balanceRevision = _balanceRevision;
    try {
      if (!await _ensureSignedIn(attempts: 2)) {
        throw const _BillingVerificationException('無法確認已購名額，請連線後重試。');
      }
      final data = await _callFunction(
        'getCustomPetPurchaseCredit',
        timeout: timeout,
      );
      if (balanceRevision != _balanceRevision) return;
      _updateUnusedCredits(_remoteCredits(data));
      _errorMessage = null;
      if (_state == CustomPetPurchaseState.purchased && !hasUnusedCredit) {
        _setState(CustomPetPurchaseState.idle);
      }
    } catch (error) {
      if (balanceRevision != _balanceRevision) return;
      _setError(_readablePurchaseError(error));
      if (kDebugMode) {
        debugPrint('[Billing] refresh credit failed: $error');
      }
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      if (purchase.productID != customPetProductId) continue;

      debugPrint(
          '[Billing] _handlePurchaseUpdates: productID=${purchase.productID}, status=${purchase.status}, error=${purchase.error?.code}:${purchase.error?.message}');
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // 等待用戶在彈窗中操作，保持 purchasing 狀態並重置計時器
          _storePaymentPending = true;
          _setState(CustomPetPurchaseState.pending);
          _schedulePurchaseFlowRecovery();
          break;

        case PurchaseStatus.error:
          // Apple 回傳錯誤，立即通知 UI
          _storePaymentPending = false;
          _cancelPurchaseFlowRecovery();
          await _completePurchaseIfNeeded(purchase);
          _setError(purchase.error?.message ?? '付款失敗，請稍後再試。');
          _completeCreditConfirmation(false);
          _emitPurchaseOutcome(CustomPetPurchaseOutcome.failed);
          break;

        case PurchaseStatus.canceled:
          // 用戶主動取消，立即通知 UI（不顯示任何錯誤）
          _storePaymentPending = false;
          debugPrint('[Billing] user canceled purchase');
          _cancelPurchaseFlowRecovery();
          await _completePurchaseIfNeeded(purchase);
          _setState(CustomPetPurchaseState.idle);
          _completeCreditConfirmation(false);
          _emitPurchaseOutcome(CustomPetPurchaseOutcome.canceled);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Apple 已確認付款，立即通知 UI（不等待後端驗證）
          _storePaymentPending = false;
          debugPrint(
              '[Billing] purchase confirmed by Apple, starting verification');
          _cancelPurchaseFlowRecovery();
          final key = _transactionKey(purchase);
          if (purchase.purchaseID == null || purchase.purchaseID!.isEmpty) {
            _setError('付款交易編號尚未取得，請稍後重新確認付款結果。');
            _completeCreditConfirmation(false);
            break;
          }
          final alreadyProcessing = _pendingPurchases.containsKey(key) ||
              _verifiedTransactions.contains(key);
          _pendingPurchases[key] = purchase;
          if (!alreadyProcessing) {
            _emitPurchaseOutcome(CustomPetPurchaseOutcome.purchased);
          }
          // 異步執行後端收據驗證，結果透過 _creditConfirmationCompleter 回傳
          unawaited(_verifyAndDeliver(purchase));
          break;
      }
    }
  }

  String _transactionKey(PurchaseDetails purchase) =>
      '${purchase.productID}:${purchase.purchaseID}';

  int _remoteCredits(dynamic data) {
    if (data is! Map || data['productId'] != customPetProductId) {
      throw const _BillingVerificationException('名額確認回應不完整，請重新驗證。');
    }
    final value = data['unusedCredits'];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value.toInt() != value) {
      throw const _BillingVerificationException('名額確認回應不完整，請重新驗證。');
    }
    return value.toInt();
  }

  Future<void> _verifyAndDeliver(PurchaseDetails purchase) {
    final key = _transactionKey(purchase);
    final inFlight = _verificationFutures[key];
    if (inFlight != null) return inFlight;
    _pendingPurchases[key] = purchase;
    late final Future<void> future;
    future = _verificationQueue
        .then((_) => _verifyReceiptAndDeliver(purchase, key))
        .whenComplete(() {
      if (identical(_verificationFutures[key], future)) {
        _verificationFutures.remove(key);
      }
    });
    _verificationQueue = future;
    _verificationFutures[key] = future;
    return future;
  }

  Future<void> _verifyReceiptAndDeliver(
      PurchaseDetails purchase, String key) async {
    try {
      _setState(CustomPetPurchaseState.loading);
      final signedIn = await _ensureSignedIn(attempts: 3);
      if (!signedIn) {
        throw const _BillingVerificationException(
          '付款已完成，但目前無法登入驗證服務。請確認網路後重試，不會重複扣款。',
        );
      }

      if (_verifiedTransactions.contains(key)) {
        if (await _completePurchaseIfNeeded(purchase)) {
          _pendingPurchases.remove(key);
        }
        await _refreshCustomPetCredit(timeout: const Duration(seconds: 12));
        _setState(hasUnusedCredit
            ? CustomPetPurchaseState.purchased
            : CustomPetPurchaseState.idle);
        _completeCreditConfirmation(hasUnusedCredit);
        return;
      }

      final data = await _callFunction(
        'verifyCustomPetPurchase',
        data: {
          'productId': purchase.productID,
          'transactionId': purchase.purchaseID ?? '',
          'transactionDate': purchase.transactionDate,
          'verificationData': purchase.verificationData.serverVerificationData,
          'localVerificationData':
              purchase.verificationData.localVerificationData,
          'verificationSource': purchase.verificationData.source,
        },
        timeout: const Duration(seconds: 90),
      );

      if (data is! Map ||
          data['ok'] != true ||
          data['transactionId'] != purchase.purchaseID) {
        throw const _BillingVerificationException('付款尚未驗證成功，請重新確認付款結果。');
      }
      final verifiedCredits = _remoteCredits(data);
      _balanceRevision += 1;
      _updateUnusedCredits(verifiedCredits);
      _verifiedTransactions.add(key);
      if (await _completePurchaseIfNeeded(purchase)) {
        _pendingPurchases.remove(key);
      }
      _setState(hasUnusedCredit
          ? CustomPetPurchaseState.purchased
          : CustomPetPurchaseState.idle);
      _completeCreditConfirmation(hasUnusedCredit);
    } catch (error) {
      // Leave the paid transaction unfinished so StoreKit redelivers it after
      // restart. Retrying verifies the same transaction; it never buys again.
      _setError(_readablePurchaseError(error));
      _completeCreditConfirmation(false);
      if (kDebugMode) {
        debugPrint('[Billing] verify failed: $error');
      }
    }
  }

  Future<void> _startConsumablePurchase() async {
    _storePaymentPending = true;
    final purchaseParam = PurchaseParam(productDetails: _customPetProduct!);
    final started = await _iap.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: true,
    );
    if (!started) {
      throw StateError('StoreKit did not start the purchase flow.');
    }
  }

  Future<bool> _recoverAndRestartPurchaseAfterStartError(
    Object startError,
  ) async {
    if (!_isRecoverableStoreKitStartError(startError)) return false;

    for (final delay in _purchaseStartRecoveryDelays) {
      await Future<void>.delayed(delay);
      final cleanedUp = await _finishStaleStoreKitFailedTransactions();
      if (!cleanedUp) continue;

      try {
        _setState(CustomPetPurchaseState.purchasing);
        _schedulePurchaseFlowRecovery();
        await _startConsumablePurchase();
        if (kDebugMode) {
          debugPrint(
            '[Billing] restarted purchase after StoreKit cleanup: $startError',
          );
        }
        return true;
      } catch (retryError) {
        if (!_isRecoverableStoreKitStartError(retryError)) {
          if (kDebugMode) {
            debugPrint('[Billing] purchase restart failed: $retryError');
          }
          return false;
        }
      }
    }
    return false;
  }

  Future<bool> _finishStaleStoreKitFailedTransactions() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }

    try {
      final queue = SKPaymentQueueWrapper();
      final transactions = await queue.transactions();
      var finishedAny = false;
      for (final transaction in transactions) {
        if (transaction.payment.productIdentifier != customPetProductId ||
            transaction.transactionState !=
                SKPaymentTransactionStateWrapper.failed) {
          continue;
        }
        await queue.finishTransaction(transaction);
        finishedAny = true;
      }
      return finishedAny;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Billing] StoreKit stale cleanup failed: $error');
      }
      return false;
    }
  }

  Future<bool> _completePurchaseIfNeeded(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return true;
    try {
      await _iap.completePurchase(purchase);
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Billing] complete purchase failed: $error');
      }
      return false;
    }
  }

  /// 在彈窗啟動後啟動一個 12 秒計時器
  /// 若逾時前仍未收到 StoreKit 結果，自動重置為 idle 狀態
  void _schedulePurchaseFlowRecovery() {
    _purchaseFlowRecoveryTimer?.cancel();
    _purchaseFlowRecoveryTimer = Timer(_purchaseFlowRecoveryTimeout, () async {
      _purchaseFlowRecoveryTimer = null;
      if (_pendingPurchases.isNotEmpty) return;
      if (_state != CustomPetPurchaseState.purchasing &&
          _state != CustomPetPurchaseState.pending) {
        return;
      }

      if (kDebugMode) {
        debugPrint('[Billing] purchase flow timed out before StoreKit result.');
      }
      // No terminal StoreKit event means no permission to buy again. Deferred
      // payments can outlive this timer, including Ask to Buy approval.
      _setState(CustomPetPurchaseState.pending);
      await _finishStaleStoreKitFailedTransactions();
    });
  }

  void _cancelPurchaseFlowRecovery() {
    _purchaseFlowRecoveryTimer?.cancel();
    _purchaseFlowRecoveryTimer = null;
  }

  /// 完成後端 credit 確認，通知正在等待的 [waitForCreditConfirmation]
  void _completeCreditConfirmation(bool result) {
    final completer = _creditConfirmationCompleter;
    _creditConfirmationCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  bool _isRecoverableStoreKitStartError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('storekit') ||
        message.contains('pending transaction') ||
        message.contains('duplicate') ||
        message.contains('already been added') ||
        message.contains('already exists') ||
        message.contains('product object') ||
        message.contains('payment cancelled') ||
        message.contains('overlaycancelled') ||
        message.contains('did not start the purchase flow');
  }

  Future<dynamic> _callFunction(
    String name, {
    Map<String, dynamic> data = const {},
    required Duration timeout,
  }) async {
    return _functionCaller(
      name,
      data: data,
      timeout: timeout,
    );
  }

  String _readablePurchaseError(Object error) {
    if (error is _BillingVerificationException) return error.message;
    if (error is SocketException) {
      return '付款已完成，但暫時無法連線驗證。請確認網路後重試，不會重複扣款。';
    }
    if (error is FirebaseFunctionsException) {
      final normalized = (error.message ?? '').toLowerCase();
      if (error.code == 'unauthenticated' ||
          normalized.contains('authentication') ||
          normalized.contains('auth') ||
          normalized.contains('tls') ||
          normalized.contains('secure connection') ||
          normalized.contains('network') ||
          normalized.contains('timeout') ||
          error.code == 'unavailable') {
        return '付款已完成，但暫時無法連線驗證。請確認網路後重試，不會重複扣款。';
      }
      return (error.message != null && error.message!.isNotEmpty)
          ? error.message!
          : '付款驗證失敗，請稍後再試。';
    }
    if (error is TimeoutException) {
      return '付款已完成，但驗證服務連線逾時。請稍後重試，不會重複扣款。';
    }
    return '付款驗證失敗，請稍後再試。';
  }

  String _readableStoreError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('storekit') ||
        normalized.contains('failed to get response from platform') ||
        normalized.contains('product') ||
        normalized.contains('not found')) {
      return 'App Store 內購商品尚未準備好，請確認 Sandbox 或 App Store Connect 已設定商品。';
    }
    if (normalized.contains('network') || normalized.contains('timeout')) {
      return '無法連接 App Store，請確認網路後再試。';
    }
    return '內購目前無法使用，請稍後再試。';
  }

  void _setState(CustomPetPurchaseState state) {
    _state = state;
    if (state != CustomPetPurchaseState.error) {
      _errorMessage = null;
    }
    if (!_disposed) notifyListeners();
  }

  void _setError(String message) {
    _state = CustomPetPurchaseState.error;
    _errorMessage = message;
    if (!_disposed) notifyListeners();
  }

  void _emitPurchaseOutcome(CustomPetPurchaseOutcome outcome) {
    if (!_disposed) _purchaseOutcomeController.add(outcome);
  }

  @override
  void dispose() {
    _disposed = true;
    _completeCreditConfirmation(false);
    _cancelPurchaseFlowRecovery();
    _purchaseSubscription?.cancel();
    _purchaseOutcomeController.close();
    super.dispose();
  }
}
