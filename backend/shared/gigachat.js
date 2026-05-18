// gigachat.js — Клиент GigaChat для Yandex Cloud Functions
// Auth: OAuth 2.0 (Client Credentials)
// Endpoint: https://gigachat.devices.sberbank.ru/api/v1/chat/completions
// ВАЖНО: self-signed SSL-сертификат — отключаем проверку
// через переменную окружения NODE_TLS_REJECT_UNAUTHORIZED='0'

import { getSecrets } from './secrets.js';

// Кэш OAuth-токена GigaChat (29 мин, т.к. живёт 30 мин)
let gigaChatToken = null;
let gigaChatTokenExp = 0;

/**
 * Получить OAuth-токен GigaChat
 * @returns {Promise<string>}
 */
async function getGigaChatToken() {
    if (gigaChatToken && Date.now() < gigaChatTokenExp) {
        return gigaChatToken;
    }

    const secrets = await getSecrets();
    const authString = Buffer.from(
        `${secrets.GIGACHAT_CLIENT_ID}:${secrets.GIGACHAT_CLIENT_SECRET}`
    ).toString('base64');

    const response = await fetch(
        'https://ngw.devices.sberbank.ru:9443/api/v2/oauth',
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'Authorization': `Basic ${authString}`,
                'RqUID': crypto.randomUUID()
            }
        }
    );

    if (!response.ok) {
        throw new Error(`GigaChat OAuth error: ${response.status}`);
    }

    const data = await response.json();
    gigaChatToken = data.access_token;
    gigaChatTokenExp = Date.now() + 29 * 60 * 1000; // 29 мин (токен живёт 30 мин)

    return gigaChatToken;
}

/**
 * Вызвать GigaChat
 * @param {object} options
 * @param {string} options.prompt
 * @param {number} [options.timeoutMs=25000]
 * @returns {Promise<{text: string, provider: string, usage: object}>}
 */
export async function callGigaChat({ prompt, timeoutMs = 25000 }) {
    const token = await getGigaChatToken();

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    try {
        const response = await fetch(
            'https://gigachat.devices.sberbank.ru/api/v1/chat/completions',
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({
                    model: 'GigaChat-Max',
                    messages: [{ role: 'user', content: prompt }],
                    temperature: 0.7,
                    max_tokens: 2000
                }),
                signal: controller.signal
            }
        );

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`GigaChat HTTP ${response.status}: ${errorText}`);
        }

        const data = await response.json();
        const text = data.choices?.[0]?.message?.content || '';

        return {
            text,
            provider: 'gigachat',
            usage: { tokens: data.usage?.total_tokens || 0 }
        };
    } finally {
        clearTimeout(timeout);
    }
}