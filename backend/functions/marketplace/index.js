// backend/functions/marketplace/index.js
// Yandex Cloud Function — поиск товаров на маркетплейсах через Apify + YandexGPT.
//
// Security pipeline (CLAUDE.md требование, аналог backend/index.js):
//   1. APP_TOKEN header check
//   2. Input validation (length, regex)
//   3. Rate limit per userId
//   4. promptGuard на user-supplied query (попадает в YandexGPT prompt)
//   5. Apify runActor + YandexGPT enrich

import { runActor } from '../../shared/apify-client.js';
import { callYandexGPT } from '../../shared/yandexgpt.js';
import { getSecrets } from '../../shared/secrets.js';
import { guardPrompt } from '../../shared/promptGuard.js';

const APP_TOKEN_HEADER = 'x-app-token';
const MAX_QUERY_LENGTH = 1000;
const MAX_USER_ID_LENGTH = 64;
const RATE_LIMIT_PER_MINUTE = 20;
const RATE_WINDOW_MS = 60_000;

const ALLOWED_STYLES = new Set([
  'modern', 'minimalist', 'loft', 'scandinavian',
  'classic_russian', 'eclectic', 'vintage', 'professional',
  'современный', // legacy fallback в текущем коде
]);

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
    const { query, roomStyle, budget, userId } = body;

    if (!query || typeof query !== 'string') {
      return buildResponse(400, { error: 'Missing required field: query' });
    }
    if (!userId || typeof userId !== 'string') {
      return buildResponse(400, { error: 'Missing required field: userId' });
    }

    // 3. Input limits + regex
    if (query.length > MAX_QUERY_LENGTH) {
      return buildResponse(413, { error: 'Query too long' });
    }
    if (userId.length > MAX_USER_ID_LENGTH || !/^[a-zA-Z0-9_.-]+$/.test(userId)) {
      return buildResponse(400, { error: 'Invalid userId format' });
    }
    // roomStyle — whitelist enum, защита от prompt injection через style
    const safeStyle = (typeof roomStyle === 'string' && ALLOWED_STYLES.has(roomStyle))
      ? roomStyle
      : 'modern';
    // budget — только число, защита от объектов/строк-инъекций
    const safeBudget = (typeof budget === 'number' && budget > 0 && budget < 100_000_000)
      ? budget
      : null;

    // 4. Rate limit
    const rateInfo = checkRateLimit(userId);
    if (!rateInfo.allowed) {
      return buildResponse(429, { error: 'Rate limit exceeded. Max 20 req/min.', retryAfter: 60 });
    }

    // 5. promptGuard на query — попадает напрямую в YandexGPT prompt в enrichWithYandexGPT
    const guard = guardPrompt(query);
    if (!guard.allowed) {
      console.warn('[guard] marketplace query rejected', JSON.stringify({
        userId: userId.slice(0, 16),
        reason: guard.reason,
      }));
      return buildResponse(400, { error: 'Content policy violation' });
    }

    // 6. Secrets + Apify
    await getSecrets();

    const recommendations = await runActor(
      'apify/product-recommendation-agent', // ← заменить на ID из mega-list
      {
        query: `${query} для интерьера в стиле ${safeStyle}`,
        maxResults: 10,
        language: 'ru',
        marketplaces: ['wildberries.ru', 'ozon.ru'],
      },
      { timeoutSecs: 60, memoryMbytes: 512 }
    );

    const filtered = safeBudget
      ? recommendations.filter(r => !r.price || r.price <= safeBudget)
      : recommendations;

    const enriched = await enrichWithYandexGPT(filtered, query, safeStyle);

    return buildResponse(200, {
      products: enriched,
      latency_ms: Date.now() - startTime,
      rateLimit: { remaining: rateInfo.remaining, resetInMs: RATE_WINDOW_MS },
    });

  } catch (err) {
    const requestId = (typeof crypto !== 'undefined' && crypto.randomUUID)
      ? crypto.randomUUID() : String(Date.now());
    console.error('marketplace fatal error:', JSON.stringify({
      requestId, message: err.message, stack: err.stack?.slice(0, 500),
    }));
    return buildResponse(500, { error: 'internal_error', requestId });
  }
};

async function enrichWithYandexGPT(products, query, roomStyle) {
  if (products.length === 0) return [];

  const list = products.slice(0, 5)
    .map((p, i) => `${i + 1}. ${p.name} — ${p.price ?? '?'} руб.`)
    .join('\n');

  const prompt = `Ты эксперт по дизайну интерьеров (стиль: ${roomStyle}).
Клиент ищет: "${query}".

Товары:
${list}

Для каждого — одно предложение: подходит или нет для этого стиля, и почему.
Формат: "1. [причина]"`;

  try {
    const result = await callYandexGPT({ prompt });
    return products.map((p, i) => ({
      ...p,
      aiReason: extractLine(result.text, i + 1),
    }));
  } catch {
    return products;
  }
}

function extractLine(text, n) {
  const match = text.match(new RegExp(`${n}\\.\\s*(.+?)(?=\\d+\\.|$)`, 's'));
  return match?.[1]?.trim() ?? '';
}
