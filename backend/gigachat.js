// backend/gigachat.js
// Клиент GigaChat API.
// Использует OAuth 2.0 для получения токена.
// ⚠️ Самоподписанный сертификат — отключаем проверку SSL (ТОЛЬКО ДЛЯ РАЗРАБОТКИ).

// ⚠️ ВАЖНО: отключаем проверку SSL для dev-среды
// GigaChat использует самоподписанные сертификаты.
// В продакшне использовать pinned certificate или через Yandex API Gateway.
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

const AUTH_URL = 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth';
const API_URL = 'https://gigachat.devices.sberbank.ru/api/v1/chat/completions';
const MODEL_NAME = 'GigaChat-Max';
const TIMEOUT_MS = 20_000;
const TOKEN_TTL_MS = 29 * 60 * 1000; // 29 минут (кэширование токена)

// --- OAuth Token Cache ---

/** @type {{ token: string | null, expiresAt: number }} */
let tokenCache = { token: null, expiresAt: 0 };

/**
 * Получает OAuth-токен GigaChat.
 * Кэширует на 29 минут (Sberbank выдаёт токен на 30 минут).
 *
 * @param {string} clientSecret — секретный ключ клиента
 * @returns {Promise<string>} — access token
 */
async function getGigaChatToken(clientSecret) {
    // Проверяем кэш
    if (tokenCache.token && Date.now() < tokenCache.expiresAt) {
        return tokenCache.token;
    }

    const credentials = Buffer.from(clientSecret).toString('base64');

    const response = await fetch(AUTH_URL, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'Authorization': `Basic ${credentials}`,
            'RqUID': crypto.randomUUID()
        },
        body: new URLSearchParams({
            scope: 'GIGACHAT_API_PERS'
        })
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(`GigaChat OAuth error: HTTP ${response.status} — ${text.slice(0, 200)}`);
    }

    /** @type {{ access_token: string, expires_at?: number }} */
    const data = await response.json();

    if (!data.access_token) {
        throw new Error('GigaChat: пустой access_token в ответе OAuth');
    }

    // Кэшируем токен на 29 минут (на 1 минуту меньше срока жизни для запаса)
    tokenCache = {
        token: data.access_token,
        expiresAt: Date.now() + TOKEN_TTL_MS
    };

    return data.access_token;
}

/**
 * Вызывает GigaChat Chat Completions API.
 *
 * @param {string} prompt — текст запроса пользователя
 * @param {string} clientSecret — секретный ключ для OAuth
 * @returns {Promise<string>} — текст ответа
 * @throws {Error} — при HTTP не 200 или таймауте
 */
async function callGigaChat(prompt, clientSecret) {
    const token = await getGigaChatToken(clientSecret);

    const body = {
        model: MODEL_NAME,
        messages: [
            {
                role: 'user',
                content: prompt
            }
        ],
        temperature: 0.7,
        max_tokens: 1000
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
        const response = await fetch(API_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify(body),
            signal: controller.signal
        });

        if (!response.ok) {
            const responseText = await response.text();
            throw new Error(
                `GigaChat HTTP ${response.status}: ${responseText.slice(0, 200)}`
            );
        }

        /** @type {any} */
        const data = await response.json();

        // Формат ответа OpenAI-compatible: { choices: [{ message: { content: string } }] }
        const content = data?.choices?.[0]?.message?.content;

        if (!content) {
            throw new Error('GigaChat: пустой ответ от API');
        }

        return content;
    } catch (err) {
        if (err.name === 'AbortError') {
            throw new Error('GigaChat: таймаут запроса');
        }
        throw err;
    } finally {
        clearTimeout(timeoutId);
    }
}

/**
 * Сбрасывает кэш токена (для тестов).
 */
function resetTokenCache() {
    tokenCache = { token: null, expiresAt: 0 };
}

module.exports = { callGigaChat, getGigaChatToken, resetTokenCache };
