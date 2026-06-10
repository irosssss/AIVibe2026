// yandexgpt.js — Клиент YandexGPT для Yandex Cloud Functions
// Endpoint: https://llm.api.cloud.yandex.net/foundationModels/v1/completion
// Модель: gpt://{folder-id}/yandexgpt/latest (флагман 5-го поколения; имени «yandexgpt-5» в API нет)
// Auth: IAM-токен из metadata service (свежий токен без ручного обновления).

import { getSecrets } from './secrets.js';

// ─── IAM-токен через metadata service ────────────────────────────
// Когда Cloud Function запущена с привязанным сервисным аккаунтом,
// внутри неё доступен metadata service, который всегда отдаёт свежий
// IAM-токен. Так уходит проблема "токен протух через 12 часов".
const METADATA_TOKEN_URL =
    'http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token';

// Кэш в памяти модуля (живёт между вызовами в рамках одного инстанса функции).
let _iamCache = { token: null, expiresAt: 0 };

/**
 * Возвращает актуальный IAM-токен.
 * Источник логируется: '[iam] source: metadata | cache | env'.
 *   - metadata: свежий токен из Yandex Cloud metadata service
 *   - cache:    валидный токен из памяти (запас 2 минуты до истечения)
 *   - env:      fallback на process.env.YANDEX_IAM_TOKEN (локальная разработка)
 * @returns {Promise<string>}
 */
export async function getIamToken() {
    // 1. Свежий кэш — отдаём сразу (запас 2 минуты до истечения)
    if (_iamCache.token && _iamCache.expiresAt > Date.now() + 120_000) {
        console.log('[iam] source:', 'cache');
        return _iamCache.token;
    }

    // 2. Пытаемся получить свежий токен из metadata service
    try {
        const res = await fetch(METADATA_TOKEN_URL, {
            headers: { 'Metadata-Flavor': 'Google' },
            signal: AbortSignal.timeout(3000),
        });
        if (!res.ok) throw new Error(`metadata HTTP ${res.status}`);

        const data = await res.json();
        if (!data.access_token) throw new Error('metadata: no access_token in response');
        const ttlMs = (data.expires_in ?? 3600) * 1000;
        _iamCache = { token: data.access_token, expiresAt: Date.now() + ttlMs };
        console.log('[iam] source:', 'metadata');
        return _iamCache.token;
    } catch (e) {
        // 3. Fallback: вне Cloud Functions (локально) metadata недоступен
        console.warn(
            '[iam] metadata service unavailable, falling back to env:',
            (e && e.message) || 'unknown'
        );
        console.log('[iam] source:', 'env');
        return process.env.YANDEX_IAM_TOKEN || '';
    }
}

// B7.2: гибрид Lite+Pro. Решение, какую модель брать, принимает роутер
// (shared/model-router.js) — здесь только маппинг на имя модели Яндекса.
const GPT_MODELS = {
    pro: 'yandexgpt',
    lite: 'yandexgpt-lite',
};

/**
 * Вызвать YandexGPT с triplex fallback-совместимым форматом
 * @param {object} options
 * @param {string} options.prompt — текстовый промпт
 * @param {string} [options.imageBase64] — base64 изображения (для vision)
 * @param {number} [options.timeoutMs=25000] — таймаут (мс)
 * @param {'pro'|'lite'} [options.model='pro'] — выбор модели (B7, роутер)
 * @returns {Promise<{text: string, provider: string, model: string, usage: object}>}
 */
export async function callYandexGPT({ prompt, imageBase64, timeoutMs = 25000, model = 'pro' }) {
    const secrets = await getSecrets();
    const folderId = secrets.YANDEXGPT_FOLDER_ID;
    const iamToken = await getIamToken();

    // Родной API Яндекса ждёт поле text, не content (OpenAI-стиль давал
    // HTTP 400 «Error in session» — проверено живым вызовом при первом деплое).
    const messages = [{ role: 'user', text: prompt }];

    // Изображение: native completion API картинки не принимает — описываем факт
    // наличия в тексте, чтобы запрос не падал. Полноценный vision —
    // отдельной задачей (OpenAI-совместимый эндпоинт или VLM API).
    if (imageBase64) {
        messages[0].text = `${prompt}\n\n[К запросу приложено фото комнаты — анализ изображения временно недоступен, отвечай по тексту.]`;
    }

    const modelName = GPT_MODELS[model] || GPT_MODELS.pro;
    const body = {
        modelUri: `gpt://${folderId}/${modelName}/latest`,
        completionOptions: {
            stream: false,
            temperature: 0.7,
            maxTokens: 2000
        },
        messages
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    try {
        const response = await fetch(
            'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${iamToken}`,
                    'x-folder-id': folderId
                },
                body: JSON.stringify(body),
                signal: controller.signal
            }
        );

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`YandexGPT HTTP ${response.status}: ${errorText}`);
        }

        const data = await response.json();
        const text = data.result?.alternatives?.[0]?.message?.text || '';

        return {
            text,
            provider: 'yandexgpt',
            model: modelName,
            usage: data.result?.usage || {}
        };
    } finally {
        clearTimeout(timeout);
    }
}

// Двойной энкодер Яндекса: документы и запросы кодируются разными моделями
// в общее векторное пространство. Документы — text-search-doc, запросы —
// text-search-query (рекомендация Yandex Foundation Models для поиска).
const EMBEDDING_MODELS = {
    query: 'text-search-query',
    doc: 'text-search-doc',
};

/**
 * Получить embedding вектора для RAG.
 * @param {string} text — текст для эмбеддинга
 * @param {'query'|'doc'} [kind='query'] — 'doc' при индексации документов
 *   (rag-indexer), 'query' при поиске (rag-search)
 * @returns {Promise<number[]>}
 */
export async function getEmbedding(text, kind = 'query') {
    const secrets = await getSecrets();
    const folderId = secrets.YANDEXGPT_FOLDER_ID;
    const iamToken = await getIamToken();

    const response = await fetch(
        'https://llm.api.cloud.yandex.net/foundationModels/v1/textEmbedding',
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${iamToken}`,
                'x-folder-id': folderId
            },
            body: JSON.stringify({
                modelUri: `emb://${folderId}/${EMBEDDING_MODELS[kind] || EMBEDDING_MODELS.query}/latest`,
                text: text
            })
        }
    );

    if (!response.ok) {
        throw new Error(`Embedding API error: ${response.status}`);
    }

    const data = await response.json();
    return data.embedding;
}
