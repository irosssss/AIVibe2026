// backend/shared/catalog-search.js
// Поиск по партнёрскому каталогу мебели (B5, Фаза 2).
//
// Вердикт PoC B5 (см. docs/UPGRADE_PLAN.md): настоящий KNN на стороне YDB
// недоступен из Cloud Function без npm-зависимостей — Document API не умеет
// YQL/Knn::, ExecuteStatement/PartiQL не поддержан. Поэтому честный путь:
//   1) пре-фильтр на стороне YDB — FilterExpression (категория + стиль +
//      габариты ±15%), страницы и потолок в ydbClient.scanFiltered;
//   2) ранжирование малого набора кандидатов по близости габаритов в Node.
//
// Контракт таблицы `products` (наполняется конвейером B1/B2):
//   article (S, PK) — артикул товара
//   name (S), category (S), style (S)
//   width_cm, depth_cm, height_cm (N) — габариты в сантиметрах
//   price (N) — цена в рублях
//   usdz_url (S) — ссылка на 3D-модель в Object Storage
//   product_url (S) — карточка товара у партнёра
//   image_url (S, опционально) — превью товара для карточки в приложении
// Меняешь поля здесь — меняй и конвейер B1/B2 (partner-catalog.js, сид-скрипт).

import { ydbClient } from './ydb-client.js';

const PRODUCTS_TABLE = 'products';
const DIMENSION_TOLERANCE = 0.15; // ±15% по плану B5
const PAGE_LIMIT = 100;
const MAX_PAGES = 8;
const CANDIDATE_TARGET = 40;

const DIMENSION_FIELDS = ['width_cm', 'depth_cm', 'height_cm'];

/**
 * Ищет товары каталога по категории/стилю/габаритам.
 * Все параметры опциональны: заданные попадают в FilterExpression (сторона YDB),
 * ранжирование по близости габаритов — уже в Node по малому набору кандидатов.
 *
 * @param {object} params
 * @param {string} [params.category] — например 'sofa', 'bed', 'table'
 * @param {string} [params.style] — например 'scandinavian', 'loft'
 * @param {number} [params.widthCm] — целевая ширина, см
 * @param {number} [params.depthCm] — целевая глубина, см
 * @param {number} [params.heightCm] — целевая высота, см
 * @param {number} [params.topK=10]
 * @param {number} [params.tolerance=0.15] — допуск по габаритам (доля)
 * @returns {Promise<object[]>} записи каталога, ближайшие по габаритам — первыми
 */
export async function searchCatalog(params = {}) {
    const { category, style, topK = 10, tolerance = DIMENSION_TOLERANCE } = params;
    const targets = {
        width_cm: params.widthCm,
        depth_cm: params.depthCm,
        height_cm: params.heightCm,
    };

    try {
        const filter = buildFilter({ category, style, targets, tolerance });
        const candidates = await ydbClient.scanFiltered(PRODUCTS_TABLE, {
            ...filter,
            pageLimit: PAGE_LIMIT,
            maxPages: MAX_PAGES,
            targetCount: CANDIDATE_TARGET,
        });
        return rankByDimensions(candidates, targets).slice(0, topK);
    } catch (err) {
        console.error('[catalog] search failed (non-fatal):', err.message);
        return [];
    }
}

/**
 * Собирает FilterExpression из заданных параметров.
 * Только базовые операторы (=, >=, <=, AND): расширенный синтаксис DynamoDB
 * (BETWEEN, contains) в документации Yandex Document API не подтверждён.
 * Все атрибуты — через #алиасы (см. комментарий в ydbClient.scanFiltered).
 */
function buildFilter({ category, style, targets, tolerance }) {
    const parts = [];
    const names = {};
    const values = {};

    if (category) {
        parts.push('#category = :category');
        names['#category'] = 'category';
        values.category = category;
    }
    if (style) {
        parts.push('#style = :style');
        names['#style'] = 'style';
        values.style = style;
    }
    for (const field of DIMENSION_FIELDS) {
        const target = targets[field];
        if (typeof target !== 'number' || !Number.isFinite(target) || target <= 0) continue;
        const alias = `#${field}`;
        parts.push(`${alias} >= :${field}_min AND ${alias} <= :${field}_max`);
        names[alias] = field;
        values[`${field}_min`] = Math.floor(target * (1 - tolerance));
        values[`${field}_max`] = Math.ceil(target * (1 + tolerance));
    }

    if (parts.length === 0) return {};
    return { filterExpression: parts.join(' AND '), names, values };
}

/**
 * Ранжирует кандидатов по суммарному относительному отклонению габаритов
 * от целевых (меньше — лучше). Без целевых габаритов порядок не меняется.
 */
function rankByDimensions(items, targets) {
    const activeFields = DIMENSION_FIELDS.filter(
        f => typeof targets[f] === 'number' && Number.isFinite(targets[f]) && targets[f] > 0
    );
    if (activeFields.length === 0) return items;

    return items
        .map(item => {
            let deviation = 0;
            for (const field of activeFields) {
                const actual = typeof item[field] === 'number' ? item[field] : targets[field];
                deviation += Math.abs(actual - targets[field]) / targets[field];
            }
            return { item, deviation };
        })
        .sort((a, b) => a.deviation - b.deviation)
        .map(entry => entry.item);
}
