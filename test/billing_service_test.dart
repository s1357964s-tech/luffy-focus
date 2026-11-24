import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:luffy_focus/services/billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_billing.dart';

Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Billing operation did not reach the expected observable state.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'failed StoreKit1 setup blocks purchase and restore before accessing the store',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = BillingService(
      inAppPurchase: store,
      storeKitReady: false,
      callFunction: backend.call,
      ensureSignedIn: ({required int attempts}) async => true,
    );
    addTearDown(() async {
      service.dispose();
      await store.dispose();
    });
    await service.initialize();
    await service.purchaseCustomPetUnlock();
    await expectLater(service.restorePurchases(), throwsException);
    expect(store.streamReads, 0);
    expect(store.productQueries, isEmpty);
    expect(store.purchaseStarts, 0);
    expect(store.restoreCalls, 0);
  });

  Future<BillingService> start(
    FakeBillingStore store,
    FakeBillingBackend backend, {
    Map<String, Object> preferences = const {},
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final service = BillingService(
      inAppPurchase: store,
      callFunction: backend.call,
      ensureSignedIn: ({required int attempts}) async => signedIn,
    );
    addTearDown(() async {
      service.dispose();
      await store.dispose();
    });
    await service.initialize();
    await service.refreshCustomPetCredit();
    return service;
  }

  test('network failure neither grants credit nor finishes a paid transaction',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend()
      ..verificationError = const SocketException('network unavailable');
    final service = await start(store, backend);

    store.emit(billingPurchase());
    await eventually(() =>
        backend.verificationCalls == 1 &&
        (service.state == CustomPetPurchaseState.error ||
            service.state == CustomPetPurchaseState.purchased));

    expect(service.unusedCredits, 0);
    expect(service.hasUnusedCredit, isFalse);
    expect(store.completed, isEmpty);
    expect(await service.waitForCreditConfirmation(), isFalse);
  });

  test('cached unverified credits cannot unlock a server-backed pet creation',
      () async {
    final service =
        await start(FakeBillingStore(), FakeBillingBackend(), preferences: {
      'luffy_local_unused_credits': 2,
      'luffy_local_unverified_credits': 2,
    });
    expect(service.unusedCredits, 0);
    expect(service.hasUnusedCredit, isFalse);
  });

  test('a paid transaction retries verification without a second purchase',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend()
      ..verificationError = const SocketException('network unavailable');
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() =>
        backend.verificationCalls == 1 &&
        (service.state == CustomPetPurchaseState.error ||
            service.state == CustomPetPurchaseState.purchased));

    backend.verificationError = null;
    await service.refreshCustomPetCredit();

    expect(backend.verificationCalls, 2);
    expect(backend.credits, 1);
    expect(service.unusedCredits, 1);
    expect(store.completed, ['tx-1']);
    expect(store.purchaseStarts, 0);
  });

  test('duplicate StoreKit callbacks share one in-flight receipt verification',
      () async {
    final store = FakeBillingStore();
    final gate = Completer<void>();
    final backend = FakeBillingBackend()..verificationGate = gate;
    final service = await start(store, backend);
    store.emit(billingPurchase());
    store.emit(billingPurchase());
    await eventually(() => backend.verificationCalls > 0);
    await Future<void>.delayed(Duration.zero);
    final inFlightCalls = backend.verificationCalls;
    gate.complete();
    await eventually(() => service.state == CustomPetPurchaseState.purchased);

    expect(inFlightCalls, 1);
    expect(backend.credits, 1);
    expect(store.completed, ['tx-1']);
  });

  test('credit is available only after a successful backend receipt response',
      () async {
    final store = FakeBillingStore();
    final gate = Completer<void>();
    final backend = FakeBillingBackend()..verificationGate = gate;
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() => backend.verificationCalls == 1);
    expect(service.hasUnusedCredit, isFalse);
    expect(store.completed, isEmpty);

    final confirmation = service.waitForCreditConfirmation();
    gate.complete();
    expect(await confirmation, isTrue);
    expect(service.unusedCredits, 1);
    expect(store.completed, ['tx-1']);
  });

  test('a failed or malformed backend response never delivers the purchase',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend()
      ..verificationResponseOverride = {'ok': false, 'unusedCredits': 99};
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() =>
        backend.verificationCalls == 1 &&
        (service.state == CustomPetPurchaseState.error ||
            service.state == CustomPetPurchaseState.purchased));
    expect(service.unusedCredits, 0);
    expect(store.completed, isEmpty);
    expect(await service.waitForCreditConfirmation(), isFalse);
  });

  test('failed StoreKit completion can retry without delivering another credit',
      () async {
    final store = FakeBillingStore()
      ..completionError = StateError('temporary StoreKit connection failure');
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() => service.state == CustomPetPurchaseState.purchased);
    expect(backend.credits, 1);

    store.completionError = null;
    await service.refreshCustomPetCredit();
    expect(store.completed, contains('tx-1'));
    expect(backend.credits, 1);
    expect(store.purchaseStarts, 0);
  });

  test('cancellation does not verify a receipt or unlock pet creation',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    final outcome = service.purchaseOutcomeStream.first;
    store.emit(billingPurchase(status: PurchaseStatus.canceled));
    expect(await outcome, CustomPetPurchaseOutcome.canceled);
    expect(service.state, CustomPetPurchaseState.idle);
    expect(service.unusedCredits, 0);
    expect(backend.verificationCalls, 0);
  });

  test('pending Apple payment cannot start a second consumable purchase',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    await service.purchaseCustomPetUnlock();
    store.emit(billingPurchase(
        status: PurchaseStatus.pending, pendingComplete: false));
    await eventually(() => service.state == CustomPetPurchaseState.pending);
    await service.purchaseCustomPetUnlock();
    expect(store.purchaseStarts, 1);
    expect(backend.verificationCalls, 0);
    expect(service.state, CustomPetPurchaseState.pending);
  });

  test('restore waits for asynchronous verification before reporting credits',
      () async {
    final store = FakeBillingStore();
    final gate = Completer<void>();
    final backend = FakeBillingBackend()..verificationGate = gate;
    final service = await start(store, backend);
    store.onRestore = () async {
      store.emit(billingPurchase(status: PurchaseStatus.restored));
    };
    var restoreCompleted = false;
    final restore =
        service.restorePurchases().then((_) => restoreCompleted = true);
    await eventually(() => backend.verificationCalls == 1);
    await Future<void>.delayed(Duration.zero);
    final completedBeforeVerification = restoreCompleted;
    gate.complete();
    await restore;
    await eventually(() => service.state == CustomPetPurchaseState.purchased);
    expect(completedBeforeVerification, isFalse);
    expect(service.unusedCredits, 1);
  });

  test('restore propagates a StoreKit failure to the caller', () async {
    final store = FakeBillingStore()
      ..restoreError = StateError('StoreKit unavailable');
    final service = await start(store, FakeBillingBackend());
    await expectLater(service.restorePurchases(), throwsStateError);
    expect(service.state, CustomPetPurchaseState.error);
  });

  test('one timed-out confirmation listener does not discard another listener',
      () async {
    final store = FakeBillingStore();
    final gate = Completer<void>();
    final backend = FakeBillingBackend()..verificationGate = gate;
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() => backend.verificationCalls == 1);
    final shortWait = service.waitForCreditConfirmation(
        timeout: const Duration(milliseconds: 1));
    final longWait =
        service.waitForCreditConfirmation(timeout: const Duration(seconds: 2));
    expect(await shortWait, isFalse);
    gate.complete();
    expect(await longWait, isTrue);
  });

  test('an already consumed receipt cannot confirm a new usable credit',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    store.emit(billingPurchase());
    await eventually(() => service.state == CustomPetPurchaseState.purchased);
    backend.credits = 0;
    await service.refreshCustomPetCredit();
    store.emit(billingPurchase());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(service.unusedCredits, 0);
    expect(
        await service.waitForCreditConfirmation(
            timeout: const Duration(milliseconds: 5)),
        isFalse);
  });

  test('existing server credits do not require another App Store purchase',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend()..credits = 1;
    final service = await start(store, backend);
    final outcome = service.purchaseOutcomeStream.first;
    await service.purchaseCustomPetUnlock();
    expect(await outcome, CustomPetPurchaseOutcome.purchased);
    expect(service.hasUnusedCredit, isTrue);
    expect(store.purchaseStarts, 0);
  });

  test(
      'new purchase is blocked when the credit verification service is offline',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    backend.refreshError =
        const SocketException('verification service offline');
    await service.purchaseCustomPetUnlock();
    expect(store.purchaseStarts, 0);
    expect(service.state, CustomPetPurchaseState.error);
  });

  test('an unavailable Firebase login never completes a paid transaction',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend, signedIn: false);
    store.emit(billingPurchase());
    await eventually(() => service.state == CustomPetPurchaseState.error);
    expect(backend.verificationCalls, 0);
    expect(store.completed, isEmpty);
    expect(service.hasUnusedCredit, isFalse);
  });

  test('pending payment stays blocked after a balance refresh fails', () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final service = await start(store, backend);
    await service.purchaseCustomPetUnlock();
    store.emit(billingPurchase(
        status: PurchaseStatus.pending, pendingComplete: false));
    await eventually(() => service.state == CustomPetPurchaseState.pending);
    backend.refreshError =
        const SocketException('balance refresh disconnected');
    await service.refreshCustomPetCredit();
    backend.refreshError = null;
    await service.purchaseCustomPetUnlock();
    expect(store.purchaseStarts, 1);
  });

  test('an old balance response cannot overwrite a newly verified paid credit',
      () async {
    final store = FakeBillingStore();
    final backend = FakeBillingBackend();
    final refreshStarted = Completer<void>();
    final refreshGate = Completer<void>();
    var delayRefresh = false;
    SharedPreferences.setMockInitialValues({});
    final service = BillingService(
      inAppPurchase: store,
      ensureSignedIn: ({required int attempts}) async => true,
      callFunction: (name, {required data, required timeout}) async {
        final result = await backend.call(name, data: data, timeout: timeout);
        if (name == 'getCustomPetPurchaseCredit' && delayRefresh) {
          refreshStarted.complete();
          await refreshGate.future;
        }
        return result;
      },
    );
    addTearDown(() async {
      service.dispose();
      await store.dispose();
    });
    await service.initialize();
    await service.refreshCustomPetCredit();
    delayRefresh = true;
    final refresh = service.refreshCustomPetCredit();
    await refreshStarted.future;
    store.emit(billingPurchase());
    await eventually(() => service.state == CustomPetPurchaseState.purchased);
    expect(backend.credits, 1);
    refreshGate.complete();
    await refresh;
    expect(service.unusedCredits, 1);
  });
}
