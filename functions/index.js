const { randomUUID } = require('crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

const db = admin.firestore();
const bucket = admin.storage().bucket();
const geminiApiKey = defineSecret('GEMINI_API_KEY');
const GEMINI_TEXT_MODEL = 'gemini-2.5-flash';
const GEMINI_IMAGE_MODEL = 'gemini-3-pro-image-preview';
const AVATAR_BACKGROUND_COLOR = '#FDF6E3';
const CUSTOM_PET_PRODUCT_ID = 'luffy.custom_pet.create.v1';
const CUSTOM_PET_CREDIT_DOC_ID = 'custom_pet_create';
const IOS_BUNDLE_ID = 'com.stevehu.luffyFocus';
const APPLE_VERIFY_RECEIPT_PRODUCTION = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_VERIFY_RECEIPT_SANDBOX = 'https://sandbox.itunes.apple.com/verifyReceipt';
const AVATAR_STATES_VERSION = 3;

const BREED_TRAITS = {
  dog: {
    beagle: 'Beagle traits: compact hound body, broad forehead, large floppy ears, round expressive eyes, short smooth coat, often tricolor with white muzzle, white chest, tan face, black saddle.',
    schnauzer: 'Schnauzer traits: rectangular muzzle, strong eyebrows, visible beard/mustache, wiry coat, V-shaped folded ears or cropped-looking upright ears, compact square body, common salt-and-pepper or black/silver coloring.',
    'shiba inu': 'Shiba Inu traits: fox-like face, triangular upright ears, curled tail, compact body, dense double coat, cream cheeks/chest, clear sesame/red/black-tan markings.',
    'black shiba': 'Black Shiba Inu traits: fox-like face, triangular upright ears, curled tail, black-and-tan coat, cream eyebrows/cheeks/chest, tan points on legs and muzzle.',
    corgi: 'Corgi traits: short legs, long body, large upright ears, fox-like face, fluffy chest, round rump, common red/white, sable/white, or tricolor pattern.',
    poodle: 'Poodle traits: curly dense coat, rounded fluffy head, long ears covered with curls, slim muzzle, elegant small body; preserve exact coat color from photo.',
    bichon: 'Bichon Frise traits: round cotton-like white curly coat, black button nose, dark round eyes, fluffy rounded head, small compact body.',
    pomeranian: 'Pomeranian traits: tiny spitz body, fox-like face, upright ears, huge fluffy mane, plume tail curling over back, dense coat.',
    'golden retriever': 'Golden Retriever traits: friendly broad face, floppy ears, medium-long golden feathered coat, large athletic body, warm eyes.',
    labrador: 'Labrador traits: broad head, short dense coat, floppy ears, sturdy body, otter-like tail, friendly expression.',
    husky: 'Husky traits: wolf-like mask, upright triangular ears, almond eyes, thick double coat, strong facial markings, fluffy tail.',
    'border collie': 'Border Collie traits: intelligent herding-dog face, semi-erect ears, athletic body, medium coat, often black-and-white blaze and chest.',
    dachshund: 'Dachshund traits: very long body, short legs, long muzzle, floppy ears, smooth/long/wire coat depending on photo.',
    'french bulldog': 'French Bulldog traits: compact muscular body, flat short muzzle, large bat ears, round forehead, short coat.',
    chihuahua: 'Chihuahua traits: tiny body, apple-shaped head or deer head, large eyes, large upright ears, delicate muzzle.',
    maltese: 'Maltese traits: small toy dog, silky long white coat, dark eyes and nose, drop ears hidden by fur.',
    samoyed: 'Samoyed traits: fluffy pure white double coat, smiling spitz face, upright ears, curled plume tail.',
    pug: 'Pug traits: round wrinkled face, short flat muzzle, curled tail, compact body, expressive dark eyes.',
  },
  cat: {
    persian: 'Persian cat traits: very long dense fluffy coat, round head, short nose/flat face, large round eyes, small rounded ears, thick neck ruff.',
    ragdoll: 'Ragdoll traits: large long-haired body, blue oval eyes, soft semi-long coat, colorpoint pattern, darker ears/face/tail, fluffy tail.',
    'british shorthair': 'British Shorthair traits: round face, chubby cheeks, dense plush short coat, small rounded ears, large round eyes, sturdy body.',
    'british longhair': 'British Longhair traits: round face and cheeks, dense long plush coat, small rounded ears, large round eyes, fluffy tail.',
    'american shorthair': 'American Shorthair traits: strong medium body, round face, short dense coat, clear tabby or bicolor pattern, alert eyes.',
    'maine coon': 'Maine Coon traits: very large long body, long shaggy coat, ear tufts, square muzzle, majestic neck ruff, long fluffy tail.',
    siamese: 'Siamese traits: slender body, wedge-shaped face, large ears, blue almond eyes, short coat with dark points on face/ears/paws/tail.',
    'scottish fold': 'Scottish Fold traits: folded small ears, round owl-like face, large round eyes, compact body, plush coat.',
    bengal: 'Bengal traits: sleek muscular body, short glossy coat, leopard-like rosettes or marbling, strong contrast markings.',
    'russian blue': 'Russian Blue traits: short dense blue-gray coat, green eyes, elegant slender body, wedge-like face, large ears.',
    sphynx: 'Sphynx traits: hairless or very fine fuzz, wrinkled skin, huge ears, angular face, visible body shape.',
    munchkin: 'Munchkin traits: short legs, normal-sized body, round expressive face, preserve exact coat pattern from photo.',
    'norwegian forest': 'Norwegian Forest Cat traits: large long-haired body, triangular face, thick waterproof coat, neck ruff, tufted ears, bushy tail.',
    'domestic longhair': 'Domestic longhair traits: mixed-breed long fluffy coat; preserve exact fur length, colors, face markings, eye color, ear shape, and tail fluff from photo.',
    'domestic shorthair': 'Domestic shorthair traits: mixed-breed short coat; preserve exact coat colors, tabby stripes, patches, face markings, eye color, and body shape from photo.',
    'orange tabby': 'Orange tabby traits: orange/ginger coat, visible tabby stripes, M marking on forehead, warm amber or green eyes, striped tail.',
    calico: 'Calico traits: tri-color patches of white, orange, and black/gray, asymmetrical face/body patches; preserve exact patch placement.',
    tuxedo: 'Tuxedo cat traits: black-and-white pattern, white chest/belly/paws, dark back/head, possible white muzzle blaze.',
  },
};

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

function requireString(value, fieldName) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${fieldName} is required.`);
  }
  return value.trim();
}

function optionalString(value, maxLength = 240) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, maxLength);
}

function optionalStringArray(value, maxItems = 12, maxLength = 40) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim().slice(0, maxLength))
    .filter((item) => item.length > 0)
    .slice(0, maxItems);
}

function optionalTraits(value, maxItems = 10, maxLength = 120) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => typeof item === 'string')
    .map((item) => item.trim().slice(0, maxLength))
    .filter((item) => item.length > 0)
    .slice(0, maxItems);
}

function normalizeBreed(value) {
  if (typeof value !== 'string') return '';
  return value.trim().toLowerCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ').slice(0, 80);
}

function breedTraitText(species, breed) {
  const normalizedSpecies = normalizeBreed(species);
  const normalizedBreed = normalizeBreed(breed);
  const traitsBySpecies = BREED_TRAITS[normalizedSpecies] || {};
  if (!normalizedBreed) return '';

  if (traitsBySpecies[normalizedBreed]) return traitsBySpecies[normalizedBreed];

  for (const [key, traits] of Object.entries(traitsBySpecies)) {
    if (normalizedBreed.includes(key) || key.includes(normalizedBreed)) {
      return traits;
    }
  }

  return '';
}

function featureNoteIdentityLock(featureNote) {
  if (!featureNote) return '';

  return `USER-PROVIDED IDENTITY MARK - ABSOLUTE REQUIREMENT:
The user wrote this extra identifying detail: "${featureNote}".
This note may be written in Chinese or another language. Translate its meaning internally and follow it literally.
Treat this note as a required visible identity feature, not as optional decoration.
If the note describes a location on the face or body, preserve that exact location and side as much as possible.
If the note describes a color, use that exact color family and make it visibly distinct from nearby fur.
For mouth, muzzle, cheek, nose, eye, ear, forehead, paw, tail, or collar details, draw the detail clearly enough to recognize at avatar size.
Do not move a face marking onto the chest, belly, forehead, or paws.
Do not omit the detail because it is subtle in the reference photo.
Before returning the image, verify that the user's required identity mark is visible in the final cartoon.`;
}

function normalizeImageMimeType(value) {
  const mimeType = typeof value === 'string' ? value.trim().toLowerCase() : 'image/jpeg';
  if (['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) {
    return mimeType;
  }
  throw new HttpsError('invalid-argument', 'Unsupported image format. Please upload a JPEG, PNG, or WebP image.');
}

function parseGeminiJson(text) {
  try {
    return JSON.parse(text);
  } catch (_) {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new HttpsError('internal', 'Gemini did not return JSON.');
    }
    return JSON.parse(match[0]);
  }
}

async function callGemini({ apiKey, parts, json = false, generationConfig = {} }) {
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'GEMINI_API_KEY is not configured.');
  }

  const response = await axios.post(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TEXT_MODEL}:generateContent?key=${apiKey}`,
    {
      contents: [{ parts }],
      ...(json
        ? { generationConfig: { ...generationConfig, response_mime_type: 'application/json' } }
        : (Object.keys(generationConfig).length > 0 ? { generationConfig } : {})),
    },
  );

  const text = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    throw new HttpsError('internal', 'Gemini returned an empty response.');
  }
  return text;
}

async function callGeminiImage({ apiKey, imageBase64, imageMimeType, prompt }) {
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'GEMINI_API_KEY is not configured.');
  }

  const response = await axios.post(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent`,
    {
      contents: [
        {
          parts: [
            { text: prompt },
            { inline_data: { mime_type: imageMimeType, data: imageBase64 } },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ['Image'],
      },
    },
    {
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
    },
  );

  const parts = response.data?.candidates?.[0]?.content?.parts || [];
  for (const part of parts) {
    const inlineData = part.inlineData || part.inline_data;
    if (inlineData?.data) {
      return Buffer.from(inlineData.data, 'base64');
    }
  }

  throw new HttpsError('internal', 'Gemini did not return an image.');
}

async function uploadPublicImage(path, bytes, contentType = 'image/png') {
  const token = randomUUID();
  const file = bucket.file(path);

  await file.save(bytes, {
    resumable: false,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });

  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

async function uploadPrivateImage(path, bytes, contentType) {
  const file = bucket.file(path);
  await file.save(bytes, {
    resumable: false,
    metadata: {
      contentType,
    },
  });
  return path;
}

async function originalImageInputFromPath({ uid, petId, originalImagePath }) {
  if (!originalImagePath ||
      !originalImagePath.startsWith(`users/${uid}/pets/${petId}/original.`)) {
    throw new HttpsError('failed-precondition', 'Original pet image is missing.');
  }

  const file = bucket.file(originalImagePath);
  const [[bytes], [metadata]] = await Promise.all([
    file.download(),
    file.getMetadata(),
  ]);
  const imageMimeType = normalizeImageMimeType(metadata.contentType);
  return {
    imageBase64: bytes.toString('base64'),
    imageMimeType,
  };
}

async function imageInputFromPublicUrl(imageUrl) {
  if (!imageUrl || !/^https:\/\/firebasestorage\.googleapis\.com\//.test(imageUrl)) {
    throw new HttpsError('failed-precondition', 'Fallback pet image is missing.');
  }

  const response = await axios.get(imageUrl, {
    responseType: 'arraybuffer',
    timeout: 30000,
    validateStatus: (status) => status >= 200 && status < 300,
  });
  const contentType = String(response.headers?.['content-type'] || 'image/png')
    .split(';')[0]
    .trim()
    .toLowerCase();
  return {
    imageBase64: Buffer.from(response.data).toString('base64'),
    imageMimeType: normalizeImageMimeType(contentType),
  };
}

async function repairImageInputForPet({
  uid,
  petId,
  originalImagePath,
  normalImageUrl,
}) {
  try {
    return await originalImageInputFromPath({ uid, petId, originalImagePath });
  } catch (error) {
    logger.warn('Original pet image unavailable for state repair; falling back to normal avatar', {
      uid,
      petId,
      originalImagePath,
      errorMessage: error?.message,
    });
    return imageInputFromPublicUrl(normalImageUrl);
  }
}

function originalImageExtension(imageMimeType) {
  switch (imageMimeType) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    default:
      return 'jpg';
  }
}

async function unusedCustomPetCredits(uid) {
  const snapshot = await db.doc(`users/${uid}/petPurchaseCredits/${CUSTOM_PET_CREDIT_DOC_ID}`).get();
  const value = snapshot.data()?.unusedCount;
  return Number.isFinite(value) ? value : 0;
}

async function assertHasCustomPetCredit(uid) {
  const credits = await unusedCustomPetCredits(uid);
  if (credits <= 0) {
    throw new HttpsError('failed-precondition', 'Please purchase a custom pet creation credit before uploading.');
  }
}

async function reserveCustomPetCredit(uid, petId) {
  const petRef = db.doc(`users/${uid}/pets/${petId}`);
  const creditRef = db.doc(`users/${uid}/petPurchaseCredits/${CUSTOM_PET_CREDIT_DOC_ID}`);
  let newlyReserved = false;

  await db.runTransaction(async (transaction) => {
    const [petSnapshot, creditSnapshot] = await Promise.all([
      transaction.get(petRef),
      transaction.get(creditRef),
    ]);
    const pet = petSnapshot.data() || {};
    if (pet.purchaseStatus === 'reserved') {
      return;
    }
    if (pet.purchaseStatus === 'consumed') {
      throw new HttpsError('failed-precondition', 'This pet creation credit has already been consumed.');
    }

    const unusedCount = Number(creditSnapshot.data()?.unusedCount || 0);
    if (unusedCount <= 0) {
      throw new HttpsError('failed-precondition', 'Please purchase a custom pet creation credit before generating.');
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(creditRef, {
      unusedCount: unusedCount - 1,
      reservedCount: admin.firestore.FieldValue.increment(1),
      updatedAt: now,
    }, { merge: true });
    transaction.set(petRef, {
      purchaseStatus: 'reserved',
      purchaseReservedAt: now,
      updatedAt: now,
    }, { merge: true });
    newlyReserved = true;
  });

  return newlyReserved;
}

async function releaseCustomPetCreditReservation(uid, petId, { deletePet = false } = {}) {
  const petRef = db.doc(`users/${uid}/pets/${petId}`);
  const creditRef = db.doc(`users/${uid}/petPurchaseCredits/${CUSTOM_PET_CREDIT_DOC_ID}`);

  await db.runTransaction(async (transaction) => {
    const petSnapshot = await transaction.get(petRef);
    const pet = petSnapshot.data() || {};
    if (!petSnapshot.exists || pet.purchaseStatus !== 'reserved') {
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(creditRef, {
      unusedCount: admin.firestore.FieldValue.increment(1),
      reservedCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: now,
    }, { merge: true });
    if (deletePet) {
      transaction.delete(petRef);
    } else {
      transaction.set(petRef, {
        purchaseStatus: 'released',
        updatedAt: now,
      }, { merge: true });
    }
  });
}

function receiptItems(receipt) {
  return [
    ...(Array.isArray(receipt?.receipt?.in_app) ? receipt.receipt.in_app : []),
    ...(Array.isArray(receipt?.latest_receipt_info) ? receipt.latest_receipt_info : []),
  ];
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function postAppleReceipt(url, payload) {
  let lastError = null;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await axios.post(url, payload, {
        timeout: 20000,
        validateStatus: () => true,
      });
    } catch (error) {
      lastError = error;
      logger.warn('Apple receipt verification request failed', {
        url,
        attempt,
        code: error.code,
        message: error.message,
      });
      if (attempt < 3) {
        await wait(600 * attempt);
      }
    }
  }

  throw new HttpsError(
    'unavailable',
    'Apple receipt verification is temporarily unavailable. Please retry.',
    {
      code: lastError?.code || '',
      message: lastError?.message || '',
    },
  );
}

async function verifyAppleReceipt({ verificationData, transactionId, productId }) {
  const payload = {
    'receipt-data': verificationData,
    'exclude-old-transactions': false,
  };

  let environment = 'Production';
  let response = await postAppleReceipt(APPLE_VERIFY_RECEIPT_PRODUCTION, payload);

  if (response.data?.status === 21007) {
    environment = 'Sandbox';
    response = await postAppleReceipt(APPLE_VERIFY_RECEIPT_SANDBOX, payload);
  }

  const data = response.data || {};
  if (data.status !== 0) {
    throw new HttpsError('failed-precondition', `Apple receipt verification failed (${data.status}).`);
  }

  const bundleId = data.receipt?.bundle_id;
  if (bundleId !== IOS_BUNDLE_ID) {
    throw new HttpsError('failed-precondition', 'Receipt bundle id does not match this app.');
  }

  const item = receiptItems(data).find((entry) => (
    entry?.product_id === productId &&
    (entry?.transaction_id === transactionId || entry?.original_transaction_id === transactionId)
  ));

  if (!item) {
    throw new HttpsError('failed-precondition', 'Receipt does not contain the expected purchase transaction.');
  }

  return {
    environment,
    transactionId: item.transaction_id || transactionId,
    originalTransactionId: item.original_transaction_id || '',
    productId: item.product_id,
    purchaseDateMs: Number(item.purchase_date_ms || 0),
  };
}

function customPetResponseFromData(petId, data) {
  const createdAt = data.createdAt?.toDate
    ? data.createdAt.toDate().toISOString()
    : (typeof data.createdAt === 'string' ? data.createdAt : new Date().toISOString());
  return {
    id: petId,
    name: data.name || '',
    species: data.species || 'cat',
    breed: data.breed || null,
    breedTraits: data.breedTraits || '',
    visualTraits: Array.isArray(data.visualTraits) ? data.visualTraits : [],
    originalImagePath: data.originalImagePath || null,
    normalImageUrl: data.normalImageUrl || '',
    sleepingImageUrl: data.sleepingImageUrl || '',
    failedImageUrl: data.failedImageUrl || '',
    avatarStatesVersion: Number(data.avatarStatesVersion || 0),
    status: data.status || 'ready',
    createdAt,
    isLocalAsset: Boolean(data.isLocalAsset),
  };
}

function avatarSharedStyle({
  species,
  breed,
  breedTraits,
  visualTraits,
  featureNote,
}) {
  const traitLines = visualTraits.length > 0
    ? visualTraits.map((trait) => `- ${trait}`).join('\n')
    : '- Use the visible fur colors, markings, eye color, ear shape, face shape, body proportions, and coat length from the reference photo.';
  const breedLine = breed
    ? `Detected breed/type: ${breed}. ${breedTraits || 'Use the breed/type-specific anatomy and coat traits visible in the reference photo.'}`
    : 'Breed/type could not be identified confidently; rely on the visual traits from the reference photo.';
  const featureNoteLock = featureNoteIdentityLock(featureNote);

  return `Create a square PNG app avatar of the exact same ${species} character from the reference photo.
${breedLine}

NON-NEGOTIABLE IDENTITY LOCK:
1. Preserve the pet identity from the reference photo: same fur colors, markings, stripe pattern, patch placement, eye color, ear shape, face shape, muzzle length, coat length, tail fluff, and overall proportions.
2. Do not simplify the pet into a generic ${species}; do not use generic cat/dog anatomy if the photo suggests a specific breed or mixed-breed type.
3. Convert the exact observed traits into a cute cartoon, but keep the distinctive breed/type silhouette and markings recognizable.
4. User-provided identity marks outrank generic breed traits and style preferences.

VISIBLE TRAITS FROM VLM ANALYSIS:
${traitLines}

${featureNoteLock || 'No extra user-provided identity mark.'}

Use one consistent character design for all states: cute flat-design kawaii mascot, clean vector-like shapes, soft warm colors, thick dark outline, centered composition, no cropped face, no text, no letters, no watermark.
Use the exact same background style as the existing Luffy app pet images: a flat solid warm cream background, color ${AVATAR_BACKGROUND_COLOR}. The background must fill the entire square image edge-to-edge. Do not use a circular badge, transparent background, gradients, shadows, scenery, props, frames, or any other background color.
Do not change the species, do not invent different markings, and do not make it look like a different pet.
The three state images must be recognizable as the same character but must not reuse the same pose, facial expression, or body silhouette.`;
}

function avatarPrompts({ species, breed, breedTraits, visualTraits, featureNote }) {
  const sharedStyle = avatarSharedStyle({
    species,
    breed,
    breedTraits,
    visualTraits,
    featureNote,
  });
  return {
    normal: `${sharedStyle}
STATE: NORMAL / AWAKE.
Pose and expression must clearly show the pet is awake and ready: seated or standing upright, both eyes open, cheerful relaxed smile, head upright, ears naturally alert, calm friendly energy.
This normal image must be visually different from the sleeping and interrupted states.
Avoid closed eyes, lying down, sleeping pose, tears, sweat, shock marks, dizzy marks, or sad expression.
Return only one image.`,
    sleeping: `${sharedStyle}
STATE: SLEEPING / FOCUS MODE.
The pose must be completely different from normal at thumbnail size: show the full body curled up in a ball or lying flat in a horizontal resting posture, head resting on paws or floor, both eyes fully closed, peaceful breathing, relaxed ears, sleepy calm mood.
The pet must NOT be sitting upright, standing, facing the camera as a portrait, or smiling at the camera. Do not use open eyes.
No readable text, no letters, no "Zzz"; use body pose alone to communicate sleep.
Avoid upright awake posture, open eyes, smiling-at-camera pose, shock marks, tears, sad expression, or anything that could be mistaken for the normal image.
Return only one image.`,
    failed: `${sharedStyle}
STATE: INTERRUPTED / DISAPPOINTED OR STARTLED.
The pose and expression must be completely different from normal and sleeping at thumbnail size: startled awake, wide surprised eyes or watery disappointed eyes, small frown, raised ears, tiny sweat drop, paws lifted or tense shoulders, and a clear interrupted-focus reaction.
No readable text or letters. You may use tiny abstract stress marks, but do not use words.
Avoid sleeping pose, peaceful smile, normal happy expression, upright calm portrait, or anything that could be mistaken for the normal image.
Return only one image.`,
  };
}

async function generateAndUploadAvatarState({
  uid,
  petId,
  state,
  apiKey,
  imageBase64,
  imageMimeType,
  prompt,
}) {
  const startedAt = Date.now();
  logger.info('Pet avatar state generation started', {
    uid,
    petId,
    state,
    imageMimeType,
  });
  const bytes = await callGeminiImage({ apiKey, imageBase64, imageMimeType, prompt });
  const generatedMs = Date.now() - startedAt;
  const path = `users/${uid}/pets/${petId}/${state}.png`;
  const url = await uploadPublicImage(path, bytes);
  logger.info('Pet avatar state generation finished', {
    uid,
    petId,
    state,
    bytes: bytes.length,
    generatedMs,
    totalMs: Date.now() - startedAt,
    path,
    urlPrefix: url.slice(0, 120),
  });
  return url;
}

exports.analyzePetImage = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 60, memory: '512MiB' },
  async (request) => {
    const uid = requireAuth(request);
    await assertHasCustomPetCredit(uid);
    const imageBase64 = requireString(request.data?.imageBase64, 'imageBase64');
    const imageMimeType = normalizeImageMimeType(request.data?.imageMimeType);

    const prompt = `Analyze the image as a pet-identification and visual-character-reference task.

First decide whether the main subject is a cat or dog.
If it is NOT a cat or dog, return exactly:
{"isPet": false, "species": null, "breed": null, "breedConfidence": 0, "visualTraits": []}

If it is a cat or dog, return JSON only with this shape:
{
  "isPet": true,
  "species": "cat" | "dog",
  "breed": "most likely breed/type in English, or mixed/domestic longhair/domestic shorthair if uncertain",
  "breedConfidence": 0.0 to 1.0,
  "visualTraits": [
    "specific visible coat color and pattern",
    "specific face marking / forehead stripe / muzzle color / patch placement",
    "eye color and eye shape",
    "ear shape and size",
    "coat length and texture",
    "tail/body proportion if visible",
    "any distinctive feature needed to redraw this exact pet"
  ]
}

Use breed/type labels useful for drawing. Examples: beagle, schnauzer, black shiba, shiba inu, corgi, poodle, ragdoll, persian, british longhair, domestic longhair, orange tabby, calico.
Be conservative: if exact breed is uncertain, choose a descriptive type such as domestic longhair, domestic shorthair, or mixed breed.
Only return JSON, no markdown.`;

    try {
      const text = await callGemini({
        apiKey: geminiApiKey.value(),
        json: true,
        parts: [
          { text: prompt },
          { inline_data: { mime_type: imageMimeType, data: imageBase64 } },
        ],
        generationConfig: {
          temperature: 0,
          maxOutputTokens: 500,
        },
      });

      const result = parseGeminiJson(text);
      const species = ['cat', 'dog'].includes(result.species) ? result.species : null;
      const breed = optionalString(result.breed, 80);
      const breedTraits = breedTraitText(species, breed);
      const visualTraits = optionalTraits(result.visualTraits, 7, 110);
      const breedConfidence = Number(result.breedConfidence || 0);
      return {
        isPet: Boolean(result.isPet && species),
        species,
        breed: breed || null,
        breedConfidence: Number.isFinite(breedConfidence) ? breedConfidence : 0,
        breedTraits,
        visualTraits,
      };
    } catch (error) {
      logger.error('Gemini image analysis failed', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message || 'Image analysis failed.');
    }
  },
);

exports.generatePetAvatar = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 300, memory: '1GiB' },
  async (request) => {
    const functionStartedAt = Date.now();
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    const imageBase64 = requireString(request.data?.imageBase64, 'imageBase64');
    const imageMimeType = normalizeImageMimeType(request.data?.imageMimeType);
    const featureNote = optionalString(request.data?.featureNote);
    const species = requireString(request.data?.species, 'species');
    const breed = optionalString(request.data?.breed, 80);
    const visualTraits = optionalTraits(request.data?.visualTraits, 7, 110);
    const breedTraits = optionalString(request.data?.breedTraits, 900) || breedTraitText(species, breed);
    const originalImagePath = optionalString(request.data?.originalImagePath, 240);
    const apiKey = geminiApiKey.value();
    const prompts = avatarPrompts({ species, breed, breedTraits, visualTraits, featureNote });
    let reservedCredit = false;

    try {
      logger.info('Pet avatar normal generation request received', {
        uid,
        petId,
        species,
        breed,
        imageModel: GEMINI_IMAGE_MODEL,
        imageMimeType,
        imageBase64Length: imageBase64.length,
        hasFeatureNote: featureNote.length > 0,
        featureNotePreview: featureNote.slice(0, 80),
        hasOriginalImagePath: originalImagePath.length > 0,
        visualTraitCount: visualTraits.length,
      });

      reservedCredit = await reserveCustomPetCredit(uid, petId);

      const originalUploadPromise = originalImagePath
        ? Promise.resolve(originalImagePath)
        : uploadPrivateImage(
          `users/${uid}/pets/${petId}/original.${originalImageExtension(imageMimeType)}`,
          Buffer.from(imageBase64, 'base64'),
          imageMimeType,
        );

      const [
        storedOriginalImagePath,
        normalImageUrl,
        sleepingImageUrl,
        failedImageUrl,
      ] = await Promise.all([
        originalUploadPromise,
        generateAndUploadAvatarState({
          uid,
          petId,
          state: 'normal',
          apiKey,
          imageBase64,
          imageMimeType,
          prompt: prompts.normal,
        }),
        generateAndUploadAvatarState({
          uid,
          petId,
          state: 'sleeping',
          apiKey,
          imageBase64,
          imageMimeType,
          prompt: prompts.sleeping,
        }),
        generateAndUploadAvatarState({
          uid,
          petId,
          state: 'failed',
          apiKey,
          imageBase64,
          imageMimeType,
          prompt: prompts.failed,
        }),
      ]);

      const now = admin.firestore.FieldValue.serverTimestamp();
      await db.doc(`users/${uid}`).set({
        createdAt: now,
        updatedAt: now,
      }, { merge: true });

      await db.doc(`users/${uid}/pets/${petId}`).set({
        species,
        breed,
        breedTraits,
        visualTraits,
        featureNote,
        originalImagePath: storedOriginalImagePath,
        normalImageUrl,
        sleepingImageUrl,
        failedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        status: 'generated',
        purchaseStatus: 'reserved',
        stateImagesStatus: 'ready',
        isLocalAsset: false,
        createdAt: now,
        updatedAt: now,
      }, { merge: true });

      return {
        originalImagePath: storedOriginalImagePath,
        normalImageUrl,
        sleepingImageUrl,
        failedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        stateImagesStatus: 'ready',
      };
    } catch (error) {
      if (reservedCredit) {
        await releaseCustomPetCreditReservation(uid, petId, { deletePet: true });
      }
      logger.error('Pet avatar normal generation failed', {
        uid,
        petId,
        totalMs: Date.now() - functionStartedAt,
        errorMessage: error?.message,
        error,
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message || 'Pet avatar generation failed.');
    }
  },
);

exports.repairPetAvatarStates = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 300, memory: '1GiB' },
  async (request) => {
    const functionStartedAt = Date.now();
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    const petRef = db.doc(`users/${uid}/pets/${petId}`);
    const snapshot = await petRef.get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Pet not found.');
    }

    const pet = snapshot.data() || {};
    const normalImageUrl = optionalString(pet.normalImageUrl, 1000);
    const sleepingImageUrl = optionalString(pet.sleepingImageUrl, 1000);
    const failedImageUrl = optionalString(pet.failedImageUrl, 1000);
    const avatarStatesVersion = Number(pet.avatarStatesVersion || 0);
    const forceRepair = request.data?.force === true;
    if (!forceRepair &&
        avatarStatesVersion >= AVATAR_STATES_VERSION &&
        normalImageUrl &&
        sleepingImageUrl &&
        failedImageUrl &&
        normalImageUrl !== sleepingImageUrl &&
        normalImageUrl !== failedImageUrl &&
        sleepingImageUrl !== failedImageUrl) {
      return {
        normalImageUrl,
        sleepingImageUrl,
        failedImageUrl,
        stateImagesStatus: pet.stateImagesStatus || 'ready',
        avatarStatesVersion,
      };
    }

    const species = optionalString(pet.species, 20) || 'dog';
    const breed = optionalString(pet.breed, 80);
    const breedTraits = optionalString(pet.breedTraits, 900) ||
        breedTraitText(species, breed);
    const visualTraits = optionalTraits(pet.visualTraits, 7, 110);
    const featureNote = optionalString(pet.featureNote);
    const originalImagePath = optionalString(pet.originalImagePath, 240);
    const apiKey = geminiApiKey.value();

    try {
      logger.info('Pet avatar state repair request received', {
        uid,
        petId,
        species,
        breed,
        visualTraitCount: visualTraits.length,
        hasFeatureNote: featureNote.length > 0,
        hasOriginalImagePath: originalImagePath.length > 0,
        forceRepair,
      });

      const imageInput = await repairImageInputForPet({
        uid,
        petId,
        originalImagePath,
        normalImageUrl,
      });
      const prompts = avatarPrompts({
        species,
        breed,
        breedTraits,
        visualTraits,
        featureNote,
      });

      const [repairedSleepingImageUrl, repairedFailedImageUrl] =
          await Promise.all([
            generateAndUploadAvatarState({
              uid,
              petId,
              state: 'sleeping',
              apiKey,
              imageBase64: imageInput.imageBase64,
              imageMimeType: imageInput.imageMimeType,
              prompt: prompts.sleeping,
            }),
            generateAndUploadAvatarState({
              uid,
              petId,
              state: 'failed',
              apiKey,
              imageBase64: imageInput.imageBase64,
              imageMimeType: imageInput.imageMimeType,
              prompt: prompts.failed,
            }),
          ]);

      await petRef.set({
        sleepingImageUrl: repairedSleepingImageUrl,
        failedImageUrl: repairedFailedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        stateImagesStatus: 'ready',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      logger.info('Pet avatar state repair finished', {
        uid,
        petId,
        totalMs: Date.now() - functionStartedAt,
      });

      return {
        normalImageUrl,
        sleepingImageUrl: repairedSleepingImageUrl,
        failedImageUrl: repairedFailedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        stateImagesStatus: 'ready',
      };
    } catch (error) {
      logger.error('Pet avatar state repair failed', {
        uid,
        petId,
        totalMs: Date.now() - functionStartedAt,
        errorMessage: error?.message,
        error,
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message || 'Pet avatar state repair failed.');
    }
  },
);

exports.generatePetAvatarStates = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 180, memory: '512MiB' },
  async (request) => {
    const functionStartedAt = Date.now();
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    const imageBase64 = requireString(request.data?.imageBase64, 'imageBase64');
    const imageMimeType = normalizeImageMimeType(request.data?.imageMimeType);
    const featureNote = optionalString(request.data?.featureNote);
    const species = requireString(request.data?.species, 'species');
    const breed = optionalString(request.data?.breed, 80);
    const visualTraits = optionalTraits(request.data?.visualTraits, 7, 110);
    const breedTraits = optionalString(request.data?.breedTraits, 900) || breedTraitText(species, breed);
    const apiKey = geminiApiKey.value();
    const prompts = avatarPrompts({ species, breed, breedTraits, visualTraits, featureNote });

    try {
      logger.info('Pet avatar secondary states generation request received', {
        uid,
        petId,
        species,
        breed,
        imageModel: GEMINI_IMAGE_MODEL,
        imageMimeType,
        imageBase64Length: imageBase64.length,
        hasFeatureNote: featureNote.length > 0,
        featureNotePreview: featureNote.slice(0, 80),
        visualTraitCount: visualTraits.length,
      });

      const [sleepingImageUrl, failedImageUrl] = await Promise.all([
        generateAndUploadAvatarState({
          uid,
          petId,
          state: 'sleeping',
          apiKey,
          imageBase64,
          imageMimeType,
          prompt: prompts.sleeping,
        }),
        generateAndUploadAvatarState({
          uid,
          petId,
          state: 'failed',
          apiKey,
          imageBase64,
          imageMimeType,
          prompt: prompts.failed,
        }),
      ]);

      await db.doc(`users/${uid}/pets/${petId}`).set({
        sleepingImageUrl,
        failedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        stateImagesStatus: 'ready',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      logger.info('Pet avatar secondary states generation finished', {
        uid,
        petId,
        totalMs: Date.now() - functionStartedAt,
      });

      return {
        sleepingImageUrl,
        failedImageUrl,
        avatarStatesVersion: AVATAR_STATES_VERSION,
        stateImagesStatus: 'ready',
      };
    } catch (error) {
      logger.error('Pet avatar secondary states generation failed', {
        uid,
        petId,
        totalMs: Date.now() - functionStartedAt,
        errorMessage: error?.message,
        error,
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message || 'Pet avatar states generation failed.');
    }
  },
);

exports.getCustomPetPurchaseCredit = onCall(
  { timeoutSeconds: 20, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request);
    return {
      unusedCredits: await unusedCustomPetCredits(uid),
      productId: CUSTOM_PET_PRODUCT_ID,
    };
  },
);

exports.verifyCustomPetPurchase = onCall(
  { timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request);
    const productId = requireString(request.data?.productId, 'productId');
    const transactionId = requireString(request.data?.transactionId, 'transactionId');
    const verificationData = requireString(request.data?.verificationData, 'verificationData');
    const verificationSource = optionalString(request.data?.verificationSource, 40);

    if (productId !== CUSTOM_PET_PRODUCT_ID) {
      throw new HttpsError('invalid-argument', 'Unexpected product id.');
    }
    if (verificationSource && verificationSource !== 'app_store') {
      throw new HttpsError('invalid-argument', 'Only App Store purchases are supported.');
    }

    const verified = await verifyAppleReceipt({
      verificationData,
      transactionId,
      productId,
    });

    const transactionRef = db.doc(`users/${uid}/iapTransactions/${verified.transactionId}`);
    const creditRef = db.doc(`users/${uid}/petPurchaseCredits/${CUSTOM_PET_CREDIT_DOC_ID}`);
    let unusedCredits = 0;

    await db.runTransaction(async (transaction) => {
      const [transactionSnapshot, creditSnapshot] = await Promise.all([
        transaction.get(transactionRef),
        transaction.get(creditRef),
      ]);

      const currentUnused = Number(creditSnapshot.data()?.unusedCount || 0);
      if (transactionSnapshot.exists) {
        unusedCredits = currentUnused;
        return;
      }

      unusedCredits = currentUnused + 1;
      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.set(transactionRef, {
        productId,
        transactionId: verified.transactionId,
        originalTransactionId: verified.originalTransactionId,
        environment: verified.environment,
        purchaseDateMs: verified.purchaseDateMs,
        verificationSource,
        credited: true,
        createdAt: now,
      }, { merge: true });
      transaction.set(creditRef, {
        productId,
        unusedCount: unusedCredits,
        purchasedCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, { merge: true });
    });

    return {
      ok: true,
      unusedCredits,
      productId: CUSTOM_PET_PRODUCT_ID,
      transactionId: verified.transactionId,
      environment: verified.environment,
    };
  },
);

exports.saveGeneratedPetName = onCall(
  { timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    const name = requireString(request.data?.name, 'name').slice(0, 24);
    const petRef = db.doc(`users/${uid}/pets/${petId}`);
    const creditRef = db.doc(`users/${uid}/petPurchaseCredits/${CUSTOM_PET_CREDIT_DOC_ID}`);
    let responsePet = null;

    await db.runTransaction(async (transaction) => {
      const [petSnapshot, creditSnapshot] = await Promise.all([
        transaction.get(petRef),
        transaction.get(creditRef),
      ]);

      if (!petSnapshot.exists) {
        throw new HttpsError('not-found', 'Generated pet draft was not found.');
      }

      const pet = petSnapshot.data() || {};
      if (pet.status === 'ready' && typeof pet.name === 'string' && pet.name.trim().length > 0) {
        responsePet = customPetResponseFromData(petId, pet);
        return;
      }

      if (pet.purchaseStatus !== 'reserved') {
        throw new HttpsError('failed-precondition', 'Please purchase a custom pet creation credit before saving.');
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.set(creditRef, {
        reservedCount: admin.firestore.FieldValue.increment(-1),
        consumedCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, { merge: true });
      transaction.set(petRef, {
        name,
        status: 'ready',
        purchaseStatus: 'consumed',
        purchaseConsumedAt: now,
        updatedAt: now,
      }, { merge: true });

      responsePet = customPetResponseFromData(petId, {
        ...pet,
        name,
        status: 'ready',
        purchaseStatus: 'consumed',
      });
    });

    return responsePet;
  },
);

exports.releaseCustomPetPurchaseCredit = onCall(
  { timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    await releaseCustomPetCreditReservation(uid, petId, { deletePet: true });
    return {
      ok: true,
      unusedCredits: await unusedCustomPetCredits(uid),
    };
  },
);

exports.generateRewardStory = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 60, memory: '512MiB' },
  async (request) => {
    const uid = requireAuth(request);
    const petId = requireString(request.data?.petId, 'petId');
    const focusMinutes = Number(request.data?.focusMinutes || 0);
    const storyNumber = Number(request.data?.storyNumber || 1);
    const previousStoryTitles = optionalStringArray(request.data?.previousStoryTitles);

    if (!Number.isFinite(focusMinutes) || focusMinutes <= 0) {
      throw new HttpsError('invalid-argument', 'focusMinutes must be positive.');
    }

    if (!Number.isFinite(storyNumber) || storyNumber <= 0) {
      throw new HttpsError('invalid-argument', 'storyNumber must be positive.');
    }

    const petDoc = petId === 'luffy'
      ? null
      : await db.doc(`users/${uid}/pets/${petId}`).get();
    const pet = petDoc?.data() || {};
    const petName = requireString(request.data?.petName || pet.name, 'petName');
    const species = requireString(request.data?.species || pet.species, 'species');
    const speciesText = species === 'cat' ? '貓咪' : '狗狗';
    const previousTitlesText = previousStoryTitles.length > 0
      ? previousStoryTitles.map((title) => `「${title}」`).join('、')
      : '目前沒有';

    const prompt = `你是一個溫暖、富有童趣的故事創作者。
用戶剛剛完成了 ${focusMinutes} 分鐘的專注挑戰。
陪伴者是一隻名為「${petName}」的${speciesText}。
這是牠的第 ${storyNumber} 篇夢境獎勵故事。

請寫一篇全新的繁體中文夢境故事，長度約 320 到 450 個中文字，接近睡前童話短篇。
故事必須：
1. 以「【全新標題】」開頭，標題不可和以下標題重複：${previousTitlesText}。
2. 讓「${petName}」成為主角，內容像夢境、童話或奇幻小冒險。
3. 自然提到用戶完成了 ${focusMinutes} 分鐘專注，以及 ${petName} 在旁陪伴、守護或把專注時間變成夢境裡的禮物。
4. 不要重複使用既有標題、核心場景或同樣的故事轉折；每一篇都要是獨立的新故事。
5. 語氣溫柔、有畫面感，適合完成專注後作為獎勵讀給用戶。

只回覆故事正文，不要加說明、引言、Markdown 或條列。`;

    try {
      const story = (await callGemini({
        apiKey: geminiApiKey.value(),
        parts: [{ text: prompt }],
        generationConfig: {
          temperature: 0.95,
          topP: 0.9,
        },
      })).trim();

      await db.collection(`users/${uid}/stories`).add({
        petId,
        petName,
        species,
        focusMinutes,
        storyNumber,
        storyText: story,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { story };
    } catch (error) {
      logger.error('Reward story generation failed', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error.message || 'Reward story generation failed.');
    }
  },
);
