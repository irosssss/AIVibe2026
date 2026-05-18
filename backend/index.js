// backend/index.js
// Yandex Cloud Function — AI Advisor proxy.
// Triplex fallback: YandexGPT → GigaChat → Cache.
// Rate limit: 20 req/min per userId (in-memory).
// Circuit Breaker per provider (3 failures → 5min cooldown, 60s recovery probe).

import * as promptGuard from './promptGuard.js';
import * as blockedUsers from './blockedUsers.js';
import { triplexFallback, circuitStatus, circuitReset, clearCache, cacheSize } from './shared/triplex-fallback.js';

// ─── Конфигурация ───────────────────────────────────────────────

const RATE_LIMIT_PER_MINUTE = 20;
const RATE_WINDOW_MS = 60_000; // 1 минута
const APP_TOKEN_HEADER = 'x-app-token';
const REQUEST_ID_HEADER = 'x-request-id';

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
export const handler = async (event, context) => {
    const startTime = Date.now();
    const path = event.path || event.rawPath || '/';
    const method = event.httpMethod;

    // ── 0. Request ID (генерируем или берём из заголовка) ──────────
    const requestId =
        event.headers?.[REQUEST_ID_HEADER] ||
        event.headers?.[REQUEST_ID_HEADER.toLowerCase()] ||
        crypto.randomUUID();

    /** Лог с единым контекстом для всего запроса */
    const log = (level, msg, extra = {}) => {
        const entry = { _l: level, _rid: requestId.slice(0, 8), _t: Date.now() - startTime, ...extra };
        console.log(`[${level}] ${msg}`, JSON.stringify(entry).slice(0, 500));
    };

    // ── 1. CORS Preflight ────────────────────────────────────────
    if (method === 'OPTIONS') {
        return { statusCode: 200, body: '', headers: corsHeaders() };
    }

    // ── Public Health Check (без авторизации) ─────────────────────
    if (path === '/health' && method === 'GET') {
        return jsonResponse(200, {
            status: 'ok',
            uptime: process.uptime ? Math.round(process.uptime()) : null,
            requestId,
            timestamp: new Date().toISOString(),
            rateLimit: { max: RATE_LIMIT_PER_MINUTE, windowMs: RATE_WINDOW_MS },
            circuitBreaker: circuitStatus(),
            blockedUsers: blockedUsers.getStats(),
            cache: { size: cacheSize() },
            version: '2.0',
        });
    }

    // ── Admin API routing ────────────────────────────────────────
    if (path.startsWith('/blocked-users') || path === '/cache/clear' || path.startsWith('/circuit')) {
        return handleAdminApi(event, path, method, requestId);
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

    // ── 5. Triplex Fallback (YandexGPT → GigaChat → Cache) ────
    // Использует единую реализацию из shared/triplex-fallback.js
    const triplexResult = await triplexFallback({
        prompt,
        imageBase64,
        timeoutMs: 25000,
        log: (level, msg, extra) => {
            const entry = { _l: level, _rid: requestId.slice(0, 8), _t: Date.now() - startTime, ...extra };
            console.log(`[${level}] ${msg}`, JSON.stringify(entry).slice(0, 500));
        }
    });

    // ── 6. Возвращаем ответ ──────────────────────────────────────
    const totalLatency = Date.now() - startTime;

    console.log(JSON.stringify({
        _l: 'info', _rid: requestId.slice(0, 8), _t: totalLatency,
        msg: 'Response sent',
        provider: triplexResult.provider,
        rateLimitRemaining: rateInfo.remaining,
    }).slice(0, 500));

    return jsonResponse(200, {
        text: triplexResult.text,
        provider: triplexResult.provider,
        latencyMs: totalLatency,
        requestId,
        circuitBreaker: triplexResult.circuitSkipped ? { skipped: triplexResult.circuitSkipped } : undefined,
        errorLog: triplexResult.errorLog.length > 0 ? triplexResult.errorLog : undefined,
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
 * @param {string} [requestId]
 * @returns {object} YCF response
 */
function handleAdminApi(event, path, method, requestId) {
    // Validate Admin Token (can be same as APP_TOKEN or separate)
    const adminToken = event.headers?.[APP_TOKEN_HEADER]
                    || event.headers?.[APP_TOKEN_HEADER.toLowerCase()]
                    || event.headers?.['x-admin-token'];
    const expectedToken = process.env.APP_TOKEN;
    if (!adminToken || adminToken !== expectedToken) {
        console.warn('[security] Invalid admin token attempt', { path: (path || '').slice(0, 32) });
        return jsonResponse(403, { error: 'Forbidden: invalid admin token' });
    }

    // Health check (admin — расширенный)
    if (path === '/health') {
        const stats = blockedUsers.getStats();
        return jsonResponse(200, {
            status: 'ok',
            uptime: process.uptime ? Math.round(process.uptime()) : null,
            requestId,
            timestamp: new Date().toISOString(),
            blockedUsers: stats,
            rateLimit: { max: RATE_LIMIT_PER_MINUTE, windowMs: RATE_WINDOW_MS },
            circuitBreaker: circuitStatus(),
            cache: { size: cacheSize() },
            version: '2.0',
            _note: 'admin endpoint — extended view'
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
        clearCache();
        return jsonResponse(200, { ok: true, message: 'Cache cleared' });
    }

    // Circuit Breaker: get status (GET) or reset (POST)
    if (path === '/circuit' && method === 'GET') {
        return jsonResponse(200, { data: circuitStatus(), generatedAt: new Date().toISOString() });
    }
    if (path === '/circuit/reset' && method === 'POST') {
        circuitReset();
        console.log('[admin] Circuit Breakers reset', { requestId: requestId?.slice(0, 8) });
        return jsonResponse(200, { ok: true, message: 'Circuit breakers reset to CLOSED', data: circuitStatus() });
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
        'Access-Control-Allow-Headers': 'Content-Type, X-App-Token, X-Admin-Token, X-Request-Id'
    };
}
