import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:luffy_focus/services/billing_service.dart';
import 'package:luffy_focus/viewmodels/pet_viewmodel.dart';
import 'package:luffy_focus/views/pet_upload_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_billing.dart';

/// Pet storage and AI generation are outside these payment UI tests. A real
/// ChangeNotifier keeps Provider's lifecycle real without constructing services.
class _IdlePetViewModel extends ChangeNotifier implements PetViewModel {
  PetUploadState _state = PetUploadState.idle;
  int discardCalls = 0;
  int resetCalls = 0;
  int saveCalls = 0;
  Object? saveError;
  String? pendingNormal;
  String? pendingSleeping;
  String? pendingFailed;
  String? _completedName;

  @override
  PetUploadState get uploadState => _state;

  @override
  bool get isAtPetLimit => false;

  @override
  String? get pendingNormalUrl => pendingNormal;

  @override
  String? get pendingSleepingUrl => pendingSleeping;

  @override
  String? get pendingFailedUrl => pendingFailed;

  @override
  String? get errorMessage => null;

  @override
  String? get completedPetName => _completedName ?? 'QA 寵物';

  @override
  String? get completedPetSpecies => 'cat';

  void setUploadState(PetUploadState state) {
    _state = state;
    notifyListeners();
  }

  @override
  Future<void> discardPendingUpload() async {
    discardCalls += 1;
    pendingNormal = pendingSleeping = pendingFailed = null;
    setUploadState(PetUploadState.idle);
  }

  @override
  void resetUploadState() {
    resetCalls += 1;
    pendingNormal = pendingSleeping = pendingFailed = null;
    setUploadState(PetUploadState.idle);
  }

  @override
  Future<void> savePetNameAndFinish(String name) async {
    saveCalls += 1;
    final error = saveError;
    if (error != null) throw error;
    _completedName = name;
    setUploadState(PetUploadState.success);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected pet operation: ${invocation.memberName}');
}

/// The real screen still decides when to request the gallery. Returning null
/// models the user dismissing it and prevents any upload or AI request.
class _DismissedGallery extends ImagePickerPlatform {
  int opens = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    expect(source, ImageSource.gallery);
    opens += 1;
    return null;
  }
}

class _PurchaseScreenHarness {
  final store = FakeBillingStore();
  final backend = FakeBillingBackend();
  final gallery = _DismissedGallery();
  final pets = _IdlePetViewModel();
  late final BillingService billing;
  late final ImagePickerPlatform _originalPicker;

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object> preferences = const {},
    bool asRoute = false,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    _originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = gallery;
    billing = BillingService(
      inAppPurchase: store,
      callFunction: backend.call,
      ensureSignedIn: ({required int attempts}) async => true,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      billing.dispose();
      pets.dispose();
      await store.dispose();
      ImagePickerPlatform.instance = _originalPicker;
    });
    await billing.initialize();
    await billing.refreshCustomPetCredit();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BillingService>.value(value: billing),
          ChangeNotifierProvider<PetViewModel>.value(value: pets),
        ],
        child: MaterialApp(
          home: asRoute
              ? Builder(builder: (context) {
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PetUploadScreen(),
                        ),
                      ),
                      child: const Text('開啟寵物流程'),
                    ),
                  );
                })
              : const PetUploadScreen(),
        ),
      ),
    );
    if (asRoute) {
      await tester.tap(find.text('開啟寵物流程'));
      await tester.pumpAndSettle();
    }
    await tester.pump();
    expect(find.text('購買解鎖名額 NT\$30'), findsOneWidget);
  }

  Future<void> buy(WidgetTester tester) async {
    await tester.tap(find.text('購買解鎖名額 NT\$30'));
    await _pumpUntil(tester, () => store.purchaseStarts == 1);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
  fail('Purchase UI did not reach the expected observable state.');
}

void main() {
  for (final state in [
    PetUploadState.analyzing,
    PetUploadState.generating,
  ]) {
    testWidgets(
        '${state.name} cannot discard a reserved pet draft by navigating back',
        (tester) async {
      final harness = _PurchaseScreenHarness();
      await harness.open(tester, asRoute: true);
      harness.pets.setUploadState(state);
      await tester.pump();

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PetUploadScreen), findsOneWidget);
      expect(harness.pets.uploadState, state);
      expect(harness.pets.discardCalls, 0);
      expect(harness.pets.resetCalls, 0);
    });
  }

  testWidgets(
      'a failed name save can leave with its draft and resume naming successfully',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    await harness.open(tester, asRoute: true);
    harness.pets
      ..pendingNormal = 'assets/images/luffy_awake.png'
      ..pendingSleeping = 'assets/images/luffy_sleeping.png'
      ..pendingFailed = 'assets/images/luffy_interrupted.png'
      ..saveError = StateError('temporary save failure');
    harness.pets.setUploadState(PetUploadState.naming);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'QA 寵物');
    await tester.tap(find.text('完成設定'));
    await _pumpUntil(tester, () => harness.pets.saveCalls == 1);
    expect(find.text('保存失敗，請稍後再試。'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(PetUploadScreen), findsNothing);
    expect(harness.pets.uploadState, PetUploadState.naming);
    expect(harness.pets.discardCalls, 0);
    expect(harness.pets.resetCalls, 0);
    expect(harness.pets.pendingNormalUrl, 'assets/images/luffy_awake.png');
    expect(harness.pets.pendingSleepingUrl, 'assets/images/luffy_sleeping.png');
    expect(
        harness.pets.pendingFailedUrl, 'assets/images/luffy_interrupted.png');

    await tester.tap(find.text('開啟寵物流程'));
    await tester.pumpAndSettle();
    expect(find.text('形象繪製完成！'), findsOneWidget);
    expect(find.text('完成設定'), findsOneWidget);

    harness.pets.saveError = null;
    await tester.enterText(find.byType(TextField).first, 'QA 重試成功');
    await tester.tap(find.text('完成設定'));
    await _pumpUntil(
        tester, () => harness.pets.uploadState == PetUploadState.success);
    expect(harness.pets.saveCalls, 2);
    expect(find.text('太棒了！'), findsOneWidget);
    expect(harness.pets.completedPetName, 'QA 重試成功');
    expect(harness.pets.discardCalls, 0);
    expect(harness.pets.resetCalls, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PetUploadScreen), findsNothing);
    expect(find.text('開啟寵物流程'), findsOneWidget);
  });

  testWidgets(
      'a new failed payment shows an uncertain-result instruction instead of declaring payment failure',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase(status: PurchaseStatus.error));
    await _pumpUntil(
        tester, () => harness.billing.state == CustomPetPurchaseState.error);

    expect(find.text('無法確認付款結果，請先查詢訂單，勿重複購買。'), findsOneWidget);
    expect(find.text('付款失敗，請稍後再試。'), findsNothing);
    expect(harness.gallery.opens, 0);
    expect(harness.backend.verificationCalls, 0);
  });

  testWidgets(
      'canceling the Apple sheet stays on purchase UI without opening gallery',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase(status: PurchaseStatus.canceled));
    await _pumpUntil(
      tester,
      () => harness.billing.state == CustomPetPurchaseState.idle,
    );

    expect(find.text('購買解鎖名額 NT\$30'), findsOneWidget);
    expect(find.text('支付成功，正在確認訂單...'), findsNothing);
    expect(harness.gallery.opens, 0);
    expect(harness.backend.verificationCalls, 0);
    expect(harness.billing.hasUnusedCredit, isFalse);
  });

  testWidgets(
      'pending approval keeps the gallery locked and cannot start another payment',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase(
      status: PurchaseStatus.pending,
      pendingComplete: false,
    ));
    await _pumpUntil(
      tester,
      () => harness.billing.state == CustomPetPurchaseState.pending,
    );
    final purchaseButton = find.byType(ElevatedButton).first;
    await tester.tap(purchaseButton);
    await tester.pump();

    expect(harness.gallery.opens, 0);
    expect(harness.billing.hasUnusedCredit, isFalse);
    expect(harness.backend.verificationCalls, 0);
    expect(harness.store.purchaseStarts, 1);
    expect(harness.store.completed, isEmpty);

    // Ask to Buy may outlast the purchase-sheet watchdog. Its approval is still
    // outstanding, so expiring that timer must not unlock a second purchase.
    await tester.pump(const Duration(seconds: 13));
    expect(harness.billing.state, CustomPetPurchaseState.pending);
    expect(harness.gallery.opens, 0);
    expect(harness.store.purchaseStarts, 1);
  });

  testWidgets(
      'server confirmation opens gallery once after duplicate paid callbacks',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    final gate = Completer<void>();
    harness.backend.verificationGate = gate;
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase());
    harness.store.emit(billingPurchase());
    await _pumpUntil(tester, () => harness.backend.verificationCalls > 0);
    await tester.pump();

    expect(find.text('支付成功，正在確認訂單...'), findsOneWidget);
    expect(harness.gallery.opens, 0);
    expect(harness.billing.hasUnusedCredit, isFalse);
    expect(harness.store.completed, isEmpty);

    gate.complete();
    await _pumpUntil(tester, () => harness.gallery.opens > 0);
    await tester.pump();

    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(harness.gallery.opens, 1);
    expect(harness.billing.unusedCredits, 1);
    expect(harness.store.completed, ['tx-1']);
    expect(harness.store.purchaseStarts, 1);
  });

  testWidgets(
      'verification failure can be retried from UI without another payment',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    harness.backend.verificationError =
        const SocketException('network unavailable');
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase());
    await _pumpUntil(
      tester,
      () =>
          harness.billing.state == CustomPetPurchaseState.error ||
          harness.billing.state == CustomPetPurchaseState.purchased,
    );
    await tester.pump();

    expect(harness.gallery.opens, 0);
    expect(find.text('我已支付'), findsOneWidget);
    expect(harness.store.completed, isEmpty);
    expect(harness.billing.hasUnusedCredit, isFalse);

    harness.backend.verificationError = null;
    await tester.tap(find.text('我已支付'));
    await _pumpUntil(tester, () => harness.gallery.opens > 0);

    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(harness.gallery.opens, 1);
    expect(harness.billing.unusedCredits, 1);
    expect(harness.backend.verificationCalls, 2);
    expect(harness.store.completed, ['tx-1']);
    expect(harness.store.purchaseStarts, 1);
  });

  testWidgets(
      'a stale StoreKit error after a verified purchase does not show a failure snackbar',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    await harness.open(tester);
    await harness.buy(tester);
    harness.store.emit(billingPurchase());
    await _pumpUntil(tester, () => harness.gallery.opens == 1);
    expect(find.text('從相簿選擇'), findsOneWidget);

    harness.store.emit(billingPurchase(status: PurchaseStatus.error));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('付款失敗，請稍後再試。'), findsNothing);
    expect(find.text('無法確認付款結果，請先查詢訂單，勿重複購買。'), findsNothing);
    expect(harness.billing.state, CustomPetPurchaseState.purchased);
    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(harness.gallery.opens, 1);
    expect(harness.billing.unusedCredits, 1);
  });

  testWidgets(
      'repeated failed manual verification never unlocks gallery or pet generation',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    harness.backend.verificationError =
        const SocketException('network unavailable');
    await harness.open(tester);
    await harness.buy(tester);

    harness.store.emit(billingPurchase());
    await _pumpUntil(
        tester, () => harness.billing.state == CustomPetPurchaseState.error);
    expect(find.text('我已支付'), findsOneWidget);
    expect(harness.gallery.opens, 0);

    await tester.tap(find.text('我已支付'));
    await _pumpUntil(
      tester,
      () =>
          harness.backend.verificationCalls == 2 &&
          harness.billing.state == CustomPetPurchaseState.error,
    );

    expect(harness.billing.unusedCredits, 0);
    expect(harness.billing.hasUnusedCredit, isFalse);
    expect(harness.gallery.opens, 0);
    expect(find.text('我已支付'), findsOneWidget);
    expect(find.text('從相簿選擇'), findsNothing);
    expect(find.text('送出'), findsNothing);
    expect(harness.store.purchaseStarts, 1);
    expect(harness.store.completed, isEmpty);
    expect(
      harness.backend.verificationRequests
          .map((request) => request['transactionId']),
      ['tx-1', 'tx-1'],
    );
  });

  testWidgets(
      'legacy local credits cannot show upload UI when the server balance is unavailable',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    harness.backend.refreshError = const SocketException('network unavailable');
    await harness.open(tester, preferences: {
      'luffy_local_unused_credits': 2,
      'luffy_local_unverified_credits': 2,
    });

    expect(find.text('購買解鎖名額 NT\$30'), findsOneWidget);
    expect(find.text('從相簿選擇'), findsNothing);
    expect(find.text('送出'), findsNothing);
    expect(harness.billing.unusedCredits, 0);
    expect(harness.billing.hasUnusedCredit, isFalse);
    expect(harness.gallery.opens, 0);
    expect(harness.store.purchaseStarts, 0);
    expect(harness.backend.verificationCalls, 0);
  });

  testWidgets(
      'failed restore reports a failure rather than no purchase history',
      (tester) async {
    final harness = _PurchaseScreenHarness();
    harness.store.restoreError = const SocketException('network unavailable');
    await harness.open(tester);

    await tester.tap(find.text('恢復購買'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('未找到可恢復'), findsNothing);
    expect(find.textContaining('恢復購買'), findsNWidgets(2));
    expect(harness.billing.state, CustomPetPurchaseState.error);
    expect(harness.gallery.opens, 0);
    expect(harness.store.purchaseStarts, 0);
  });
}
