// backend/shared/partner-catalog.js
// Партнёрский каталог — единственный источник товаров (B2/B3, Фаза 2).
//
// Пивот 2026-06 (docs/BUSINESS_MODEL.md): маркетплейсы Ozon/Wildberries убраны,
// работаем только с каталогом мебельных фабрик-партнёров.
//
// Источник данных — таблица YDB `products` (контракт полей — в catalog-search.js),
// наполняется конвейером B1; тестовое наполнение — backend/scripts/seed-test-catalog.mjs.

import { searchCatalog } from './catalog-search.js';
import { ydbClient } from './ydb-client.js';

const PRODUCTS_TABLE = 'products';
const ARTICLE_PATTERN = /^[a-zA-Z0-9_.-]{1,64}$/;

// Канон категорий каталога. Совпадает с конвейером B1 и сид-скриптом:
// меняешь список — меняй и наполнение каталога.
// Стемы — чтобы покрыть словоформы запроса («диваны», «кроватью»);
// сравнение по началу слова, а не по подстроке — иначе «выбрать» дало бы «бра».
const CATEGORY_STEMS = [
    ['sofa', ['диван', 'софа']],
    ['bed', ['кроват']],
    ['armchair', ['кресл']],
    ['chair', ['стул', 'табурет']],
    ['table', ['стол']],
    ['wardrobe', ['шкаф', 'гардероб', 'комод']],
    ['shelf', ['полк', 'стеллаж']],
    ['cabinet', ['тумб']],
    ['lamp', ['ламп', 'светильник', 'люстр', 'торшер']],
    ['carpet', ['ковр', 'ковёр', 'ковер']],
];

/**
 * Определяет категорию мебели по свободному тексту запроса.
 * @param {string} query — например «серый диван в гостиную»
 * @returns {string|null} категория каталога или null (поиск без фильтра категории)
 */
export function detectFurnitureCategory(query) {
    const words = String(query ?? '').toLowerCase().split(/[^a-zа-яё0-9]+/);
    for (const [category, stems] of CATEGORY_STEMS) {
        if (stems.some(stem => words.some(word => word.startsWith(stem)))) {
            return category;
        }
    }
    return null;
}

/**
 * Запись каталога → формат products ответа функции поиска
 * (исторический контракт клиента + usdzUrl/category/style).
 */
export function toMarketplaceProduct(record) {
    return {
        name: record.name ?? 'Без названия',
        price: typeof record.price === 'number' && Number.isFinite(record.price) ? record.price : null,
        url: record.product_url ?? '',
        imageUrl: record.image_url ?? '',
        marketplace: 'partner',
        article: record.article != null ? String(record.article) : '',
        usdzUrl: record.usdz_url ?? '',
        category: record.category ?? '',
        style: record.style ?? '',
    };
}

/**
 * Поиск по партнёрскому каталогу в формате ответа маркетплейса.
 * Категория выводится из текста запроса; стиль (если задан) — фильтр первой
 * попытки, при пустой выдаче повторяем без стиля: каталог на старте маленький,
 * и жёсткий стиль-фильтр чаще режет всё, чем помогает.
 *
 * @param {object} params
 * @param {string} params.query — пользовательский текст запроса
 * @param {string} [params.style] — стиль из whitelist маркетплейса (или null)
 * @param {number} [params.topK=10]
 * @returns {Promise<object[]>}
 */
export async function searchPartnerCatalog({ query, style, topK = 10 }) {
    const category = detectFurnitureCategory(query) ?? undefined;

    let records = await searchCatalog({ category, style: style ?? undefined, topK });
    if (records.length === 0 && style) {
        records = await searchCatalog({ category, topK });
    }
    return records.map(toMarketplaceProduct);
}

/**
 * Резолвер B3: артикул → запись каталога (usdz_url, цена, карточка партнёра).
 * @param {string} article
 * @returns {Promise<object|null>} товар в формате маркетплейса или null (не найден / YDB off)
 */
export async function resolveArticle(article) {
    if (typeof article !== 'string' || !ARTICLE_PATTERN.test(article)) return null;
    const record = await ydbClient.get(PRODUCTS_TABLE, 'article', article);
    return record ? toMarketplaceProduct(record) : null;
}
