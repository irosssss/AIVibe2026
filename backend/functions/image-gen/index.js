// backend/functions/image-gen/index.js
// Yandex Cloud Function — генерация изображений интерьеров через Apify Image Generation Actor.
//
// Security pipeline:
//   1. APP_TOKEN header check
//   2. Input validation (enum whitelist для style/roomType)
//   3. Rate limit per userId — image-gen дорогой (90s × 1024MB × 2 image)

import { runActor } from '../../shared/apify-client.js';
import { getSecrets } from '../../shared/secrets.js';

const APP_TOKEN_HEADER = 'x-app-token';
const MAX_USER_ID_LENGTH = 64;
const MAX_PALETTE_LENGTH = 100;
// Image-gen существенно дороже AI-advisor — отдельный, более жёсткий лимит.
const RATE_LIMIT_PER_MINUTE = 5;
const RATE_WINDOW_MS = 60_000;

const STYLE_EN = {
  modern: 'modern contemporary interior, clean lines, neutral tones',
  minimalist: 'minimalist interior, white walls, functional, negative space',
  loft: 'loft style, exposed brick, metal elements, industrial',
  scandinavian: 'scandinavian interior, light wood, white, cozy, plants',
  classic_russian: 'classic interior, ornate details, rich fabrics, symmetry',
  eclectic: 'eclectic interior, mixed styles, bold accents',
  vintage: 'vintage interior, warm tones, antique furniture',
  professional: 'professional home office, dark accents, formal',
};

const ROOM_EN = {
  living_room: 'living room',
  bedroom: 'bedroom',
  kitchen: 'kitchen',
  bathroom: 'bathroom',
  office: 'home office',
  dining_room: 'dining room',
  hallway: 'hallway',
  child_room: "children's room",
};

const rateLimitStore = new Map();

function checkRateLimit(userId) {
  const now = Date.now();
  let entry = rateLimitStore.get(userId);
  if (!entry || now > entry.resetAt) {
    rateLimitStore.set(userId, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return { allowed: true, remaining: RATE_LIMIT_PER_MINUTE - 1 };
  }
  if (entry.count >= RATE_LIMIT_PER_MINUTE) return { allowed: false, remaining: 0 };
  entry.count++;
  return { allowed: true, remaining: Math.max(0, RATE_LIMIT_PER_MINUTE - entry.count) };
}

function buildResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-App-Token',
    },
    body: JSON.stringify(body),
  };
}

export const handler = async (event, context) => {
  const startTime = Date.now();

  try {
    // 1. APP_TOKEN check
    const appToken = event.headers?.[APP_TOKEN_HEADER]
                  || event.headers?.[APP_TOKEN_HEADER.toLowerCase()];
    const expectedToken = process.env.APP_TOKEN;
    if (!expectedToken || appToken !== expectedToken) {
      return buildResponse(403, { error: 'Forbidden: invalid App Token' });
    }

    // 2. Parse + типы
    let body;
    try {
      body = JSON.parse(event.body ?? '{}');
    } catch {
      return buildResponse(400, { error: 'Invalid JSON body' });
    }
    const { style, roomType, colorPalette, userId } = body;

    if (!style || typeof style !== 'string') {
      return buildResponse(400, { error: 'Missing required field: style' });
    }
    if (!userId || typeof userId !== 'string') {
      return buildResponse(400, { error: 'Missing required field: userId' });
    }

    // 3. userId regex/length
    if (userId.length > MAX_USER_ID_LENGTH || !/^[a-zA-Z0-9_.-]+$/.test(userId)) {
      return buildResponse(400, { error: 'Invalid userId format' });
    }

    // 4. style + roomType: ТОЛЬКО whitelist enum — не доверяем строкам в prompt
    if (!Object.prototype.hasOwnProperty.call(STYLE_EN, style)) {
      return buildResponse(400, { error: 'Unsupported style' });
    }
    if (roomType && !Object.prototype.hasOwnProperty.call(ROOM_EN, roomType)) {
      return buildResponse(400, { error: 'Unsupported roomType' });
    }
    // colorPalette — short string, sanitize to letters/digits/space/comma/dash/#hex
    let safePalette = '';
    if (typeof colorPalette === 'string') {
      if (colorPalette.length > MAX_PALETTE_LENGTH) {
        return buildResponse(413, { error: 'colorPalette too long' });
      }
      // Допускаем только безопасный набор символов — никаких управляющих или Unicode tag block.
      if (!/^[a-zA-Z0-9 ,#-]*$/.test(colorPalette)) {
        return buildResponse(400, { error: 'colorPalette contains forbidden characters' });
      }
      safePalette = colorPalette;
    }

    // 5. Rate limit
    const rateInfo = checkRateLimit(userId);
    if (!rateInfo.allowed) {
      return buildResponse(429, { error: 'Rate limit exceeded. Max 5 req/min for image generation.', retryAfter: 60 });
    }

    // 6. Build prompt — все компоненты прошли whitelist
    await getSecrets();
    const styleDesc = STYLE_EN[style];
    const roomDesc = roomType ? ROOM_EN[roomType] : 'interior';
    const palette = safePalette ? `, color palette: ${safePalette}` : '';
    const prompt = `${styleDesc}, ${roomDesc}${palette}, photorealistic interior photography, 8K, natural lighting, architectural digest quality`;

    const results = await runActor(
      'apify/image-generation-agent',
      {
        prompt,
        negativePrompt: 'lowres, blurry, ugly, deformed, cartoon',
        width: 1024,
        height: 768,
        numberOfImages: 2,
      },
      { timeoutSecs: 90, memoryMbytes: 1024 }
    );

    const images = results.filter(r => r.imageUrl).map(r => ({ url: r.imageUrl, prompt }));

    return buildResponse(200, {
      images,
      latency_ms: Date.now() - startTime,
      rateLimit: { remaining: rateInfo.remaining, resetInMs: RATE_WINDOW_MS },
    });

  } catch (err) {
    const requestId = (typeof crypto !== 'undefined' && crypto.randomUUID)
      ? crypto.randomUUID() : String(Date.now());
    console.error('image-gen fatal error:', JSON.stringify({
      requestId, message: err.message, stack: err.stack?.slice(0, 500),
    }));
    return buildResponse(500, { error: 'internal_error', requestId });
  }
};
