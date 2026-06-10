// backend/__tests__/partner-catalog.test.js
// Тесты B2/B3: партнёрский каталог как источник маркетплейса (фичефлаг
// CATALOG_SOURCE) и резолвер артикулов (action='resolve').

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { toDynamo } from '../shared/ydb-client.js';
import {
    detectFurnitureCategory,
    toMarketplaceProduct,
    searchPartnerCatalog,
    resolveArticle,
} from '../shared/partner-catalog.js';
import { handler } from '../functions/marketplace/index.js';

const ENDPOINT = 'https://docapi.test.local/ru-central1/b1g/etn';
const APP_TOKEN = 'test-app-token';
const realFetch = globalThis.fetch;

beforeEach(() => {
    process.env.YDB_DOCUMENT_API_ENDPOINT = ENDPOINT;
    process.env.YANDEX_IAM_TOKEN = 'test-iam';
    process.env.APP_TOKEN = APP_TOKEN;
});

afterEach(() => {
    globalThis.fetch = realFetch;
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
    delete process.env.CATALOG_SOURCE;
});

function record(article, extra = {}) {
    return {
        article,
        name: `Товар ${article}`,
        category: 'sofa',
        style: 'loft',
        width_cm: 200,
        depth_cm: 90,
        height_cm: 80,
        price: 49900,
        usdz_url: `https://storage.test/models/${article}.usdz`,
        product_url: `https://partner.test/p/${article}`,
        ...extra,
    };
}

// Последовательные ответы Document API; все прочие URL (Apify, LLM) бросают —
// best-effort-обвязки (enrich) это глотают, а неожиданные вызовы валят тест.
function mockYdb(responses) {
    const calls = [];
    let i = 0;
    globalThis.fetch = async (url, opts = {}) => {
        if (String(url) !== ENDPOINT) throw new Error(`нет сети в тестах: ${url}`);
        calls.push({ target: opts.headers?.['X-Amz-Target'], body: JSON.parse(opts.body) });
        const res = responses[Math.min(i, responses.length - 1)];
        i++;
        return { ok: true, json: async () => res };
    };
    return calls;
}

function searchEvent(body) {
    return {
        httpMethod: 'POST',
        headers: { 'x-app-token': APP_TOKEN },
        body: JSON.stringify(body),
    };
}

// ─── detectFurnitureCategory ─────────────────────────────────────

test('detectFurnitureCategory: стемы покрывают словоформы', () => {
    assert.equal(detectFurnitureCategory('серый диван в гостиную'), 'sofa');
    assert.equal(detectFurnitureCategory('интересуюсь кроватью 160'), 'bed');
    assert.equal(detectFurnitureCategory('торшер к креслу'), 'armchair'); // кресл раньше lamp в каноне
    assert.equal(detectFurnitureCategory('шкаф-купе'), 'wardrobe');
    assert.equal(detectFurnitureCategory('Ковёр в спальню'), 'carpet');
});

test('detectFurnitureCategory: сравнение по началу слова, не по подстроке', () => {
    // «выбрать»/«столько» не должны давать ложных категорий по подстрокам
    assert.equal(detectFurnitureCategory('что выбрать недорого'), null);
    assert.equal(detectFurnitureCategory(''), null);
    assert.equal(detectFurnitureCategory(undefined), null);
});

// ─── toMarketplaceProduct ────────────────────────────────────────

test('toMarketplaceProduct: формат products + marketplace=partner', () => {
    const product = toMarketplaceProduct(record('TEST-1'));
    assert.deepEqual(product, {
        name: 'Товар TEST-1',
        price: 49900,
        url: 'https://partner.test/p/TEST-1',
        imageUrl: '',
        marketplace: 'partner',
        article: 'TEST-1',
        usdzUrl: 'https://storage.test/models/TEST-1.usdz',
        category: 'sofa',
        style: 'loft',
    });
});

test('toMarketplaceProduct: битые поля не ломают формат', () => {
    const product = toMarketplaceProduct({ article: 42, price: 'дорого' });
    assert.equal(product.article, '42');
    assert.equal(product.price, null);
    assert.equal(product.name, 'Без названия');
});

// ─── searchPartnerCatalog ────────────────────────────────────────

test('searchPartnerCatalog: категория из запроса попадает в фильтр, выдача нормализована', async () => {
    const calls = mockYdb([{ Items: [toDynamo(record('TEST-1'))] }]);

    const products = await searchPartnerCatalog({ query: 'диван для гостиной', style: 'loft' });

    assert.equal(calls[0].target, 'DynamoDB_20120810.Scan');
    assert.match(calls[0].body.FilterExpression, /#category = :category/);
    assert.equal(calls[0].body.ExpressionAttributeValues[':category'].S, 'sofa');
    assert.equal(products.length, 1);
    assert.equal(products[0].marketplace, 'partner');
});

test('searchPartnerCatalog: пустая выдача со стилем → повтор без стиля (каталог маленький)', async () => {
    const calls = mockYdb([
        { Items: [] },
        { Items: [toDynamo(record('TEST-2', { style: 'scandinavian' }))] },
    ]);

    const products = await searchPartnerCatalog({ query: 'диван', style: 'loft' });

    assert.equal(calls.length, 2);
    assert.match(calls[0].body.FilterExpression, /#style = :style/);
    assert.doesNotMatch(calls[1].body.FilterExpression, /#style/);
    assert.equal(products.length, 1);
    assert.equal(products[0].article, 'TEST-2');
});

// ─── resolveArticle ──────────────────────────────────────────────

test('resolveArticle: GetItem по артикулу, ответ нормализован', async () => {
    const calls = mockYdb([{ Item: toDynamo(record('TEST-SOFA-001')) }]);

    const product = await resolveArticle('TEST-SOFA-001');

    assert.equal(calls[0].target, 'DynamoDB_20120810.GetItem');
    assert.deepEqual(calls[0].body.Key, { article: { S: 'TEST-SOFA-001' } });
    assert.equal(product.usdzUrl, 'https://storage.test/models/TEST-SOFA-001.usdz');
    assert.equal(product.marketplace, 'partner');
});

test('resolveArticle: некорректный формат артикула → null без обращения к YDB', async () => {
    const calls = mockYdb([{}]);
    assert.equal(await resolveArticle('../etc/passwd'), null);
    assert.equal(await resolveArticle(''), null);
    assert.equal(await resolveArticle(42), null);
    assert.equal(calls.length, 0);
});

test('resolveArticle: не найден → null', async () => {
    mockYdb([{}]); // GetItem без Item
    assert.equal(await resolveArticle('TEST-NOPE-404'), null);
});

// ─── handler: фичефлаг CATALOG_SOURCE ────────────────────────────

test('handler: CATALOG_SOURCE=partner → товары из каталога, источник partner', async () => {
    process.env.CATALOG_SOURCE = 'partner';
    mockYdb([{ Items: [toDynamo(record('TEST-1'))] }]);

    const res = await handler(searchEvent({ query: 'диван', userId: 'u-b2-partner' }));
    const body = JSON.parse(res.body);

    assert.equal(res.statusCode, 200);
    assert.deepEqual(body.marketplace_sources, { partner: 1 });
    assert.equal(body.products[0].marketplace, 'partner');
    assert.equal(body.products[0].usdzUrl, 'https://storage.test/models/TEST-1.usdz');
});

test('handler: флаг выключен → путь Apify (источники wildberries/ozon)', async () => {
    delete process.env.CATALOG_SOURCE;
    mockYdb([{}]); // любые сетевые вызовы (Apify) бросают → акторы дают пустую выдачу

    const res = await handler(searchEvent({ query: 'диван', userId: 'u-b2-apify' }));
    const body = JSON.parse(res.body);

    assert.equal(res.statusCode, 200);
    assert.deepEqual(body.marketplace_sources, { wildberries: 0, ozon: 0 });
    assert.deepEqual(body.products, []);
});

// ─── handler: action=resolve (B3) ────────────────────────────────

test('handler resolve: найденный артикул → 200 с product', async () => {
    mockYdb([{ Item: toDynamo(record('TEST-SOFA-001')) }]);

    const res = await handler(searchEvent({
        action: 'resolve',
        article: 'TEST-SOFA-001',
        userId: 'u-b3-found',
    }));
    const body = JSON.parse(res.body);

    assert.equal(res.statusCode, 200);
    assert.equal(body.product.article, 'TEST-SOFA-001');
    assert.equal(body.product.price, 49900);
});

test('handler resolve: неизвестный артикул → 404', async () => {
    mockYdb([{}]);

    const res = await handler(searchEvent({
        action: 'resolve',
        article: 'TEST-NOPE-404',
        userId: 'u-b3-missing',
    }));

    assert.equal(res.statusCode, 404);
});

test('handler resolve: без article → 400', async () => {
    mockYdb([{}]);

    const res = await handler(searchEvent({ action: 'resolve', userId: 'u-b3-no-article' }));

    assert.equal(res.statusCode, 400);
});
