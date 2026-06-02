// backend/functions/marketplace/index.js
// Yandex Cloud Function — поиск товаров на маркетплейсах через Apify + YandexGPT.
//
// Security pipeline (CLAUDE.md требование, аналог backend/index.js):
//   1. APP_TOKEN header check
//   2. Input validation (length, regex)
//   3. Rate limit per IP + per userId
//   4. promptGuard на user-supplied query (попадает в YandexGPT prompt)
//   5. Параллельный поиск Wildberries + Ozon (Apify), нормализация, YandexGPT enrich

import { runActor } from '../../shared/apify-client.js';
import { callYandexGPT } from '../../shared/yandexgpt.js';
import { getSecrets } from '../../shared/secrets.js';
import { guardPrompt } from '../../shared/promptGuard.js';
import { createRateLimiter, clientIp } from '../../shared/rate-limit.js';

// Вторичный лимит по IP (#17) — backstop против ротации userId в теле запроса.
const ipLimiter = createRateLimiter({ max: 60 });

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

// ВАЖНО: ID акторов нужно подтвердить на apify.com/store перед продакшеном.
// Поля в выдаче актора тоже стоит сверить во время smoke-теста (см. normalize*).
const WILDBERRIES_ACTOR = 'epctex/wildberries-scraper';
const OZON_ACTOR = 'epctex/ozon-scraper';

const MAX_ITEMS_PER_SOURCE = 8;
const MAX_RESULTS = 10;
const ACTOR_OPTIONS = { timeoutSecs: 40, memoryMbytes: 512 };

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
    // 0. CORS preflight — до проверки токена.
    if (event.httpMethod === 'OPTIONS') {
      return buildResponse(200, {});
    }

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

    // 4. Rate limit — по IP (backstop против ротации userId, #17) и по userId.
    const ipInfo = ipLimiter(clientIp(event));
    if (!ipInfo.allowed) {
      return buildResponse(429, { error: 'Rate limit exceeded (per-IP).', retryAfter: 60 });
    }
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

    // 6. Secrets + параллельный поиск по двум маркетплейсам.
    await getSecrets();

    const actorInput = { search: query, maxItems: MAX_ITEMS_PER_SOURCE, proxy: { useApifyProxy: true } };

    // Один упавший актор не валит весь запрос.
    const [wbResult, ozonResult] = await Promise.allSettled([
      runActor(WILDBERRIES_ACTOR, actorInput, ACTOR_OPTIONS),
      runActor(OZON_ACTOR, actorInput, ACTOR_OPTIONS),
    ]);

    const wbItems = settledItems(wbResult, 'wildberries');
    const ozonItems = settledItems(ozonResult, 'ozon');

    // Нормализация к общему формату.
    let products = [...normalizeWildberries(wbItems), ...normalizeOzon(ozonItems)];

    // Фильтр по бюджету (safeBudget уже провалидирован выше).
    if (safeBudget) {
      products = products.filter((p) => !p.price || p.price <= safeBudget);
    }
    products = products.slice(0, MAX_RESULTS);

    const marketplace_sources = { wildberries: wbItems.length, ozon: ozonItems.length };
    const rateLimit = { remaining: rateInfo.remaining, resetInMs: RATE_WINDOW_MS };

    // Оба источника пусты — понятный ответ, без ошибки.
    if (products.length === 0) {
      return buildResponse(200, {
        products: [],
        message: 'Товары не найдены, попробуйте изменить запрос',
        marketplace_sources,
        latency_ms: Date.now() - startTime,
        rateLimit,
      });
    }

    // AI-объяснения от YandexGPT (best-effort: при ошибке вернём без них).
    const enriched = await enrichWithYandexGPT(products, query, safeStyle);

    return buildResponse(200, {
      products: enriched,
      marketplace_sources,
      latency_ms: Date.now() - startTime,
      rateLimit,
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

// ─── Результаты Promise.allSettled ───────────────────────────────

function settledItems(result, label) {
  if (result.status === 'fulfilled' && Array.isArray(result.value)) {
    return result.value;
  }
  if (result.status === 'rejected') {
    console.warn(`[marketplace] ${label} actor failed:`, result.reason?.message ?? result.reason);
  }
  return [];
}

// ─── Нормализация ────────────────────────────────────────────────
// Поля акторов могут отличаться — берём первое подходящее имя поля.

function pickFirst(obj, keys) {
  for (const k of keys) {
    const v = obj?.[k];
    if (v !== undefined && v !== null && v !== '') return v;
  }
  return undefined;
}

function normalizePrice(raw) {
  if (raw == null) return null;
  if (typeof raw === 'number') return Number.isFinite(raw) ? raw : null;
  const n = Number(String(raw).replace(/[^\d.]/g, ''));
  return Number.isFinite(n) ? n : null;
}

function firstImage(obj) {
  const direct = pickFirst(obj, ['imageUrl', 'image', 'img', 'thumbnail']);
  if (direct) return direct;
  if (Array.isArray(obj?.images) && obj.images.length) {
    const first = obj.images[0];
    return typeof first === 'string' ? first : (first?.url ?? '');
  }
  return '';
}

function normalizeWildberries(items) {
  return items.map((it) => {
    const article = pickFirst(it, ['article', 'id', 'sku', 'nmId', 'productId']);
    return {
      name: pickFirst(it, ['name', 'title', 'productName']) ?? 'Без названия',
      price: normalizePrice(pickFirst(it, ['price', 'salePrice', 'priceWithSale', 'finalPrice'])),
      url:
        pickFirst(it, ['url', 'link', 'productUrl']) ??
        (article ? `https://www.wildberries.ru/catalog/${article}/detail.aspx` : ''),
      imageUrl: firstImage(it),
      marketplace: 'wildberries',
      article: article != null ? String(article) : '',
    };
  });
}

function normalizeOzon(items) {
  return items.map((it) => {
    const article = pickFirst(it, ['article', 'id', 'sku', 'productId']);
    return {
      name: pickFirst(it, ['name', 'title', 'productName']) ?? 'Без названия',
      price: normalizePrice(pickFirst(it, ['price', 'salePrice', 'priceWithSale', 'finalPrice'])),
      url: pickFirst(it, ['url', 'link', 'productUrl']) ?? '',
      imageUrl: firstImage(it),
      marketplace: 'ozon',
      article: article != null ? String(article) : '',
    };
  });
}

// ─── AI-объяснения ───────────────────────────────────────────────

async function enrichWithYandexGPT(products, query, roomStyle) {
  if (products.length === 0) return [];

  const list = products
    .slice(0, 5)
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
