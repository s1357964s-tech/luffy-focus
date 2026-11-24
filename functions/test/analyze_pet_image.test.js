const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const testKey = 'TEST-ONLY-KEY-NOT-FOR-LOGS';
const testImage = 'TEST-ONLY-IMAGE-NOT-FOR-LOGS';
const validPet = {
  isPet: true,
  species: 'dog',
  breed: 'beagle',
  breedConfidence: 0.9,
  visualTraits: ['Brown and white coat', 'Long floppy ears'],
};

function response(text = JSON.stringify(validPet), finishReason = 'STOP') {
  return {
    candidates: [{ finishReason, content: { parts: [{ text }] } }],
    modelVersion: 'gemini-2.5-flash',
    responseId: 'test-response-id',
    usageMetadata: { promptTokenCount: 584, candidatesTokenCount: 158, thoughtsTokenCount: 0, totalTokenCount: 742 },
  };
}

// Exercise the real callable, Gemini request configuration and JSON parsing.
// Only the remote Gemini provider and Firebase authentication/storage boundary
// are replaced; no image is read and no external request is performed.
function analyzer({ provider = () => response(), credits = 1 } = {}) {
  const requests = [];
  const logs = [];
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const dependencies = {
    'firebase-functions/v2/https': { onCall: (_, handler) => handler, HttpsError },
    'firebase-functions/params': { defineSecret: () => ({ value: () => testKey }) },
    'firebase-functions/logger': Object.fromEntries(['info', 'warn', 'error'].map((level) => [
      level, (...args) => logs.push({ level, args }),
    ])),
    'firebase-admin': {
      initializeApp() {},
      firestore: () => ({ doc: () => ({ get: async () => ({ data: () => ({ unusedCount: credits }) }) }) }),
      storage: () => ({ bucket: () => ({}) }),
    },
    axios: {
      async post(url, body) {
        requests.push({ url, body });
        return { status: 200, data: await provider(body) };
      },
    },
  };
  const context = { Buffer, exports: {}, require: (name) => dependencies[name] || require(name) };
  vm.runInNewContext(readFileSync(join(__dirname, '..', 'index.js'), 'utf8'), context);
  return {
    requests,
    logs,
    analyze() {
      return context.exports.analyzePetImage({ auth: { uid: 'test-user' }, data: {
        imageBase64: testImage,
        imageMimeType: 'image/png',
      } });
    },
  };
}

test('pet analysis reserves final JSON output tokens without spending them on default thinking', async () => {
  const app = analyzer();
  const result = await app.analyze();
  assert.equal(result.isPet, true);
  assert.equal(result.species, 'dog');
  assert.equal(result.breed, 'beagle');
  assert.equal(app.requests.length, 1);
  const config = app.requests[0].body.generationConfig;
  assert.equal(config.thinkingConfig?.thinkingBudget, 0);
  assert.ok(config.maxOutputTokens >= 1024);
  assert.equal(config.response_mime_type, 'application/json');
  assert.equal(app.requests[0].body.contents[0].parts[1].inline_data.mime_type, 'image/png');
});

test('observed MAX_TOKENS truncation is retryable and exposes only diagnostic metadata', async () => {
  // The finish reason and token counts match the public interrupted-dog
  // provider diagnostic; the incomplete JSON text is a synthetic example.
  const data = response('{"isPet": true,', 'MAX_TOKENS');
  data.usageMetadata = {
    promptTokenCount: 584, candidatesTokenCount: 9, thoughtsTokenCount: 476, totalTokenCount: 1069,
  };
  const app = analyzer({ provider: () => data });
  await assert.rejects(app.analyze(), { code: 'unavailable' });
  const diagnostic = app.logs.find((entry) => entry.args[0] === 'Gemini JSON response received')?.args[1];
  assert.equal(diagnostic?.finishReason, 'MAX_TOKENS');
  assert.equal(diagnostic?.thoughtsTokenCount, 476);
  assert.equal(diagnostic?.candidatesTokenCount, 9);
  const serializedLogs = JSON.stringify(app.logs);
  assert.equal(serializedLogs.includes(testKey), false);
  assert.equal(serializedLogs.includes(testImage), false);
  assert.equal(serializedLogs.includes('{"isPet": true,'), false);
});

test('analysis HTTP failures never log credentials, image payloads or the raw Axios error', async () => {
  const app = analyzer({ provider: () => {
    const error = new Error(`HTTP failed with ${testKey}`);
    error.code = 'ERR_BAD_REQUEST';
    error.config = { url: `https://example.test?key=${testKey}`, data: { image: testImage } };
    error.response = { status: 503, data: { privateOutput: testImage } };
    throw error;
  } });
  await assert.rejects(app.analyze(), (error) => error.code === 'internal' && !error.message.includes(testKey));
  const serializedLogs = JSON.stringify(app.logs);
  assert.equal(serializedLogs.includes(testKey), false);
  assert.equal(serializedLogs.includes(testImage), false);
  assert.equal(serializedLogs.includes('503'), true);
});

test('successful JSON analysis reports finish reason and usage without logging the model text', async () => {
  const app = analyzer();
  const result = await app.analyze();
  assert.equal(result.visualTraits.length, 2);
  const diagnostic = app.logs.find((entry) => entry.args[0] === 'Gemini JSON response received')?.args[1];
  assert.equal(diagnostic?.finishReason, 'STOP');
  assert.equal(diagnostic?.candidatesTokenCount, 158);
  assert.equal(diagnostic?.parts[0].thought, false);
  assert.equal(diagnostic?.parts[0].textLength, JSON.stringify(validPet).length);
  const serializedLogs = JSON.stringify(app.logs);
  assert.equal(serializedLogs.includes('Brown and white coat'), false);
  assert.equal(serializedLogs.includes(testImage), false);
});

test('analysis without a paid credit cannot contact the model', async () => {
  const app = analyzer({ credits: 0 });
  await assert.rejects(app.analyze(), { code: 'failed-precondition' });
  assert.equal(app.requests.length, 0);
});

test('a valid non-pet JSON result remains a non-pet result', async () => {
  const app = analyzer({ provider: () => response(JSON.stringify({
    isPet: false, species: null, breed: null, breedConfidence: 0, visualTraits: [],
  })) });
  const result = await app.analyze();
  assert.equal(result.isPet, false);
  assert.equal(result.species, null);
  assert.equal(result.visualTraits.length, 0);
});
