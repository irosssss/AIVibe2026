// backend/index.js
// Yandex Cloud Function — AI Advisor proxy.
// Triplex fallback: YandexGPT → GigaChat → Cache.
// Rate limit: 20 req/min per userId (in-memory).

const { callYandexGPT } = require('./yandexgpt');
const { callGigaChat } = require('./gigachat');
const cache = require('./cache');
const promptGuard = require('./promptGuard');
const blockedUsers = require('./blockedUsers');

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

    // Atomic increment (prevent race in concurrent YCF invocations)
    const newCount = entry.count + 1;
    entry.count = newCount;

    const remaining = Math.max(0, RATE_LIMIT_PER_MINUTE - newCount);
    const resetInMs = entry.resetTime - now;

    return {
        allowed: newCount <= RATE_LIMIT_PER_MINUTE,
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
    const path = event.path || event.rawPath || '/';
    const method = event.httpMethod;

    // ── 1. CORS Preflight ────────────────────────────────────────
    if (method === 'OPTIONS') {
        return {
            statusCode: 200,
            body: '',
            headers: corsHeaders()
        };
    }

    // ── Admin API routing ────────────────────────────────────────
    if (path.startsWith('/blocked-users') || path === '/cache/clear') {
        return handleAdminApi(event, path, method);
    }

    // ── 2. Main endpoint: /analyze ───────────────────────────────
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

    // ── Input Sanitization & Limits ──────────────────────────────
    const MAX_PROMPT_LENGTH = 4000;
    const MAX_USER_ID_LENGTH = 64;
    const MAX_BASE64_LENGTH = 7 * 1024 * 1024; // ~5MB raw

    if (prompt.length > MAX_PROMPT_LENGTH) {
        return jsonResponse(413, { error: `Prompt exceeds max length of ${MAX_PROMPT_LENGTH} characters` });
    }

    if (userId.length > MAX_USER_ID_LENGTH || !/^[a-zA-Z0-9_.-]+$/.test(userId)) {
        return jsonResponse(400, { error: 'Invalid userId format. Use alphanumeric, underscore, dot, or hyphen.' });
    }

    if (imageBase64 && typeof imageBase64 === 'string' && imageBase64.length > MAX_BASE64_LENGTH) {
        return jsonResponse(413, { error: `imageBase64 exceeds max size of ${MAX_BASE64_LENGTH} characters` });
    }

    // ── 3. Валидация App Token ───────────────────────────────────
    const appToken = event.headers?.[APP_TOKEN_HEADER]
                  || event.headers?.[APP_TOKEN_HEADER.toLowerCase()];

    const expectedToken = process.env.APP_TOKEN;
    if (!expectedToken || appToken !== expectedToken) {
        console.warn('[security] Invalid or missing App Token', { userId: userId.slice(0, 16) });
        return jsonResponse(403, { error: 'Forbidden: invalid App Token' });
    }

    // ── 4. Rate Limiting ─────────────────────────────────────────
    const rateInfo = checkRateLimit(userId);

    if (!rateInfo.allowed) {
        console.warn('[security] Rate limit exceeded', { userId: userId.slice(0, 16), remaining: rateInfo.remaining });
        return jsonResponse(429, {
            error: 'Rate limit exceeded',
            retryAfterMs: rateInfo.resetInMs
        });
    }

    // ── 4.5 Blocked Users Check ─────────────────────────────────
    const blockCheck = blockedUsers.isBlocked(userId);
    if (blockCheck.blocked) {
        console.warn('[security] User blocked', { userId: userId.slice(0, 16), reason: blockCheck.reason, severity: blockCheck.severity });
        return jsonResponse(403, {
            error: 'User temporarily blocked due to policy violations.',
            blockedUntil: blockCheck.expiresAt,
            reason: 'Your account is blocked for 24 hours. Contact support if you believe this is an error.'
        });
    }

    // ── 4.6 Prompt Guard ────────────────────────────────────────
    const guardResult = promptGuard.analyze(prompt);
    const guardLog = promptGuard.formatResult(guardResult, userId);
    console.log('[guard] Analysis', guardLog);

    if (promptGuard.isImmediateBlock(guardResult)) {
        const ban = blockedUsers.blockUser(userId, {
            reason: guardResult.reason,
            injectionPrompt: prompt,
            severity: guardResult.severity,
            rule: guardResult.rule
        });
        console.warn('[security] Immediate block applied', { userId: userId.slice(0, 16), rule: guardResult.rule });
        return jsonResponse(403, {
            error: 'Blocked: content policy violation',
            blockedUntil: ban.expiresAt,
            message: 'Your message violated our content policy. Your account is blocked for 24 hours.'
        });
    }

    if (promptGuard.isStrike(guardResult)) {
        const strikeResult = blockedUsers.addStrike(userId, { ...guardResult, prompt });
        if (strikeResult.banned) {
            console.warn('[security] Strike ban applied', { userId: userId.slice(0, 16), strikes: strikeResult.strikes });
            return jsonResponse(403, {
                error: 'Blocked: too many violations',
                blockedUntil: strikeResult.banResult.expiresAt,
                message: `Your account is blocked for 24 hours after ${blockedUsers.STRIKE_THRESHOLD} policy violations.`
            });
        }
        // Не блокируем сейчас, но логируем strike
        console.warn('[security] Strike recorded', { userId: userId.slice(0, 16), strikes: strikeResult.strikes });
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
            console.log('[service] YandexGPT success', { userId: userId.slice(0, 16), latencyMs });
        } catch (err) {
            console.warn('[service] YandexGPT failed', { userId: userId.slice(0, 16), error: String(err.message).slice(0, 100) });
        }
    } else {
        console.warn('[config] YANDEX_IAM_TOKEN / YANDEX_FOLDER_ID not set');
    }

    // Попытка 2: GigaChat (если YandexGPT не ответил)
    const gigachatClientSecret = process.env.GIGACHAT_CLIENT_SECRET;

    if (!text && gigachatClientSecret) {
        try {
            const gigaStart = Date.now();
            text = await callGigaChat(prompt, gigachatClientSecret);
            latencyMs = Date.now() - gigaStart;
            provider = 'gigachat';
            console.log('[service] GigaChat success', { userId: userId.slice(0, 16), latencyMs });
        } catch (err) {
            console.warn('[service] GigaChat failed', { userId: userId.slice(0, 16), error: String(err.message).slice(0, 100) });
        }
    } else if (!text && !gigachatClientSecret) {
        console.warn('[config] GIGACHAT_CLIENT_SECRET not set');
    }

    // Попытка 3: Cache (если оба провайдера не ответили)
    if (!text) {
        const cached = cache.get(prompt);
        if (cached) {
            text = cached.text;
            provider = 'cache';
            latencyMs = Date.now() - startTime;
            console.log('[service] Cache hit', { userId: userId.slice(0, 16), provider: cached.provider });
        }
    }

    // ── 6. Fallback: если ничего не сработало ────────────────────
    if (!text) {
        text = 'Извините, все AI-провайдеры временно недоступны. Пожалуйста, попробуйте позже.';
        provider = 'unavailable';
        latencyMs = Date.now() - startTime;
        console.error('[service] All providers exhausted', { userId: userId.slice(0, 16) });
    }

    // ── 7. Кэшируем успешный ответ (кроме кэша) ──────────────────
    if (provider !== 'cache' && provider !== 'unavailable') {
        cache.set(prompt, text, provider);
    }

    // ── 8. Возвращаем ответ ──────────────────────────────────────
    const totalLatency = Date.now() - startTime;

    console.log('[service] Response sent', {
        userId: userId.slice(0, 16),
        provider,
        latencyMs: totalLatency,
        rateLimitRemaining: rateInfo.remaining,
        rateLimitMax: RATE_LIMIT_PER_MINUTE
    });

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

/**
 * Обработка admin API endpoints (/blocked-users/*, /cache/clear).
 * Требует Admin Token отдельно от APP_TOKEN.
 *
 * @param {object} event
 * @param {string} path
 * @param {string} method
 * @returns {object} YCF response
 */
function handleAdminApi(event, path, method) {
    // Validate Admin Token (can be same as APP_TOKEN or separate)
    const adminToken = event.headers?.[APP_TOKEN_HEADER]
                    || event.headers?.[APP_TOKEN_HEADER.toLowerCase()]
                    || event.headers?.['x-admin-token'];
    const expectedToken = process.env.APP_TOKEN;
    if (!adminToken || adminToken !== expectedToken) {
        console.warn('[security] Invalid admin token attempt', { path: (path || '').slice(0, 32) });
        return jsonResponse(403, { error: 'Forbidden: invalid admin token' });
    }

    // Health check
    if (path === '/health') {
        const stats = blockedUsers.getStats();
        return jsonResponse(200, {
            status: 'ok',
            uptime: 'N/A (serverless)',
            blockedUsers: stats,
            rateLimit: { max: RATE_LIMIT_PER_MINUTE, windowMs: RATE_WINDOW_MS }
        });
    }

    // List blocked users
    if (path === '/blocked-users' && method === 'GET') {
        const list = blockedUsers.listBlocked();
        const stats = blockedUsers.getStats();
        return jsonResponse(200, {
            data: list,
            total: list.length,
            stats,
            generatedAt: new Date().toISOString()
        });
    }

    // Stats
    if (path === '/blocked-users/stats' && method === 'GET') {
        return jsonResponse(200, blockedUsers.getStats());
    }

    // Unblock user
    const unblockMatch = path.match(/^\/blocked-users\/(.+)$/);
    if (unblockMatch && method === 'DELETE') {
        const userId = unblockMatch[1];
        const result = blockedUsers.unblockUser(userId);
        return jsonResponse(result.ok ? 200 : 400, result);
    }

    // Cleanup expired
    if (path === '/blocked-users/cleanup' && method === 'POST') {
        const result = blockedUsers.cleanupExpired();
        return jsonResponse(200, result);
    }

    // Cache clear
    if (path === '/cache/clear' && method === 'POST') {
        cache.clear();
        return jsonResponse(200, { ok: true, message: 'Cache cleared' });
    }

    return jsonResponse(404, { error: 'Admin endpoint not found' });
}

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
        'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-App-Token, X-Admin-Token'
    };
}
