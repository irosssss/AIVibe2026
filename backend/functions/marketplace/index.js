// backend/functions/marketplace/index.js
// Cloud Function маркетплейса: параллельный поиск по Wildberries и Ozon
// через Apify-акторы, нормализация к общему формату, AI-объяснения от YandexGPT.

import { runActor } from '../../shared/apify-client.js';
import { callYandexGPT } from '../../shared/yandexgpt.js';
import { getSecrets } from '../../shared/secrets.js';

// ВАЖНО: ID акторов нужно подтвердить на apify.com/store перед продакшеном.
// Поля в выдаче актора тоже стоит сверить во время smoke-теста (см. normalize*).
const WILDBERRIES_ACTOR = 'epctex/wildberries-scraper';
const OZON_ACTOR = 'epctex/ozon-scraper';

const MAX_ITEMS_PER_SOURCE = 8;
const MAX_RESULTS = 10;
const ACTOR_OPTIONS = { timeoutSecs: 40, memoryMbytes: 512 };

export const handler = async (event, context) => {
  await getSecrets();

  const body = JSON.parse(event.body ?? '{}');
  const { query, roomStyle, budget, userId } = body;

  if (!query || !userId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'query and userId required' }) };
  }

  const actorInput = { search: query, maxItems: MAX_ITEMS_PER_SOURCE, proxy: { useApifyProxy: true } };

  // 1. Параллельный поиск: один упавший актор не валит весь запрос.
  const [wbResult, ozonResult] = await Promise.allSettled([
    runActor(WILDBERRIES_ACTOR, actorInput, ACTOR_OPTIONS),
    runActor(OZON_ACTOR, actorInput, ACTOR_OPTIONS),
  ]);

  const wbItems = settledItems(wbResult, 'wildberries');
  const ozonItems = settledItems(ozonResult, 'ozon');

  // 2. Нормализация к общему формату.
  let products = [...normalizeWildberries(wbItems), ...normalizeOzon(ozonItems)];

  // 3. Фильтр по бюджету (если задан валидный).
  const safeBudget = typeof budget === 'number' && budget > 0 ? budget : null;
  if (safeBudget) {
    products = products.filter((p) => !p.price || p.price <= safeBudget);
  }

  // 4. Не больше MAX_RESULTS.
  products = products.slice(0, MAX_RESULTS);

  const marketplace_sources = { wildberries: wbItems.length, ozon: ozonItems.length };

  // 5. Оба источника пусты — понятный ответ, без ошибки.
  if (products.length === 0) {
    return {
      statusCode: 200,
      body: JSON.stringify({
        products: [],
        message: 'Товары не найдены, попробуйте изменить запрос',
        marketplace_sources,
      }),
    };
  }

  // 6. AI-объяснения от YandexGPT (best-effort: при ошибке вернём без них).
  const enriched = await enrichWithYandexGPT(products, query, roomStyle);

  return {
    statusCode: 200,
    body: JSON.stringify({ products: enriched, marketplace_sources }),
  };
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

  const prompt = `Ты эксперт по дизайну интерьеров (стиль: ${roomStyle ?? 'современный'}).
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
    return products; // fallback без AI-объяснений
  }
}

function extractLine(text, n) {
  const match = text.match(new RegExp(`${n}\\.\\s*(.+?)(?=\\d+\\.|$)`, 's'));
  return match?.[1]?.trim() ?? '';
}
