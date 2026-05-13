// backend/index.js
// Yandex Cloud Function — AI Advisor proxy.
// Triplex fallback: YandexGPT → GigaChat → Cache.
// Rate limit: 20 req/min per userId (in-memory).

const { callYandexGPT } = require('./yandexgpt');
const { callGigaChat } = require('./gigachat');
const cache = require('./cache');

// ─── Конфигурация ───────────────────────────────────────────────

const RATE_LIMIT_PER_MINUTE = 20;
const RATE_WINDOW_MS = 60_000; // 1 минута
const APP_TOKEN_HEADER = 'x-app-token';

// ─── Rate Limiter (in-memory) ────────────────────────────────────

/**
 * @type {Map<string, { count: number, resetTime: number }>}
 */
const rateLimitMap = new Map();

/**
 * Проверяет, не превышен ли лимит запросов для userId.
 * Каждую минуту счётчик сбрасывается автоматически.
 *
 * @param {string} userId
 * @returns {{ allowed: boolean, remaining: number, resetInMs: number }}
 */
function checkRateLimit(userId) {
    const now = Date.now();
    let entry = rateLimitMap.get(userId);

    if (!entry || now > entry.resetTime) {
        // Первый запрос или окно истекло — создаём новое окно
        entry = { count: 0, resetTime: now + RATE_WINDOW_MS };
        rateLimitMap.set(userId, entry);
    }

    entry.count++;
    const remaining = Math.max(0, RATE_LIMIT_PER_MINUTE - entry.count);
    const resetInMs = entry.resetTime - now;

    return {
        allowed: entry.count <= RATE_LIMIT_PER_MINUTE,
        remaining,
        resetInMs
    };
}

// ─── Yandex Cloud Function Handler ───────────────────────────────

/**
 * Точка входа Yandex Cloud Function.
 * Ожидает POST-запросы с JSON-телом { prompt, userId, imageBase64? }.
 *
 * @param {import('yc-function').YandexCloudEvent} event
 * @param {import('yc-function').YandexCloudContext} context
 * @returns {Promise<{ statusCode: number, body: string, headers: object }>}
 */
module.exports.handler = async (event, context) => {
    const startTime = Date.now();

    // ── 1. CORS Preflight ────────────────────────────────────────
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            body: '',
            headers: corsHeaders()
        };
    }

    // ── 2. Разбор запроса ────────────────────────────────────────
    let body;
    try {
        body = JSON.parse(event.body || '{}');
    } catch {
        return jsonResponse(400, { error: 'Invalid JSON body' });
    }

    const { prompt, userId, imageBase64 } = body;

    if (!prompt || typeof prompt !== 'string') {
        return jsonResponse(400, { error: 'Missing required field: prompt' });
    }

    if (!userId || typeof userId !== 'string') {
        return jsonResponse(400, { error: 'Missing required field: userId' });
    }

    // ── 3. Валидация App Token ───────────────────────────────────
    const appToken = event.headers?.[APP_TOKEN_HEADER]
                  || event.headers?.[APP_TOKEN_HEADER.toLowerCase()];

    const expectedToken = process.env.APP_TOKEN;
    if (expectedToken && appToken !== expectedToken) {
        console.warn(`[${userId}] Invalid App Token`);
        return jsonResponse(403, { error: 'Forbidden: invalid App Token' });
    }

    // ── 4. Rate Limiting ─────────────────────────────────────────
    const rateInfo = checkRateLimit(userId);

    if (!rateInfo.allowed) {
        console.warn(`[${userId}] Rate limit exceeded`);
        return jsonResponse(429, {
            error: 'Rate limit exceeded',
            retryAfterMs: rateInfo.resetInMs
        });
    }

    // ── 5. Triplex Fallback ──────────────────────────────────────
    let text;
    let provider;
    let latencyMs;

    // Попытка 1: YandexGPT
    const yandexIamToken = process.env.YANDEX_IAM_TOKEN;
    const yandexFolderId = process.env.YANDEX_FOLDER_ID;

    if (yandexIamToken && yandexFolderId) {
        try {
            const yandexStart = Date.now();
            text = await callYandexGPT(prompt, yandexIamToken, yandexFolderId);
            latencyMs = Date.now() - yandexStart;
            provider = 'yandexgpt';
            console.log(`[${userId}] YandexGPT success (${latencyMs}ms)`);
        } catch (err) {
            console.warn(`[${userId}] YandexGPT failed: ${err.message}`);
        }
    } else {
        console.warn('[Config] YANDEX_IAM_TOKEN / YANDEX_FOLDER_ID not set');
    }

    // Попытка 2: GigaChat (если YandexGPT не ответил)
    const gigachatClientSecret = process.env.GIGACHAT_CLIENT_SECRET;

    if (!text && gigachatClientSecret) {
        try {
            const gigaStart = Date.now();
            text = await callGigaChat(prompt, gigachatClientSecret);
            latencyMs = Date.now() - gigaStart;
            provider = 'gigachat';
            console.log(`[${userId}] GigaChat success (${latencyMs}ms)`);
        } catch (err) {
            console.warn(`[${userId}] GigaChat failed: ${err.message}`);
        }
    } else if (!text && !gigachatClientSecret) {
        console.warn('[Config] GIGACHAT_CLIENT_SECRET not set');
    }

    // Попытка 3: Cache (если оба провайдера не ответили)
    if (!text) {
        const cached = cache.get(prompt);
        if (cached) {
            text = cached.text;
            provider = 'cache';
            latencyMs = Date.now() - startTime;
            console.log(`[${userId}] Cache hit (provider: ${cached.provider})`);
        }
    }

    // ── 6. Fallback: если ничего не сработало ────────────────────
    if (!text) {
        text = 'Извините, все AI-провайдеры временно недоступны. Пожалуйста, попробуйте позже.';
        provider = 'unavailable';
        latencyMs = Date.now() - startTime;
        console.error(`[${userId}] All providers exhausted`);
    }

    // ── 7. Кэшируем успешный ответ (кроме кэша) ──────────────────
    if (provider !== 'cache' && provider !== 'unavailable') {
        cache.set(prompt, text, provider);
    }

    // ── 8. Возвращаем ответ ──────────────────────────────────────
    const totalLatency = Date.now() - startTime;

    console.log(
        `[${userId}] Response: provider=${provider}, ` +
        `latency=${totalLatency}ms, rateLimit=${rateInfo.remaining}/${RATE_LIMIT_PER_MINUTE}`
    );

    return jsonResponse(200, {
        text,
        provider,
        latencyMs: totalLatency,
        rateLimit: {
            remaining: rateInfo.remaining,
            resetInMs: rateInfo.resetInMs
        }
    });
};

// ─── Вспомогательные функции ─────────────────────────────────────

/**
 * Возвращает JSON-ответ с CORS-заголовками.
 *
 * @param {number} statusCode
 * @param {object} data
 * @returns {{ statusCode: number, body: string, headers: object }}
 */
function jsonResponse(statusCode, data) {
    return {
        statusCode,
        body: JSON.stringify(data),
        headers: corsHeaders()
    };
}

/**
 * CORS-заголовки для iOS-клиента.
 * @returns {object}
 */
function corsHeaders() {
    return {
        'Content-Type': 'application/json; charset=utf-8',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-App-Token'
    };
}
