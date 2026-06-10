// backend/__tests__/ydb-client.test.js
// Тесты расширения ydb-client (B5): scanFiltered (фильтр на стороне YDB,
// пагинация, потолки) и query. node --test, fetch мокается.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { ydbClient, toDynamo, fromDynamo, toExpressionValues } from '../shared/ydb-client.js';

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

/**
 * Мок fetch: metadata service падает (getIamToken уходит в env-fallback),
 * запросы к Document API получают ответы из очереди pages.
 * Возвращает массив захваченных тел запросов к Document API.
 */
function mockDocApi(pages) {
    const captured = [];
    let i = 0;
    globalThis.fetch = async (url, opts = {}) => {
        if (String(url).includes('169.254.169.254')) {
            throw new Error('metadata unavailable in tests');
        }
        assert.equal(url, ENDPOINT);
        captured.push({
            target: opts.headers?.['X-Amz-Target'],
            body: JSON.parse(opts.body),
        });
        const page = pages[Math.min(i, pages.length - 1)];
        i++;
        return { ok: true, json: async () => page };
    };
    return captured;
}

function dynamoItem(obj) {
    return toDynamo(obj);
}

// ─── Сериализация ────────────────────────────────────────────────

test('toExpressionValues: примитивы → плейсхолдеры с типами', () => {
    assert.deepEqual(
        toExpressionValues({ cat: 'kitchen', wmin: 170, flag: true, ':явный': 'x' }),
        {
            ':cat': { S: 'kitchen' },
            ':wmin': { N: '170' },
            ':flag': { BOOL: true },
            ':явный': { S: 'x' },
        }
    );
});

test('toExpressionValues: сложный тип → ошибка (не молчаливый stringify)', () => {
    assert.throws(() => toExpressionValues({ bad: { nested: 1 } }), /неподдерживаемый тип/);
});

test('toDynamo/fromDynamo: round-trip примитивов', () => {
    const src = { s: 'строка', n: 42, b: false, nil: null };
    assert.deepEqual(fromDynamo(toDynamo(src)), src);
});

// ─── scanFiltered ────────────────────────────────────────────────

test('scanFiltered: тело запроса содержит фильтр, алиасы и проекцию', async () => {
    const captured = mockDocApi([{ Items: [dynamoItem({ id: '1', content: 'a' })] }]);

    const items = await ydbClient.scanFiltered('rag_chunks', {
        filterExpression: '#category = :cat',
        values: { cat: 'kitchen' },
        names: { '#category': 'category' },
        projection: '#content',
        pageLimit: 64,
    });

    assert.equal(captured.length, 1);
    assert.equal(captured[0].target, 'DynamoDB_20120810.Scan');
    const body = captured[0].body;
    assert.equal(body.TableName, 'rag_chunks');
    assert.equal(body.Limit, 64);
    assert.equal(body.FilterExpression, '#category = :cat');
    assert.deepEqual(body.ExpressionAttributeValues, { ':cat': { S: 'kitchen' } });
    assert.deepEqual(body.ExpressionAttributeNames, { '#category': 'category' });
    assert.equal(body.ProjectionExpression, '#content');
    assert.deepEqual(items, [{ id: '1', content: 'a' }]);
});

test('scanFiltered: без фильтра не шлёт Expression-поля', async () => {
    const captured = mockDocApi([{ Items: [] }]);
    await ydbClient.scanFiltered('rag_chunks', {});
    const body = captured[0].body;
    assert.equal(body.FilterExpression, undefined);
    assert.equal(body.ExpressionAttributeValues, undefined);
    assert.equal(body.ExpressionAttributeNames, undefined);
    assert.equal(body.ProjectionExpression, undefined);
});

test('scanFiltered: идёт по страницам через LastEvaluatedKey и склеивает результат', async () => {
    const captured = mockDocApi([
        { Items: [dynamoItem({ id: '1' })], LastEvaluatedKey: { id: { S: '1' } } },
        { Items: [dynamoItem({ id: '2' })] }, // нет LastEvaluatedKey — конец таблицы
    ]);

    const items = await ydbClient.scanFiltered('t', { targetCount: 50 });

    assert.equal(captured.length, 2);
    assert.equal(captured[0].body.ExclusiveStartKey, undefined);
    assert.deepEqual(captured[1].body.ExclusiveStartKey, { id: { S: '1' } });
    assert.deepEqual(items.map(i => i.id), ['1', '2']);
});

test('scanFiltered: досрочный выход при достижении targetCount', async () => {
    const captured = mockDocApi([
        {
            Items: [dynamoItem({ id: '1' }), dynamoItem({ id: '2' })],
            LastEvaluatedKey: { id: { S: '2' } }, // продолжение есть, но кандидатов хватает
        },
    ]);

    const items = await ydbClient.scanFiltered('t', { targetCount: 2 });

    assert.equal(captured.length, 1);
    assert.equal(items.length, 2);
});

test('scanFiltered: упирается в потолок maxPages', async () => {
    const captured = mockDocApi([
        { Items: [dynamoItem({ id: 'x' })], LastEvaluatedKey: { id: { S: 'x' } } },
    ]);

    const items = await ydbClient.scanFiltered('t', { maxPages: 3, targetCount: 100 });

    assert.equal(captured.length, 3);
    assert.equal(items.length, 3);
});

test('scanFiltered: YDB не настроен → пустой массив без запросов', async () => {
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
    let called = false;
    globalThis.fetch = async () => { called = true; throw new Error('не должно вызываться'); };

    const items = await ydbClient.scanFiltered('t', {});
    assert.deepEqual(items, []);
    assert.equal(called, false);
});

test('scanFiltered: HTTP-ошибка Document API пробрасывается', async () => {
    globalThis.fetch = async url => {
        if (String(url).includes('169.254.169.254')) throw new Error('no metadata');
        return { ok: false, status: 400, text: async () => 'ValidationException' };
    };

    await assert.rejects(
        () => ydbClient.scanFiltered('t', {}),
        /YDB Scan HTTP 400/
    );
});

// ─── query ───────────────────────────────────────────────────────

test('query: тело запроса содержит KeyConditionExpression и IndexName', async () => {
    const captured = mockDocApi([{ Items: [dynamoItem({ article: 'A-1' })] }]);

    const items = await ydbClient.query('products', {
        keyConditionExpression: '#category = :cat',
        values: { cat: 'sofa' },
        names: { '#category': 'category' },
        indexName: 'category_index',
        limit: 20,
    });

    assert.equal(captured[0].target, 'DynamoDB_20120810.Query');
    const body = captured[0].body;
    assert.equal(body.TableName, 'products');
    assert.equal(body.KeyConditionExpression, '#category = :cat');
    assert.deepEqual(body.ExpressionAttributeValues, { ':cat': { S: 'sofa' } });
    assert.equal(body.IndexName, 'category_index');
    assert.equal(body.Limit, 20);
    assert.deepEqual(items, [{ article: 'A-1' }]);
});

test('query: без keyConditionExpression → ошибка', async () => {
    await assert.rejects(() => ydbClient.query('products', {}), /keyConditionExpression/);
});

test('query: YDB не настроен → пустой массив', async () => {
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
    const items = await ydbClient.query('products', {
        keyConditionExpression: '#a = :a',
        values: { a: '1' },
    });
    assert.deepEqual(items, []);
});
