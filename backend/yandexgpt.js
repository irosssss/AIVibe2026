// backend/yandexgpt.js
// Клиент YandexGPT API.
// Использует встроенный fetch (Node.js 18+).
// Таймаут 20 секунд через AbortController.

const API_URL = 'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';
const MODEL_VERSION = 'yandexgpt-5/latest';
const TIMEOUT_MS = 20_000;

/**
 * Вызывает YandexGPT Foundation Models API.
 *
 * @param {string} prompt — текст запроса пользователя
 * @param {string} iamToken — IAM-токен для авторизации
 * @param {string} folderId — идентификатор каталога в Yandex Cloud
 * @returns {Promise<string>} — текст ответа
 * @throws {Error} — при HTTP не 200 или таймауте
 */
async function callYandexGPT(prompt, iamToken, folderId) {
    const modelUri = `gpt://${folderId}/${MODEL_VERSION}`;

    const body = {
        modelUri,
        completionOptions: {
            temperature: 0.7,
            maxTokens: 1000
        },
        messages: [
            {
                role: 'user',
                text: prompt
            }
        ]
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
        const response = await fetch(API_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${iamToken}`,
                'x-folder-id': folderId
            },
            body: JSON.stringify(body),
            signal: controller.signal
        });

        if (!response.ok) {
            const responseText = await response.text();
            throw new Error(
                `YandexGPT HTTP ${response.status}: ${responseText.slice(0, 200)}`
            );
        }

        /** @type {any} */
        const data = await response.json();

        // Формат ответа: { result: { alternatives: [{ message: { content: string } }] } }
        const content = data?.result?.alternatives?.[0]?.message?.content
                     || data?.choices?.[0]?.message?.content;

        if (!content) {
            throw new Error('YandexGPT: пустой ответ от API');
        }

        return content;
    } catch (err) {
        if (err.name === 'AbortError') {
            throw new Error('YandexGPT: таймаут запроса');
        }
        throw err;
    } finally {
        clearTimeout(timeoutId);
    }
}

module.exports = { callYandexGPT };
