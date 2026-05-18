// index.js — Точка входа Yandex Cloud Function aiAdvisor
// Triplex fallback: YandexGPT → GigaChat → Cached Response
// Rate limiting: 20 req/min per userId (in-memory)

import { callYandexGPT } from '../../shared/yandexgpt.js';
import { callGigaChat } from '../../shared/gigachat.js';
import { getSecrets } from '../../shared/secrets.js';

// In-memory rate limit store: { userId: { count, resetAt } }
const rateLimitStore = new Map();

// Простой кэш: { promptHash: { text, savedAt } }
const responseCache = new Map();
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24h

/**
 * Проверка rate limit (in-memory, без внешних зависимостей)
 * Для продакшна заменить на Redis / YDB
 */
function checkRateLimit(userId) {
    const now = Date.now();
    const entry = rateLimitStore.get(userId);

    if (!entry || now > entry.resetAt) {
        rateLimitStore.set(userId, { count: 1, resetAt: now + 60 * 1000 });
        return true;
    }

    if (entry.count >= 20) {
        return false;
    }

    entry.count++;
    return true;
}

/**
 * Получить кэшированный ответ (если есть)
 */
function getCachedResponse(prompt) {
    const hash = simpleHash(prompt);
    const entry = responseCache.get(hash);
    if (entry && Date.now() - entry.savedAt < CACHE_TTL_MS) {
        return entry.text;
    }
    if (entry) responseCache.delete(hash);
    return null;
}

/**
 * Сохранить ответ в кэш
 */
function cacheResponse(prompt, text) {
    const hash = simpleHash(prompt);
    responseCache.set(hash, { text, savedAt: Date.now() });
}

/**
 * Простой хеш строки (без внешних зависимостей)
 */
function simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash |= 0;
    }
    return hash.toString(36);
}

/**
 * Handler Yandex Cloud Function
 */
export const handler = async (event, context) => {
    const startTime = Date.now();

    try {
        // --- 1. Parse request ---
        const body = JSON.parse(event.body || '{}');
        const { prompt, userId, imageBase64 } = body;

        if (!prompt || !userId) {
            return buildResponse(400, { error: 'Missing required fields: prompt, userId' });
        }

        // --- 2. App Check validation (заглушка) ---
        const appCheckToken = event.headers?.['X-Firebase-AppCheck'];
        if (!appCheckToken) {
            // В продакшне — валидация через Firebase Admin SDK
            // Сейчас просто логируем
            console.warn('Missing X-Firebase-AppCheck header for userId:', userId);
        }

        // --- 3. Rate limit ---
        if (!checkRateLimit(userId)) {
            return buildResponse(429, {
                error: 'Rate limit exceeded. Max 20 req/min.',
                retryAfter: 60
            });
        }

        let provider = 'yandexgpt';
        let text = '';
        let errorLog = [];

        // --- 4. Try YandexGPT (25s timeout) ---
        try {
            const result = await callYandexGPT({ prompt, imageBase64, timeoutMs: 25000 });
            text = result.text;
            provider = 'yandexgpt';
        } catch (err) {
            errorLog.push({ provider: 'yandexgpt', error: err.message });
            console.warn('YandexGPT failed, trying GigaChat:', err.message);

            // --- 5. Fallback → GigaChat (25s timeout) ---
            try {
                const result = await callGigaChat({ prompt, timeoutMs: 25000 });
                text = result.text;
                provider = 'gigachat';
            } catch (err2) {
                errorLog.push({ provider: 'gigachat', error: err2.message });
                console.warn('GigaChat failed, using cache:', err2.message);

                // --- 6. Fallback → Cache ---
                const cached = getCachedResponse(prompt);
                if (cached) {
                    text = cached;
                    provider = 'cache';
                } else {
                    throw new Error('All providers failed and no cached response available');
                }
            }
        }

        // Сохраняем успешный ответ в кэш
        if (provider !== 'cache') {
            cacheResponse(prompt, text);
        }

        const latency = Date.now() - startTime;

        return buildResponse(200, {
            text,
            provider,
            usage: {},
            latency_ms: latency,
            errorLog: errorLog.length > 0 ? errorLog : undefined
        });

    } catch (err) {
        console.error('aiAdvisor fatal error:', err.message);
        return buildResponse(500, {
            error: err.message,
            provider: 'none',
            latency_ms: Date.now() - startTime
        });
    }
};

function buildResponse(statusCode, body) {
    return {
        statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Firebase-AppCheck'
        },
        body: JSON.stringify(body)
    };
}
