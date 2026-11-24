const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const productId = 'luffy.custom_pet.create.v1';
const creditPath = (uid = 'alice') => `users/${uid}/petPurchaseCredits/custom_pet_create`;
const petPath = (petId = 'pet-1') => `users/alice/pets/${petId}`;
const purchaseData = (transactionId = '1000001') => ({
  productId,
  transactionId,
  verificationData: 'test-receipt',
  verificationSource: 'app_store',
});

function validReceipt(item = {}, receipt = {}) {
  return {
    status: 0,
    environment: 'Production',
    receipt: {
      bundle_id: 'com.stevehu.luffyFocus',
      in_app: [{
        quantity: '1',
        product_id: productId,
        transaction_id: '1000001',
        original_transaction_id: '1000001',
        purchase_date_ms: '1795500000000',
        ...item,
      }],
      ...receipt,
    },
  };
}

// Keep the real receipt validation, callable handlers and credit transitions.
// Only Apple HTTP and Firestore persistence/optimistic retries are external doubles.
function iapHarness({ initial = {}, apple = () => validReceipt(), image } = {}) {
  const documents = new Map(Object.entries(initial).map(([path, data]) => [path, structuredClone(data)]));
  const versions = new Map();
  const appleRequests = [];
  const storageFiles = new Map();
  let imageRequests = 0;
  let retryMutation = null;
  let queryMutation = null;
  function restoreTimestamps(value) {
    if (!value || typeof value !== 'object') return value;
    if (Number.isFinite(value._seconds) && Number.isFinite(value._nanoseconds)) {
      return { ...value, toMillis: () => value._seconds * 1000 + value._nanoseconds / 1000000 };
    }
    for (const key of Object.keys(value)) value[key] = restoreTimestamps(value[key]);
    return value;
  }
  const snapshot = (ref) => {
    const data = structuredClone(documents.get(ref.path));
    return {
      ref,
      id: ref.path.split('/').at(-1),
      exists: documents.has(ref.path),
      data: () => restoreTimestamps(structuredClone(data)),
    };
  };
  const write = (ref, data, options = {}) => {
    const current = documents.get(ref.path) || {};
    const next = options.merge ? { ...current } : {};
    for (const [key, value] of Object.entries(data)) {
      next[key] = value?.operation === 'increment'
        ? Number(current[key] || 0) + value.amount
        : structuredClone(value);
    }
    documents.set(ref.path, next);
    versions.set(ref.path, (versions.get(ref.path) || 0) + 1);
  };
  const db = {
    collection(path) {
      return {
        where(field, operator, value) {
          assert.equal(operator, '==');
          return {
            async get() {
              const docs = [...documents]
                .filter(([documentPath, data]) => (
                  documentPath.startsWith(`${path}/`) &&
                  documentPath.slice(path.length + 1).split('/').length === 1 &&
                  data[field] === value
                ))
                .map(([documentPath]) => snapshot(db.doc(documentPath)));
              if (queryMutation) {
                const mutate = queryMutation;
                queryMutation = null;
                mutate((documentPath, data) => write(db.doc(documentPath), data, { merge: true }));
              }
              return { docs };
            },
          };
        },
      };
    },
    doc(path) {
      return {
        path,
        async get() { return snapshot(this); },
        async set(data, options) { write(this, data, options); },
      };
    },
    async runTransaction(callback) {
      for (let attempt = 0; attempt < 10; attempt += 1) {
        const reads = new Map();
        const writes = [];
        const result = await callback({
          async get(ref) {
            assert.equal(writes.length, 0, 'Firestore transactions must read before writing');
            reads.set(ref.path, versions.get(ref.path) || 0);
            return snapshot(ref);
          },
          set(ref, data, options) { writes.push(() => write(ref, data, options)); },
          delete(ref) {
            writes.push(() => {
              documents.delete(ref.path);
              versions.set(ref.path, (versions.get(ref.path) || 0) + 1);
            });
          },
        });
        if (retryMutation) {
          const mutate = retryMutation;
          retryMutation = null;
          mutate((path, data) => write(db.doc(path), data, { merge: true }));
          continue;
        }
        if ([...reads].some(([path, version]) => version !== (versions.get(path) || 0))) continue;
        for (const commit of writes) commit();
        return result;
      }
      throw new Error('Transaction contention did not settle');
    },
  };
  class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  }
  const firestore = () => db;
  firestore.FieldValue = {
    increment: (amount) => ({ operation: 'increment', amount }),
    serverTimestamp: () => ({ operation: 'timestamp' }),
  };
  const dependencies = {
    'firebase-functions/v2/https': { onCall: (_, handler) => handler, HttpsError },
    'firebase-functions/params': { defineSecret: () => ({ value: () => 'unused-test-key' }) },
    'firebase-functions/logger': { info() {}, warn() {}, error() {} },
    'firebase-admin': {
      initializeApp() {},
      firestore,
      storage: () => ({ bucket: () => ({
        name: 'local-test-bucket',
        file: (path) => ({
          async save(bytes, options) { storageFiles.set(path, { bytes, options }); },
        }),
      }) }),
    },
    axios: {
      async post(url, body) {
        if (url.startsWith('https://generativelanguage.googleapis.com/')) {
          imageRequests += 1;
          if (!image) throw new Error('Unexpected image generation');
          return { data: await image(url, body) };
        }
        assert.match(url, /^https:\/\/(buy|sandbox)\.itunes\.apple\.com\/verifyReceipt$/);
        appleRequests.push({ url, body });
        return apple(url, body, appleRequests.length);
      },
    },
  };
  const context = {
    Buffer,
    setTimeout: (callback) => setTimeout(callback, 0),
    exports: {},
    require: (name) => dependencies[name] || require(name),
  };
  const appleBoundary = dependencies.axios.post;
  dependencies.axios.post = async (...args) => {
    const data = await appleBoundary(...args);
    return data?.data === undefined ? { status: 200, data } : data;
  };
  vm.runInNewContext(
    `${readFileSync(join(__dirname, '..', 'index.js'), 'utf8')}
     exports.reserveCredit = reserveCustomPetCredit;
     exports.releaseCredit = releaseCustomPetCreditReservation;`,
    context,
  );
  return {
    appleRequests,
    storageFiles,
    imageRequests: () => imageRequests,
    documents,
    get: (path) => documents.get(path),
    retryNextTransaction: (mutation) => { retryMutation = mutation; },
    afterNextQuery: (mutation) => { queryMutation = mutation; },
    reserve: (petId = 'pet-1') => context.exports.reserveCredit('alice', petId),
    release: (petId = 'pet-1', options) => context.exports.releaseCredit('alice', petId, options),
    call(name, data, uid = 'alice') {
      return context.exports[name]({ auth: uid ? { uid } : null, data });
    },
    verify(uid = 'alice', transactionId = '1000001') {
      return this.call('verifyCustomPetPurchase', purchaseData(transactionId), uid);
    },
    generate(petId = 'pet-1') {
      return this.call('generatePetAvatar', {
        petId,
        species: 'cat',
        imageBase64: 'dGVzdA==',
        imageMimeType: 'image/jpeg',
        originalImagePath: `users/alice/pets/${petId}/original.jpg`,
      });
    },
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

const imageResponse = () => ({
  candidates: [{ content: { parts: [{ inlineData: { mimeType: 'image/jpeg', data: '/9j/2Q==' } }] } }],
});

test('one transaction cannot grant credit to a second uid', async () => {
  const app = iapHarness();
  await app.verify();
  await assert.rejects(app.verify('bob'), { code: 'permission-denied' });
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath('bob')), undefined);
});

test('concurrent claims by different uids deliver exactly one credit', async () => {
  const app = iapHarness();
  const results = await Promise.allSettled([app.verify(), app.verify('bob')]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal([app.get(creditPath()), app.get(creditPath('bob'))]
    .reduce((total, credit) => total + (credit?.unusedCount || 0), 0), 1);
});

for (const cancellation of [
  { cancellation_date_ms: '1795501000000' },
  { cancellation_date: '2026-11-24 01:00:00 Etc/GMT' },
  { cancellation_reason: '0' },
]) {
  test(`refunded transaction (${Object.keys(cancellation)[0]}) grants no credit`, async () => {
    const app = iapHarness({ apple: () => validReceipt(cancellation) });
    await assert.rejects(app.verify(), { code: 'failed-precondition' });
    assert.equal(app.documents.size, 0);
  });
}

test('an original transaction id cannot substitute for a different purchase id', async () => {
  const app = iapHarness({ apple: () => validReceipt({ transaction_id: '1000002' }) });
  await assert.rejects(app.verify(), { code: 'failed-precondition' });
  assert.equal(app.documents.size, 0);
});

test('duplicate Apple entries cannot hide a cancellation in latest receipt info', async () => {
  const receipt = validReceipt();
  receipt.latest_receipt_info = [{ ...receipt.receipt.in_app[0], cancellation_date_ms: '1795501000000' }];
  const app = iapHarness({ apple: () => receipt });
  await assert.rejects(app.verify(), { code: 'failed-precondition' });
  assert.equal(app.documents.size, 0);
});

test('a retried reservation reports only the committed attempt ownership', async () => {
  const app = iapHarness({ initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } } });
  app.retryNextTransaction((set) => {
    set(creditPath(), { unusedCount: 0, reservedCount: 1 });
    set(petPath(), { purchaseStatus: 'reserved' });
  });
  assert.equal(await app.reserve(), false);
  assert.equal(app.get(creditPath()).reservedCount, 1);
});

test('saving an unfinished reservation does not consume its credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: { purchaseStatus: 'reserved' },
  } });
  await assert.rejects(app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Mochi' }),
    { code: 'failed-precondition' });
  assert.equal(app.get(creditPath()).reservedCount, 1);
  assert.equal(app.get(creditPath()).consumedCount, undefined);
});

test('temporary Apple receipt failures are retried before granting a credit', async () => {
  const app = iapHarness({ apple: (_, __, attempt) => attempt === 1 ? { status: 21005 } : validReceipt() });
  await app.verify();
  assert.equal(app.appleRequests.length, 2);
  assert.equal(app.get(creditPath()).unusedCount, 1);
});

test('an exhausted temporary Apple failure remains retryable by the client', async () => {
  const app = iapHarness({ apple: () => ({ status: 21009 }) });
  await assert.rejects(app.verify(), { code: 'unavailable' });
  assert.equal(app.appleRequests.length, 3);
  assert.equal(app.documents.size, 0);
});

test('an HTTP failure cannot grant credit even if its body claims a valid receipt', async () => {
  const app = iapHarness({ apple: () => ({ status: 503, data: validReceipt() }) });
  await assert.rejects(app.verify(), { code: 'unavailable' });
  assert.equal(app.documents.size, 0);
});

test('a late generation response cannot recreate a released draft', async () => {
  const images = deferred();
  const started = deferred();
  const app = iapHarness({
    initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } },
    image: () => { started.resolve(); return images.promise; },
  });
  const generating = app.generate();
  await started.promise;
  await app.call('releaseCustomPetPurchaseCredit', { petId: 'pet-1' });
  images.resolve(imageResponse());
  await assert.rejects(generating, { code: 'failed-precondition' });
  assert.equal(app.get(petPath()), undefined);
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).reservedCount, 0);
});

test('duplicate generation cannot run twice on one reservation', async () => {
  const images = deferred();
  const started = deferred();
  const app = iapHarness({
    initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } },
    image: () => { started.resolve(); return images.promise; },
  });
  const generating = app.generate();
  await started.promise;
  const duplicate = app.generate();
  images.resolve(imageResponse());
  await assert.rejects(duplicate, { code: 'aborted' });
  await generating;
  assert.equal(app.imageRequests(), 3);
  assert.equal(app.get(creditPath()).reservedCount, 1);
});

test('retrying an already generated draft returns its images without another charge or image call', async () => {
  const app = iapHarness({
    initial: {
      [creditPath()]: { unusedCount: 0, reservedCount: 1 },
      [petPath()]: {
        purchaseStatus: 'reserved',
        status: 'generated',
        normalImageUrl: 'https://example.test/normal.jpg',
        sleepingImageUrl: 'https://example.test/sleeping.jpg',
        failedImageUrl: 'https://example.test/failed.jpg',
        avatarStatesVersion: 3,
        stateImagesStatus: 'ready',
      },
    },
  });
  const result = await app.generate();
  assert.equal(result.normalImageUrl, 'https://example.test/normal.jpg');
  assert.equal(result.sleepingImageUrl, 'https://example.test/sleeping.jpg');
  assert.equal(app.imageRequests(), 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
});

test('a stale failed generation cannot release a newer reservation for the same pet', async () => {
  const firstImages = deferred();
  const secondImages = deferred();
  const firstStarted = deferred();
  const secondStarted = deferred();
  let calls = 0;
  const app = iapHarness({
    initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } },
    image: () => {
      calls += 1;
      if (calls <= 3) { firstStarted.resolve(); return firstImages.promise; }
      secondStarted.resolve();
      return secondImages.promise;
    },
  });
  const first = app.generate();
  await firstStarted.promise;
  await app.call('releaseCustomPetPurchaseCredit', { petId: 'pet-1' });
  const second = app.generate();
  await secondStarted.promise;
  firstImages.reject(new Error('Simulated model network failure'));
  await assert.rejects(first, { code: 'internal' });
  assert.equal(app.get(creditPath()).unusedCount, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
  secondImages.resolve(imageResponse());
  await second;
  assert.equal(app.get(petPath()).status, 'generated');
});

test('sandbox receipts retry against sandbox only after production returns 21007', async () => {
  const app = iapHarness({ apple: (_, __, attempt) => attempt === 1 ? { status: 21007 } : validReceipt() });
  const result = await app.verify();
  assert.equal(result.environment, 'Sandbox');
  assert.deepEqual(app.appleRequests.map((request) => request.url), [
    'https://buy.itunes.apple.com/verifyReceipt',
    'https://sandbox.itunes.apple.com/verifyReceipt',
  ]);
  assert.equal(app.get(creditPath()).unusedCount, 1);
});

test('a disconnected Apple call retries without minting a second credit', async () => {
  const app = iapHarness({ apple: (_, __, attempt) => {
    if (attempt === 1) throw new Error('ECONNRESET');
    return validReceipt();
  } });
  await app.verify();
  assert.equal(app.appleRequests.length, 2);
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).purchasedCount, 1);
});

test('verification can be resubmitted after a completely disconnected first attempt', async () => {
  let disconnected = true;
  const app = iapHarness({ apple: () => {
    if (disconnected) throw new Error('ECONNRESET');
    return validReceipt();
  } });
  await assert.rejects(app.verify(), { code: 'unavailable' });
  assert.equal(app.documents.size, 0);
  disconnected = false;
  await app.verify();
  await app.verify();
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).purchasedCount, 1);
});

test('simultaneous duplicate callbacks for the same uid mint a single credit', async () => {
  const app = iapHarness();
  await Promise.all([app.verify(), app.verify(), app.verify()]);
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).purchasedCount, 1);
});

test('retrying an already spent purchase does not replenish the credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, purchasedCount: 1, consumedCount: 1 },
    'users/alice/iapTransactions/1000001': { productId, transactionId: '1000001', credited: true },
  } });
  const result = await app.verify();
  assert.equal(result.unusedCredits, 0);
  assert.equal(app.get(creditPath()).unusedCount, 0);
  assert.equal(app.get(creditPath()).purchasedCount, 1);
  await assert.rejects(app.verify('bob'), { code: 'permission-denied' });
});

test('a global owner record prevents redelivery even if the per-user ledger is missing', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, purchasedCount: 1, consumedCount: 1 },
    'appStoreTransactions/Production_1000001': { uid: 'alice', productId, transactionId: '1000001' },
  } });
  const result = await app.verify();
  assert.equal(result.unusedCredits, 0);
  assert.equal(app.get(creditPath()).purchasedCount, 1);
});

for (const createdAt of ['2026-06-07T10:02:50.445Z', undefined]) {
  test(`legacy owner registration preserves ${createdAt ? 'the original timestamp' : 'a missing historical timestamp'}`, async () => {
    const app = iapHarness({ initial: {
      [creditPath()]: { unusedCount: 0, purchasedCount: 1, consumedCount: 1 },
      'users/alice/iapTransactions/1000001': {
        productId,
        transactionId: '1000001',
        credited: true,
        ...(createdAt ? { createdAt } : {}),
      },
    } });
    await app.verify();
    assert.equal(app.get('appStoreTransactions/Production_1000001').createdAt, createdAt);
    assert.equal(app.get(creditPath()).purchasedCount, 1);
  });
}

for (const [name, response] of [
  ['bundle', validReceipt({}, { bundle_id: 'com.other.app' })],
  ['product', validReceipt({ product_id: 'other.product' })],
  ['transaction', validReceipt({ transaction_id: '9999999', original_transaction_id: '9999999' })],
  ['invalid receipt', { status: 21003 }],
]) {
  test(`an Apple ${name} mismatch grants no credit`, async () => {
    const app = iapHarness({ apple: () => response });
    await assert.rejects(app.verify(), { code: 'failed-precondition' });
    assert.equal(app.documents.size, 0);
  });
}

test('unauthenticated verification never contacts Apple or modifies credits', async () => {
  const app = iapHarness();
  await assert.rejects(app.call('verifyCustomPetPurchase', purchaseData(), null), { code: 'unauthenticated' });
  assert.equal(app.appleRequests.length, 0);
  assert.equal(app.documents.size, 0);
});

for (const data of [
  { ...purchaseData(), productId: 'other.product' },
  { ...purchaseData(), verificationSource: 'google_play' },
  { ...purchaseData(), transactionId: '' },
  { ...purchaseData(), verificationData: '' },
]) {
  test(`invalid purchase input (${JSON.stringify(data)}) never grants a credit`, async () => {
    const app = iapHarness();
    await assert.rejects(app.call('verifyCustomPetPurchase', data), { code: 'invalid-argument' });
    assert.equal(app.appleRequests.length, 0);
    assert.equal(app.documents.size, 0);
  });
}

test('repeated reservations and releases preserve exactly one available credit', async () => {
  const app = iapHarness({ initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } } });
  assert.equal(await app.reserve(), true);
  assert.equal(await app.reserve(), false);
  assert.equal(app.get(creditPath()).unusedCount, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
  await app.release('pet-1', { deletePet: true });
  await app.release('pet-1', { deletePet: true });
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).reservedCount, 0);
});

test('two pets cannot reserve the same last credit', async () => {
  const app = iapHarness({ initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } } });
  const results = await Promise.allSettled([app.reserve('pet-1'), app.reserve('pet-2')]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(app.get(creditPath()).unusedCount, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
});

function generatedDraft() {
  return {
    purchaseStatus: 'reserved',
    status: 'generated',
    normalImageUrl: 'https://example.test/normal.jpg',
    sleepingImageUrl: 'https://example.test/sleeping.jpg',
    failedImageUrl: 'https://example.test/failed.jpg',
  };
}

test('repeated saves and a later release consume exactly one credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: generatedDraft(),
  } });
  const first = await app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Mochi' });
  const second = await app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Other' });
  await app.release('pet-1', { deletePet: true });
  assert.equal(first.name, 'Mochi');
  assert.equal(second.name, 'Mochi');
  assert.equal(app.get(creditPath()).reservedCount, 0);
  assert.equal(app.get(creditPath()).consumedCount, 1);
  assert.equal(app.get(creditPath()).unusedCount, 0);
  assert.equal(app.get(petPath()).purchaseStatus, 'consumed');
});

test('concurrent save callbacks consume exactly one reserved credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: generatedDraft(),
  } });
  await Promise.all([
    app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Mochi' }),
    app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Mochi' }),
  ]);
  assert.equal(app.get(creditPath()).reservedCount, 0);
  assert.equal(app.get(creditPath()).consumedCount, 1);
});

test('concurrent save and release cannot both consume and refund a credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: generatedDraft(),
  } });
  await Promise.allSettled([
    app.call('saveGeneratedPetName', { petId: 'pet-1', name: 'Mochi' }),
    app.release('pet-1', { deletePet: true }),
  ]);
  const credit = app.get(creditPath());
  assert.equal(credit.reservedCount, 0);
  assert.equal((credit.unusedCount || 0) + (credit.consumedCount || 0), 1);
});

test('a consumed pet cannot reserve another credit', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 1, reservedCount: 0, consumedCount: 1 },
    [petPath()]: { purchaseStatus: 'consumed', status: 'ready', name: 'Mochi' },
  } });
  await assert.rejects(app.reserve(), { code: 'failed-precondition' });
  assert.equal(app.get(creditPath()).unusedCount, 1);
});

test('new generation reservations receive a lease longer than the 300-second function timeout', async () => {
  const app = iapHarness({ initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } } });
  const before = Date.now();
  await app.reserve();
  const pet = app.get(petPath());
  assert.equal(pet.status, 'generating');
  assert.equal(typeof pet.purchaseReservationId, 'string');
  assert.ok(pet.purchaseReservationExpiresAtMs >= before + 330000);
  assert.ok(pet.purchaseReservationExpiresAtMs <= Date.now() + 330000);
});

test('refresh refunds a hard-timeout reservation once across repeated and concurrent refreshes', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: {
      purchaseStatus: 'reserved',
      status: 'generating',
      purchaseReservationId: 'expired-reservation',
      purchaseReservationExpiresAtMs: Date.now() - 1000,
    },
  } });
  await Promise.all([
    app.call('getCustomPetPurchaseCredit', {}),
    app.call('getCustomPetPurchaseCredit', {}),
  ]);
  const result = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(result.unusedCredits, 1);
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).reservedCount, 0);
  assert.equal(app.get(petPath()), undefined);
});

for (const [name, pet] of [
  ['active generation', {
    purchaseStatus: 'reserved',
    status: 'generating',
    purchaseReservationId: 'active',
    purchaseReservationExpiresAtMs: Date.now() + 330000,
  }],
  ['generated draft waiting for a name', {
    ...generatedDraft(),
    purchaseReservationId: 'generated',
    purchaseReservationExpiresAtMs: Date.now() - 3600000,
  }],
  ['legacy draft without a recorded reservation timestamp', { purchaseStatus: 'reserved' }],
]) {
  test(`refresh preserves ${name}`, async () => {
    const app = iapHarness({ initial: {
      [creditPath()]: { unusedCount: 0, reservedCount: 1 },
      [petPath()]: pet,
    } });
    const result = await app.call('getCustomPetPurchaseCredit', {});
    assert.equal(result.unusedCredits, 0);
    assert.equal(app.get(creditPath()).reservedCount, 1);
    assert.equal(app.get(petPath()).purchaseStatus, 'reserved');
  });
}

test('refresh can recover a legacy generation only from its existing Firestore timestamp', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: {
      purchaseStatus: 'reserved',
      purchaseReservedAt: { _seconds: Math.floor((Date.now() - 3600000) / 1000), _nanoseconds: 0 },
    },
  } });
  const result = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(result.unusedCredits, 1);
  assert.equal(app.get(creditPath()).reservedCount, 0);
  assert.equal(app.get(petPath()), undefined);
});

test('stale expiry candidates cannot release a newer reservation id', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: {
      purchaseStatus: 'reserved',
      status: 'generating',
      purchaseReservationId: 'old-reservation',
      purchaseReservationExpiresAtMs: Date.now() - 1000,
    },
  } });
  app.afterNextQuery((set) => set(petPath(), { purchaseReservationId: 'new-reservation' }));
  const result = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(result.unusedCredits, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
  assert.equal(app.get(petPath()).purchaseReservationId, 'new-reservation');
});

test('a legacy candidate without an id cannot release a newly identified reservation', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: {
      purchaseStatus: 'reserved',
      purchaseReservedAt: { _seconds: Math.floor((Date.now() - 3600000) / 1000), _nanoseconds: 0 },
    },
  } });
  app.afterNextQuery((set) => set(petPath(), { purchaseReservationId: 'new-reservation' }));
  const result = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(result.unusedCredits, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
  assert.equal(app.get(petPath()).purchaseReservationId, 'new-reservation');
});

test('expiry recovery rechecks generated status inside the transaction', async () => {
  const app = iapHarness({ initial: {
    [creditPath()]: { unusedCount: 0, reservedCount: 1 },
    [petPath()]: {
      purchaseStatus: 'reserved',
      status: 'generating',
      purchaseReservationId: 'expired-reservation',
      purchaseReservationExpiresAtMs: Date.now() - 1000,
    },
  } });
  app.afterNextQuery((set) => set(petPath(), generatedDraft()));
  const result = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(result.unusedCredits, 0);
  assert.equal(app.get(creditPath()).reservedCount, 1);
  assert.equal(app.get(petPath()).status, 'generated');
});

test('a late generation response cannot revive a reservation recovered by credit refresh', async () => {
  const images = deferred();
  const started = deferred();
  const app = iapHarness({
    initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } },
    image: () => { started.resolve(); return images.promise; },
  });
  const generating = app.generate();
  await started.promise;
  app.get(petPath()).purchaseReservationExpiresAtMs = Date.now() - 1000;
  const refreshed = await app.call('getCustomPetPurchaseCredit', {});
  assert.equal(refreshed.unusedCredits, 1);
  images.resolve(imageResponse());
  await assert.rejects(generating, { code: 'failed-precondition' });
  assert.equal(app.get(petPath()), undefined);
  assert.equal(app.get(creditPath()).unusedCount, 1);
  assert.equal(app.get(creditPath()).reservedCount, 0);
});

test('stale image uploads cannot invalidate the newer committed draft download URLs', async () => {
  const firstImages = deferred();
  const secondImages = deferred();
  const firstStarted = deferred();
  const secondStarted = deferred();
  let calls = 0;
  const app = iapHarness({
    initial: { [creditPath()]: { unusedCount: 1, reservedCount: 0 } },
    image: () => {
      calls += 1;
      if (calls <= 3) { firstStarted.resolve(); return firstImages.promise; }
      secondStarted.resolve();
      return secondImages.promise;
    },
  });
  const first = app.generate();
  await firstStarted.promise;
  await app.call('releaseCustomPetPurchaseCredit', { petId: 'pet-1' });
  const second = app.generate();
  await secondStarted.promise;
  secondImages.resolve(imageResponse());
  await second;
  const committed = { ...app.get(petPath()) };
  firstImages.resolve(imageResponse());
  await assert.rejects(first, { code: 'failed-precondition' });
  for (const field of ['normalImageUrl', 'sleepingImageUrl', 'failedImageUrl']) {
    const url = new URL(committed[field]);
    const path = decodeURIComponent(url.pathname.split('/o/')[1]);
    const file = app.storageFiles.get(path);
    assert.equal(file.options.metadata.metadata.firebaseStorageDownloadTokens, url.searchParams.get('token'));
    assert.equal(app.get(petPath())[field], committed[field]);
  }
  assert.equal(app.get(creditPath()).reservedCount, 1);
  assert.equal(app.get(creditPath()).unusedCount, 0);
});
