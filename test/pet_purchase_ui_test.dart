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
  @override
  PetUploadState get uploadState => PetUploadState.idle;

  @override
  bool get isAtPetLimit => false;

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

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(home: PetUploadScreen()),
      ),
    );
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
