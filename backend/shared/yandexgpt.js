// yandexgpt.js — Клиент YandexGPT для Yandex Cloud Functions
// Endpoint: https://llm.api.cloud.yandex.net/foundationModels/v1/completion
// Модель: gpt://{folder-id}/yandexgpt-5/latest
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

/**
 * Вызвать YandexGPT с triplex fallback-совместимым форматом
 * @param {object} options
 * @param {string} options.prompt — текстовый промпт
 * @param {string} [options.imageBase64] — base64 изображения (для vision)
 * @param {number} [options.timeoutMs=25000] — таймаут (мс)
 * @returns {Promise<{text: string, usage: object}>}
 */
export async function callYandexGPT({ prompt, imageBase64, timeoutMs = 25000 }) {
    const secrets = await getSecrets();
    const folderId = secrets.YANDEXGPT_FOLDER_ID;
    const iamToken = await getIamToken();

    const messages = [{ role: 'user', content: prompt }];

    // Если есть изображение — добавляем как multimodal контент
    if (imageBase64) {
        messages[0].content = [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }
        ];
    }

    const body = {
        modelUri: `gpt://${folderId}/yandexgpt-5/latest`,
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
            usage: data.result?.usage || {}
        };
    } finally {
        clearTimeout(timeout);
    }
}

/**
 * Получить embedding вектора для RAG (используется rag-indexer)
 * @param {string} text — текст для эмбеддинга
 * @returns {Promise<number[]>}
 */
export async function getEmbedding(text) {
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
                modelUri: `emb://${folderId}/text-search-query/latest`,
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
