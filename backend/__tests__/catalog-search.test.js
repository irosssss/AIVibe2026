// backend/__tests__/catalog-search.test.js
// Тесты B5: поиск по партнёрскому каталогу — пре-фильтр (категория + стиль +
// габариты ±15%) на стороне YDB, ранжирование по габаритам в Node.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { searchCatalog } from '../shared/catalog-search.js';
import { toDynamo } from '../shared/ydb-client.js';

const ENDPOINT = 'https://docapi.test.local/ru-central1/b1g/etn';
const realFetch = globalThis.fetch;

beforeEach(() => {
    process.env.YDB_DOCUMENT_API_ENDPOINT = ENDPOINT;
    process.env.YANDEX_IAM_TOKEN = 'test-iam';
});

afterEach(() => {
    globalThis.fetch = realFetch;
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
});

function product(article, dims = {}) {
    return toDynamo({
        article,
        name: `Товар ${article}`,
        category: 'sofa',
        style: 'loft',
        width_cm: dims.w ?? 200,
        depth_cm: dims.d ?? 90,
        height_cm: dims.h ?? 80,
        price: 49900,
        usdz_url: `https://storage.test/models/${article}.usdz`,
        product_url: `https://partner.test/p/${article}`,
    });
}

function mockCatalog(pages) {
    const scans = [];
    let page = 0;
    globalThis.fetch = async (url, opts = {}) => {
        if (String(url).includes('169.254.169.254')) throw new Error('metadata unavailable in tests');
        assert.equal(String(url), ENDPOINT);
        scans.push(JSON.parse(opts.body));
        const res = pages[Math.min(page, pages.length - 1)];
        page++;
        return { ok: true, json: async () => res };
    };
    return scans;
}

test('searchCatalog: фильтр собирается из категории, стиля и габаритов ±15%', async () => {
    const scans = mockCatalog([{ Items: [product('A-1')] }]);

    await searchCatalog({ category: 'sofa', style: 'loft', widthCm: 200 });

    const body = scans[0];
    assert.equal(body.TableName, 'products');
    assert.equal(
        body.FilterExpression,
        '#category = :category AND #style = :style AND #width_cm >= :width_cm_min AND #width_cm <= :width_cm_max'
    );
    assert.deepEqual(body.ExpressionAttributeNames, {
        '#category': 'category',
        '#style': 'style',
        '#width_cm': 'width_cm',
    });
    // 200 ± 15% → 170..230
    assert.deepEqual(body.ExpressionAttributeValues, {
        ':category': { S: 'sofa' },
        ':style': { S: 'loft' },
        ':width_cm_min': { N: '170' },
        ':width_cm_max': { N: '230' },
    });
});

test('searchCatalog: без параметров — скан без фильтра (потолки страниц остаются)', async () => {
    const scans = mockCatalog([{ Items: [] }]);
    await searchCatalog();
    assert.equal(scans[0].FilterExpression, undefined);
    assert.equal(scans[0].Limit, 100);
});

test('searchCatalog: ранжирует по близости габаритов и режет topK', async () => {
    mockCatalog([{
        Items: [
            product('далёкий', { w: 228 }),
            product('точный', { w: 200 }),
            product('близкий', { w: 205 }),
        ],
    }]);

    const results = await searchCatalog({ widthCm: 200, topK: 2 });
    assert.deepEqual(results.map(r => r.article), ['точный', 'близкий']);
});

test('searchCatalog: запись каталога возвращается целиком (контракт B2/B3)', async () => {
    mockCatalog([{ Items: [product('A-1', { w: 200 })] }]);

    const [item] = await searchCatalog({ category: 'sofa' });
    assert.equal(item.article, 'A-1');
    assert.equal(item.usdz_url, 'https://storage.test/models/A-1.usdz');
    assert.equal(item.price, 49900);
    assert.equal(item.product_url, 'https://partner.test/p/A-1');
});

test('searchCatalog: некорректные габариты (0, NaN) не попадают в фильтр', async () => {
    const scans = mockCatalog([{ Items: [] }]);
    await searchCatalog({ widthCm: 0, depthCm: Number.NaN, category: 'sofa' });
    assert.equal(scans[0].FilterExpression, '#category = :category');
});

test('searchCatalog: YDB не настроен → пустой результат (non-fatal)', async () => {
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
    globalThis.fetch = async () => { throw new Error('не должно вызываться'); };
    const results = await searchCatalog({ category: 'sofa' });
    assert.deepEqual(results, []);
});

test('searchCatalog: ошибка Document API → пустой результат (non-fatal)', async () => {
    globalThis.fetch = async url => {
        if (String(url).includes('169.254.169.254')) throw new Error('no metadata');
        return { ok: false, status: 500, text: async () => 'InternalError' };
    };
    const results = await searchCatalog({ category: 'sofa' });
    assert.deepEqual(results, []);
});
