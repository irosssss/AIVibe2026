// yandexgpt.js — Клиент YandexGPT для Yandex Cloud Functions
// Endpoint: https://llm.api.cloud.yandex.net/foundationModels/v1/completion
// Модель: gpt://{folder-id}/yandexgpt-5/latest
// Auth: IAM-токен (обновлять каждые 12 часов через Lockbox)

import { getSecrets } from './secrets.js';

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
    const iamToken = secrets.YANDEX_IAM_TOKEN;

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
    const iamToken = secrets.YANDEX_IAM_TOKEN;

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
