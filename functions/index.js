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
const GEMINI_IMAGE_MODEL = 'gemini-2.5-flash-image';
const AVATAR_BACKGROUND_COLOR = '#FDF6E3';

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
  rabbit: {
    'holland lop': 'Holland Lop traits: small compact body, floppy lop ears, round head, short muzzle, dense soft coat.',
    'netherland dwarf': 'Netherland Dwarf traits: tiny compact body, very short ears, round face, large eyes, short neck.',
    lionhead: 'Lionhead rabbit traits: fluffy mane around head and neck, compact body, upright ears, woolly cheek fur.',
    rex: 'Rex rabbit traits: plush velvet-like short coat, upright ears, rounded body, soft dense fur texture.',
    'mini rex': 'Mini Rex traits: small body, plush velvet-like short coat, upright ears, round compact proportions.',
    dutch: 'Dutch rabbit traits: white blaze on face, white chest/front, colored ears and rear, crisp two-tone pattern.',
    angora: 'Angora rabbit traits: very long woolly fluffy coat, rounded cloud-like body, ears partly hidden by fur.',
    'flemish giant': 'Flemish Giant traits: very large long body, broad head, long upright ears, sturdy proportions.',
    'dwarf hotot': 'Dwarf Hotot traits: small white rabbit, distinctive dark eyeliner rings around eyes, short upright ears.',
    lop: 'Lop rabbit traits: drooping ears, rounded head, compact soft body; preserve exact coat color and markings from photo.',
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
  return `Create a square PNG app avatar of the exact same ${species} character from the reference photo.
${breedLine}

NON-NEGOTIABLE IDENTITY LOCK:
1. Preserve the pet identity from the reference photo: same fur colors, markings, stripe pattern, patch placement, eye color, ear shape, face shape, muzzle length, coat length, tail fluff, and overall proportions.
2. Do not simplify the pet into a generic ${species}; do not use generic cat/dog/rabbit anatomy if the photo suggests a specific breed or mixed-breed type.
3. Convert the exact observed traits into a cute cartoon, but keep the distinctive breed/type silhouette and markings recognizable.

VISIBLE TRAITS FROM VLM ANALYSIS:
${traitLines}

${featureNote ? `USER-PROVIDED FEATURE NOTE - HIGHEST PRIORITY:
The user explicitly says: "${featureNote}".
This detail must be visibly represented in the cartoon unless it directly contradicts the photo. If it is a mole, scar, special patch, unusual eye detail, collar, ear mark, or color detail, draw it clearly and consistently.` : 'No extra user-provided feature note.'}

Use one consistent character design for all states: cute flat-design kawaii mascot, clean vector-like shapes, soft warm colors, thick dark outline, centered composition, no cropped face, no text, no letters, no watermark.
Use the exact same background style as the existing Luffy app pet images: a flat solid warm cream background, color ${AVATAR_BACKGROUND_COLOR}. The background must fill the entire square image edge-to-edge. Do not use a circular badge, transparent background, gradients, shadows, scenery, props, frames, or any other background color.
Do not change the species, do not invent different markings, and do not make it look like a different pet.`;
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
Pose and expression must clearly show the pet is awake and ready: both eyes open, cheerful relaxed smile, head upright, ears naturally alert, calm friendly energy.
Avoid closed eyes, sleeping pose, tears, sweat, shock marks, dizzy marks, or sad expression.
Return only one image.`,
    sleeping: `${sharedStyle}
STATE: SLEEPING / FOCUS MODE.
Pose and expression must clearly show real sleep, not just a happy closed-eye smile: body curled up or lying down with head resting on paws, both eyes fully closed, peaceful breathing, relaxed ears, sleepy calm mood.
Add subtle sleep cues such as a small "Zzz" bubble or tiny moon/star icons near the head, but keep them minimal and do not add any other text.
Avoid upright awake posture, open eyes, smiling-at-camera pose, shock marks, tears, or sad expression.
Return only one image.`,
    failed: `${sharedStyle}
STATE: INTERRUPTED / DISAPPOINTED OR STARTLED.
Pose and expression must clearly show the pet was disturbed: wide surprised eyes or watery disappointed eyes, small frown, raised ears, tiny sweat drop, and a slight startled pose.
Use visual emotion cues like small stress marks or a tiny exclamation symbol, but no readable words.
Avoid sleeping pose, peaceful smile, or normal happy expression.
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
    requireAuth(request);
    const imageBase64 = requireString(request.data?.imageBase64, 'imageBase64');
    const imageMimeType = normalizeImageMimeType(request.data?.imageMimeType);

    const prompt = `Analyze the image as a pet-identification and visual-character-reference task.

First decide whether the main subject is a cat, dog, or rabbit.
If it is NOT a cat, dog, or rabbit, return exactly:
{"isPet": false, "species": null, "breed": null, "breedConfidence": 0, "visualTraits": []}

If it is a cat, dog, or rabbit, return JSON only with this shape:
{
  "isPet": true,
  "species": "cat" | "dog" | "rabbit",
  "breed": "most likely breed/type in English, or mixed/domestic longhair/domestic shorthair/lop if uncertain",
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

Use breed/type labels useful for drawing. Examples: beagle, schnauzer, black shiba, shiba inu, corgi, poodle, ragdoll, persian, british longhair, domestic longhair, orange tabby, calico, holland lop, netherland dwarf, lionhead.
Be conservative: if exact breed is uncertain, choose a descriptive type such as domestic longhair, domestic shorthair, lop rabbit, mixed breed.
Only return JSON, no markdown.`;

    try {
      const text = await callGemini({
        apiKey: geminiApiKey.value(),
        json: true,
        parts: [
          { text: prompt },
          { inline_data: { mime_type: imageMimeType, data: imageBase64 } },
        ],
      });

      const result = parseGeminiJson(text);
      const species = ['cat', 'dog', 'rabbit'].includes(result.species) ? result.species : null;
      const breed = optionalString(result.breed, 80);
      const breedTraits = breedTraitText(species, breed);
      const visualTraits = optionalTraits(result.visualTraits, 10, 140);
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
    const visualTraits = optionalTraits(request.data?.visualTraits, 10, 140);
    const breedTraits = optionalString(request.data?.breedTraits, 1200) || breedTraitText(species, breed);
    const originalImagePath = requireString(request.data?.originalImagePath, 'originalImagePath');
    const apiKey = geminiApiKey.value();
    const prompts = avatarPrompts({ species, breed, breedTraits, visualTraits, featureNote });

    try {
      logger.info('Pet avatar normal generation request received', {
        uid,
        petId,
        species,
        breed,
        imageMimeType,
        imageBase64Length: imageBase64.length,
        hasFeatureNote: featureNote.length > 0,
        visualTraitCount: visualTraits.length,
      });

      const normalImageUrl = await generateAndUploadAvatarState({
        uid,
        petId,
        state: 'normal',
        apiKey,
        imageBase64,
        imageMimeType,
        prompt: prompts.normal,
      });

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
        originalImagePath,
        normalImageUrl,
        sleepingImageUrl: normalImageUrl,
        failedImageUrl: normalImageUrl,
        status: 'generated',
        stateImagesStatus: 'normal_ready',
        isLocalAsset: false,
        createdAt: now,
        updatedAt: now,
      }, { merge: true });

      return {
        originalImagePath,
        normalImageUrl,
        sleepingImageUrl: normalImageUrl,
        failedImageUrl: normalImageUrl,
        stateImagesStatus: 'normal_ready',
      };
    } catch (error) {
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
    const visualTraits = optionalTraits(request.data?.visualTraits, 10, 140);
    const breedTraits = optionalString(request.data?.breedTraits, 1200) || breedTraitText(species, breed);
    const apiKey = geminiApiKey.value();
    const prompts = avatarPrompts({ species, breed, breedTraits, visualTraits, featureNote });

    try {
      logger.info('Pet avatar secondary states generation request received', {
        uid,
        petId,
        species,
        breed,
        imageMimeType,
        imageBase64Length: imageBase64.length,
        hasFeatureNote: featureNote.length > 0,
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
    const speciesText = species === 'cat' ? '貓咪' : (species === 'rabbit' ? '兔子' : '狗狗');
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
