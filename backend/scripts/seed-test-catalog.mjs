#!/usr/bin/env node
// backend/scripts/seed-test-catalog.mjs
// Тестовое наполнение партнёрского каталога (таблица YDB `products`, B1/B2).
//
// Решение владельца (2026-06-10): B2–B4 строим на тестовом каталоге, не дожидаясь
// фабрик; товары реальных партнёров зальются конвейером B1 в тот же контракт.
//
// usdz_url указывает на будущий бакет Object Storage (CATALOG_MODELS_BASE_URL):
// файлов там пока нет — приложение в этом случае рендерит placeholder-бокс,
// то есть поведение не хуже текущего. Когда конвейер B1 сконвертирует первые
// реальные модели, файлы лягут по этим же путям без правки каталога.
//
// Запуск (нужны переменные окружения):
//   YDB_DOCUMENT_API_ENDPOINT — endpoint Document API таблицы products
//   YANDEX_IAM_TOKEN          — IAM-токен (локально) ИЛИ запуск из облака (metadata)
//   CATALOG_MODELS_BASE_URL   — (опц.) база ссылок на модели, по умолчанию
//                               https://storage.yandexcloud.net/aivibe-models/test
//
//   node backend/scripts/seed-test-catalog.mjs            # записать в YDB
//   node backend/scripts/seed-test-catalog.mjs --dry-run  # показать без записи
//
// Контракт полей — backend/shared/catalog-search.js. Категории — канон из
// backend/shared/partner-catalog.js (CATEGORY_STEMS).

import { ydbClient } from '../shared/ydb-client.js';

const PRODUCTS_TABLE = 'products';
const MODELS_BASE = (process.env.CATALOG_MODELS_BASE_URL
    ?? 'https://storage.yandexcloud.net/aivibe-models/test').replace(/\/$/, '');
const PARTNER_BASE = 'https://partner-demo.aivibe.test/p';

// article, name, category, style, Ш×Г×В (см), цена ₽
const FIXTURE = [
    ['TEST-SOFA-001', 'Диван трёхместный «Осло»', 'sofa', 'scandinavian', 220, 95, 80, 64900],
    ['TEST-SOFA-002', 'Диван двухместный «Берген»', 'sofa', 'scandinavian', 180, 90, 78, 48900],
    ['TEST-SOFA-003', 'Диван угловой «Лофт Индастри»', 'sofa', 'loft', 260, 160, 75, 89900],
    ['TEST-SOFA-004', 'Софа компактная «Минима»', 'sofa', 'minimalist', 160, 85, 72, 39900],
    ['TEST-BED-001', 'Кровать двуспальная «Сканди» 160', 'bed', 'scandinavian', 165, 206, 95, 54900],
    ['TEST-BED-002', 'Кровать «Лофт» 140 с изголовьем', 'bed', 'loft', 145, 205, 100, 46900],
    ['TEST-BED-003', 'Кровать классическая «Усадьба» 180', 'bed', 'classic_russian', 185, 210, 120, 84900],
    ['TEST-ARMCH-001', 'Кресло «Полярис» с подлокотниками', 'armchair', 'scandinavian', 80, 85, 100, 24900],
    ['TEST-ARMCH-002', 'Кресло-кокон «Минима Софт»', 'armchair', 'minimalist', 75, 80, 95, 21900],
    ['TEST-CHAIR-001', 'Стул обеденный «Сканди Вуд»', 'chair', 'scandinavian', 45, 52, 82, 6900],
    ['TEST-CHAIR-002', 'Стул барный «Индастри»', 'chair', 'loft', 40, 40, 105, 8900],
    ['TEST-CHAIR-003', 'Табурет складной «Компакт»', 'chair', 'minimalist', 35, 35, 45, 2900],
    ['TEST-TABLE-001', 'Стол обеденный «Осло» 140', 'table', 'scandinavian', 140, 80, 75, 32900],
    ['TEST-TABLE-002', 'Стол журнальный «Лофт Куб»', 'table', 'loft', 80, 80, 45, 14900],
    ['TEST-TABLE-003', 'Стол письменный «Минима Воркс»', 'table', 'minimalist', 120, 60, 74, 19900],
    ['TEST-WARD-001', 'Шкаф трёхдверный «Сканди» с зеркалом', 'wardrobe', 'scandinavian', 150, 58, 210, 49900],
    ['TEST-WARD-002', 'Гардероб открытый «Индастри Рэк»', 'wardrobe', 'loft', 120, 50, 180, 27900],
    ['TEST-WARD-003', 'Комод четыре ящика «Минима»', 'wardrobe', 'minimalist', 90, 45, 95, 18900],
    ['TEST-SHELF-001', 'Стеллаж пятиярусный «Лофт Грид»', 'shelf', 'loft', 80, 35, 185, 16900],
    ['TEST-SHELF-002', 'Полка настенная «Сканди Лайн»', 'shelf', 'scandinavian', 90, 22, 25, 4900],
    ['TEST-CAB-001', 'Тумба под ТВ «Осло Медиа»', 'cabinet', 'scandinavian', 160, 40, 50, 22900],
    ['TEST-CAB-002', 'Тумба прикроватная «Минима Найт»', 'cabinet', 'minimalist', 45, 40, 55, 7900],
    ['TEST-LAMP-001', 'Торшер «Сканди Глоу»', 'lamp', 'scandinavian', 35, 35, 150, 8900],
    ['TEST-LAMP-002', 'Светильник подвесной «Индастри Эдисон»', 'lamp', 'loft', 25, 25, 40, 5900],
    ['TEST-CARP-001', 'Ковёр шерстяной «Усадьба» 200×300', 'carpet', 'classic_russian', 200, 300, 2, 34900],
    ['TEST-CARP-002', 'Ковёр короткий ворс «Минима Грей» 160×230', 'carpet', 'minimalist', 160, 230, 1, 12900],
];

function toProduct([article, name, category, style, widthCm, depthCm, heightCm, price]) {
    return {
        article,
        name,
        category,
        style,
        width_cm: widthCm,
        depth_cm: depthCm,
        height_cm: heightCm,
        price,
        usdz_url: `${MODELS_BASE}/${article}.usdz`,
        product_url: `${PARTNER_BASE}/${article}`,
    };
}

const dryRun = process.argv.includes('--dry-run');
const products = FIXTURE.map(toProduct);

if (dryRun) {
    console.log(JSON.stringify(products, null, 2));
    console.log(`— dry-run: ${products.length} товаров, запись в YDB не выполнялась`);
    process.exit(0);
}

if (!process.env.YDB_DOCUMENT_API_ENDPOINT) {
    console.error('✗ YDB_DOCUMENT_API_ENDPOINT не задан — записывать некуда.');
    console.error('  Подсказка: посмотреть товары без записи — флаг --dry-run');
    process.exit(1);
}

let written = 0;
const failed = [];
for (const item of products) {
    try {
        const res = await ydbClient.upsert(PRODUCTS_TABLE, item);
        if (res.skipped) throw new Error('YDB не настроен (endpoint пуст)');
        written++;
        console.log(`✓ ${item.article} — ${item.name}`);
    } catch (err) {
        failed.push(item.article);
        console.error(`✗ ${item.article}: ${err.message}`);
    }
}

console.log(`\nИтог: записано ${written}/${products.length}` +
    (failed.length ? `, ошибки: ${failed.join(', ')}` : ''));
process.exit(failed.length ? 1 : 0);
