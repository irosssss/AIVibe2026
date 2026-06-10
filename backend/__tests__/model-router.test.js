// backend/__tests__/model-router.test.js
// Тесты B7: гибрид Lite+Pro — роутер выбора модели (B7.1), выбор modelUri
// в провайдере (B7.2), проброс model/usage через triplex-fallback (B7.3).
// node --test, fetch мокается.

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { selectModel, MODEL_PRO, MODEL_LITE } from '../shared/model-router.js';
import { callYandexGPT } from '../shared/yandexgpt.js';
import { triplexFallback } from '../shared/triplex-fallback.js';

const realFetch = globalThis.fetch;

beforeEach(() => {
    process.env.YANDEX_IAM_TOKEN = 'test-iam';
});

afterEach(() => {
    globalThis.fetch = realFetch;
});

/**
 * Мок fetch: metadata падает (env-fallback IAM), completion API отдаёт
 * заданный ответ. Возвращает захваченные тела completion-запросов.
 */
function mockCompletionBackend({ text = 'ответ', usage = { inputTextTokens: '10', completionTokens: '20' } } = {}) {
    const completions = [];
    globalThis.fetch = async (url, opts = {}) => {
        const u = String(url);
        if (u.includes('169.254.169.254')) throw new Error('metadata unavailable in tests');
        assert.ok(u.includes('foundationModels/v1/completion'), `неожиданный URL: ${u}`);
        completions.push(JSON.parse(opts.body));
        return {
            ok: true,
            json: async () => ({ result: { alternatives: [{ message: { text } }], usage } }),
        };
    };
    return completions;
}

// ─── B7.1: роутер ────────────────────────────────────────────────

test('selectModel: простой короткий вопрос → lite', () => {
    const route = selectModel('Какой цвет штор подойдёт к серому дивану?');
    assert.equal(route.model, MODEL_LITE);
    assert.equal(route.reason, 'simple_query');
});

test('selectModel: изображение → pro (vision)', () => {
    const route = selectModel('Что на фото?', { hasImage: true });
    assert.equal(route.model, MODEL_PRO);
    assert.equal(route.reason, 'image');
});

test('selectModel: длинный промпт → pro', () => {
    const route = selectModel('а'.repeat(601));
    assert.equal(route.model, MODEL_PRO);
    assert.equal(route.reason, 'long_prompt');
});

test('selectModel: несколько вопросов → pro', () => {
    const route = selectModel('Какой стиль выбрать? И какие шторы повесить?');
    assert.equal(route.model, MODEL_PRO);
    assert.equal(route.reason, 'multi_question');
});

test('selectModel: сложные темы → pro', () => {
    const complex = [
        'Помоги с расстановкой мебели в гостиной',
        'Сделай перепланировку студии',
        'Рассчитай бюджет на ремонт кухни',
        'Подбери мебель на 150 000 ₽',
        'Сравни скандинавский стиль и лофт',
    ];
    for (const prompt of complex) {
        assert.equal(selectModel(prompt).model, MODEL_PRO, `ожидался pro: ${prompt}`);
    }
});

// ─── B7.2: выбор модели в провайдере ─────────────────────────────

test('callYandexGPT: lite → modelUri yandexgpt-lite, pro по умолчанию', async () => {
    const completions = mockCompletionBackend();

    const liteResult = await callYandexGPT({ prompt: 'тест lite', model: 'lite' });
    const defaultResult = await callYandexGPT({ prompt: 'тест default' });

    assert.match(completions[0].modelUri, /\/yandexgpt-lite\/latest$/);
    assert.match(completions[1].modelUri, /\/yandexgpt-5\/latest$/);
    assert.equal(liteResult.model, 'yandexgpt-lite');
    assert.equal(defaultResult.model, 'yandexgpt-5');
});

test('callYandexGPT: неизвестное значение model → безопасный fallback на pro', async () => {
    const completions = mockCompletionBackend();
    await callYandexGPT({ prompt: 'тест', model: 'turbo' });
    assert.match(completions[0].modelUri, /\/yandexgpt-5\/latest$/);
});

// ─── B7.3: проброс model/usage через triplex ─────────────────────

test('triplexFallback: model доезжает до провайдера, usage и model — в результате', async () => {
    const completions = mockCompletionBackend({
        usage: { inputTextTokens: '42', completionTokens: '7' },
    });

    const result = await triplexFallback({ prompt: 'уникальный промпт b7-lite', model: 'lite' });

    assert.match(completions[0].modelUri, /\/yandexgpt-lite\/latest$/);
    assert.equal(result.provider, 'yandexgpt');
    assert.equal(result.model, 'yandexgpt-lite');
    assert.deepEqual(result.usage, { inputTextTokens: '42', completionTokens: '7' });
});
