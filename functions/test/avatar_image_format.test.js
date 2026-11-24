const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

// Only the remote model and Storage boundary are replaced. Run the actual
// response parsing, filename selection, upload metadata, and download URL code.
function avatarGenerator(inlineData, field = 'inlineData') {
  const uploads = [];
  const requests = [];
  const bucket = {
    name: 'local-test-bucket',
    file(path) {
      return {
        async save(bytes, options) {
          uploads.push({ path, bytes, options });
        },
      };
    },
  };
  class HttpsError extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  }
  const dependencies = {
    'firebase-functions/v2/https': {
      onCall: (_, handler) => handler,
      HttpsError,
    },
    'firebase-functions/params': { defineSecret: () => ({ value: () => 'test' }) },
    'firebase-functions/logger': { info() {}, warn() {}, error() {} },
    'firebase-admin': {
      initializeApp() {},
      firestore: () => ({}),
      storage: () => ({ bucket: () => bucket }),
    },
    axios: {
      async post(url, body) {
        requests.push({ url, body });
        return {
          data: {
            candidates: [{ content: { parts: [{ [field]: inlineData }] } }],
          },
        };
      },
    },
  };
  const context = {
    Buffer,
    exports: {},
    require: (name) => dependencies[name] || require(name),
  };
  vm.runInNewContext(
    `${readFileSync(join(__dirname, '..', 'index.js'), 'utf8')}
     exports.generateState = generateAndUploadAvatarState;`,
    context,
  );
  return {
    uploads,
    requests,
    generate(state = 'normal') {
      return context.exports.generateState({
        uid: 'test-user',
        petId: 'test-pet',
        state,
        apiKey: 'test-key',
        imageBase64: 'reference-photo',
        imageMimeType: 'image/png',
        prompt: 'test avatar',
      });
    },
  };
}

test('sends the reference photo to the stable Gemini 3 Pro image endpoint', async () => {
  const generator = avatarGenerator({ mimeType: 'image/jpeg', data: '/9j/2Q==' });
  await generator.generate();
  assert.equal(generator.requests[0].url,
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image:generateContent');
  assert.equal(generator.requests[0].body.contents[0].parts[1].inline_data.mime_type, 'image/png');
});

for (const state of ['normal', 'sleeping', 'failed']) {
  test(`${state}: JPEG output keeps JPEG metadata and a .jpg download path`, async () => {
    const bytes = Buffer.from('ffd8ffe000104a46494600010100000100010000ffd9', 'hex');
    const generator = avatarGenerator({ mimeType: 'image/jpeg', data: bytes.toString('base64') });
    const url = await generator.generate(state);
    assert.equal(generator.uploads.length, 1);
    const uploaded = generator.uploads[0];
    assert.equal(uploaded.options.metadata.contentType, 'image/jpeg');
    assert.match(uploaded.path, new RegExp(`^users/test-user/pets/test-pet/${state}-[^/]+\\.jpg$`));
    assert.deepEqual(uploaded.bytes, bytes);
    assert.equal(new URL(url).searchParams.get('alt'), 'media');
    assert.equal(decodeURIComponent(new URL(url).pathname),
      `/v0/b/local-test-bucket/o/${uploaded.path}`);
  });
}

for (const [contentType, extension, hex] of [
  ['image/png', 'png', '89504e470d0a1a0a'],
  ['image/webp', 'webp', '524946460000000057454250'],
]) {
  test(`${contentType}: snake_case response keeps its format`, async () => {
    const bytes = Buffer.from(hex, 'hex');
    const generator = avatarGenerator({ mime_type: contentType, data: bytes.toString('base64') }, 'inline_data');
    await generator.generate();
    assert.match(generator.uploads[0].path,
      new RegExp(`^users/test-user/pets/test-pet/normal-[^/]+\\.${extension}$`));
    assert.equal(generator.uploads[0].options.metadata.contentType, contentType);
    assert.deepEqual(generator.uploads[0].bytes, bytes);
  });
}

test('generating the same state twice keeps separate download paths and tokens', async () => {
  const generator = avatarGenerator({ mimeType: 'image/jpeg', data: '/9j/2Q==' });
  const first = new URL(await generator.generate());
  const second = new URL(await generator.generate());
  assert.notEqual(first.pathname, second.pathname);
  assert.equal(generator.uploads[0].options.metadata.metadata.firebaseStorageDownloadTokens,
    first.searchParams.get('token'));
  assert.equal(generator.uploads[1].options.metadata.metadata.firebaseStorageDownloadTokens,
    second.searchParams.get('token'));
});

for (const contentType of [undefined, 'image/gif']) {
  test(`does not publish output with ${contentType || 'missing'} MIME type`, async () => {
    const generator = avatarGenerator({ mimeType: contentType, data: 'R0lGODlh' });
    await assert.rejects(generator.generate(), { code: 'internal' });
    assert.equal(generator.uploads.length, 0);
  });
}
