// backend/__tests__/rag-search.test.js
// Тесты B6: RAG-поиск с пре-фильтром по категории на стороне YDB
// (вместо full-scan 500 + косинус по всем в Node). node --test, fetch мокается.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { searchRAG, enrichPromptWithRAG } from '../shared/rag-search.js';
import { detectCategory, GENERAL_CATEGORY } from '../shared/rag-category.js';
import { getEmbedding } from '../shared/yandexgpt.js';
import { toDynamo } from '../shared/ydb-client.js';

const ENDPOINT = 'https://docapi.test.local/ru-central1/b1g/etn';
const EMBEDDING_URL = 'llm.api.cloud.yandex.net';
const realFetch = globalThis.fetch;

beforeEach(() => {
    process.env.YDB_DOCUMENT_API_ENDPOINT = ENDPOINT;
    process.env.YANDEX_IAM_TOKEN = 'test-iam';
});

afterEach(() => {
    globalThis.fetch = realFetch;
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
});

function chunk(content, embedding, category = 'kitchen') {
    return toDynamo({ content, embedding: JSON.stringify(embedding), category });
}

/**
 * Мок fetch: metadata падает (env-fallback IAM), embedding API отдаёт
 * queryEmbedding, Document API — страницы из очереди.
 * Возвращает захваченные тела Scan-запросов и запросов к embedding API.
 */
function mockRagBackend({ queryEmbedding, pages, embeddingFails = false, embeddingHangs = false }) {
    const scans = [];
    const embeds = [];
    let page = 0;
    globalThis.fetch = async (url, opts = {}) => {
        const u = String(url);
        if (u.includes('169.254.169.254')) throw new Error('metadata unavailable in tests');
        if (u.includes(EMBEDDING_URL)) {
            embeds.push(JSON.parse(opts.body));
            if (embeddingHangs) return new Promise(() => {}); // зависший вызов
            if (embeddingFails) return { ok: false, status: 500 };
            return { ok: true, json: async () => ({ embedding: queryEmbedding }) };
        }
        assert.equal(u, ENDPOINT);
        scans.push(JSON.parse(opts.body));
        const res = pages[Math.min(page, pages.length - 1)];
        page++;
        return { ok: true, json: async () => res };
    };
    return { scans, embeds };
}

// ─── Эвристика категорий ─────────────────────────────────────────

test('detectCategory: стемы покрывают словоформы запросов', () => {
    assert.equal(detectCategory('Какой диван выбрать для гостиной?'), 'living_room');
    assert.equal(detectCategory('обустроить спальню'), 'bedroom');
    assert.equal(detectCategory('Идеи для кухни'), 'kitchen');
    assert.equal(detectCategory('подбери цветовую палитру'), 'color');
    assert.equal(detectCategory('минимализм в интерьере'), GENERAL_CATEGORY);
});

// ─── searchRAG ───────────────────────────────────────────────────

test('searchRAG: тематический запрос фильтруется по категории на стороне YDB', async () => {
    const { scans, embeds } = mockRagBackend({
        queryEmbedding: [1, 0],
        pages: [{ Items: [chunk('про кухню', [1, 0])] }],
    });

    const results = await searchRAG('Идеи для кухни');

    // Запрос кодируется «запросной» моделью двойного энкодера.
    assert.match(embeds[0].modelUri, /\/text-search-query\/latest$/);

    assert.equal(scans.length, 1);
    const body = scans[0];
    assert.equal(body.TableName, 'rag_chunks');
    assert.equal(body.FilterExpression, '#category = :cat OR #category = :gen');
    assert.deepEqual(body.ExpressionAttributeValues, {
        ':cat': { S: 'kitchen' },
        ':gen': { S: 'general' },
    });
    // Тянем только нужные поля — не весь чанк с source_url/created_at.
    assert.equal(body.ProjectionExpression, '#content, #embedding');
    assert.deepEqual(body.ExpressionAttributeNames, {
        '#content': 'content',
        '#embedding': 'embedding',
        '#category': 'category',
    });
    assert.deepEqual(results, ['про кухню']);
});

test('searchRAG: нераспознанная категория → скан без фильтра, но с проекцией', async () => {
    const { scans } = mockRagBackend({
        queryEmbedding: [1, 0],
        pages: [{ Items: [chunk('общий совет', [1, 0], 'general')] }],
    });

    await searchRAG('минимализм в интерьере');

    assert.equal(scans[0].FilterExpression, undefined);
    assert.equal(scans[0].ProjectionExpression, '#content, #embedding');
});

test('searchRAG: ранжирует по косинусной близости и режет topK', async () => {
    mockRagBackend({
        queryEmbedding: [1, 0],
        pages: [{
            Items: [
                chunk('ортогональный', [0, 1]),
                chunk('точное совпадение', [1, 0]),
                chunk('близкий', [0.9, 0.1]),
            ],
        }],
    });

    const results = await searchRAG('Идеи для кухни', 2);
    assert.deepEqual(results, ['точное совпадение', 'близкий']);
});

test('searchRAG: битый эмбеддинг и чужая размерность пропускаются', async () => {
    mockRagBackend({
        queryEmbedding: [1, 0],
        pages: [{
            Items: [
                toDynamo({ content: 'битый', embedding: 'не json', category: 'kitchen' }),
                chunk('другая размерность', [1, 0, 0]),
                chunk('валидный', [1, 0]),
            ],
        }],
    });

    const results = await searchRAG('Идеи для кухни');
    assert.deepEqual(results, ['валидный']);
});

test('searchRAG: ошибка embedding API → пустой результат (non-fatal)', async () => {
    mockRagBackend({ queryEmbedding: [1, 0], pages: [{ Items: [] }], embeddingFails: true });
    const results = await searchRAG('Идеи для кухни');
    assert.deepEqual(results, []);
});

test('searchRAG: YDB не настроен → пустой результат (non-fatal)', async () => {
    delete process.env.YDB_DOCUMENT_API_ENDPOINT;
    mockRagBackend({ queryEmbedding: [1, 0], pages: [] });
    const results = await searchRAG('Идеи для кухни');
    assert.deepEqual(results, []);
});

// ─── Модели двойного энкодера ────────────────────────────────────

test('getEmbedding: документы индексируются моделью text-search-doc', async () => {
    const { embeds } = mockRagBackend({ queryEmbedding: [1, 0], pages: [] });

    await getEmbedding('текст статьи о дизайне', 'doc');
    await getEmbedding('запрос пользователя'); // kind по умолчанию

    assert.match(embeds[0].modelUri, /\/text-search-doc\/latest$/);
    assert.match(embeds[1].modelUri, /\/text-search-query\/latest$/);
});

// ─── enrichPromptWithRAG ─────────────────────────────────────────

test('enrichPromptWithRAG: выдержки в промпте помечены как данные, не инструкции', async () => {
    mockRagBackend({
        queryEmbedding: [1, 0],
        pages: [{ Items: [chunk('Кухонный остров требует 120 см прохода', [1, 0])] }],
    });

    const question = 'Идеи для кухни';
    const { prompt, ragChunks } = await enrichPromptWithRAG(question);

    assert.equal(ragChunks, 1);
    assert.ok(prompt.includes('[1] Кухонный остров требует 120 см прохода'));
    assert.ok(prompt.includes('не инструкции'));
    assert.ok(prompt.endsWith('Вопрос пользователя:\n' + question));
});

test('enrichPromptWithRAG: без находок → исходный промпт без изменений', async () => {
    mockRagBackend({ queryEmbedding: [1, 0], pages: [{ Items: [] }] });

    const { prompt, ragChunks } = await enrichPromptWithRAG('Идеи для кухни');

    assert.equal(ragChunks, 0);
    assert.equal(prompt, 'Идеи для кухни');
});

test('enrichPromptWithRAG: зависший поиск → таймаут → исходный промпт', async () => {
    mockRagBackend({ queryEmbedding: [1, 0], pages: [], embeddingHangs: true });

    const { prompt, ragChunks } = await enrichPromptWithRAG('Идеи для кухни', { timeoutMs: 20 });

    assert.equal(ragChunks, 0);
    assert.equal(prompt, 'Идеи для кухни');
});

test('enrichPromptWithRAG: ошибка RAG → исходный промпт (non-fatal)', async () => {
    mockRagBackend({ queryEmbedding: [1, 0], pages: [], embeddingFails: true });

    const { prompt, ragChunks } = await enrichPromptWithRAG('Идеи для кухни');

    assert.equal(ragChunks, 0);
    assert.equal(prompt, 'Идеи для кухни');
});
