// backend/index.js
// Yandex Cloud Function — AI Advisor proxy.
// Triplex fallback: YandexGPT → GigaChat → Cache.
// Rate limit: 20 req/min per userId (in-memory).
// Circuit Breaker per provider (3 failures → 5min cooldown, 60s recovery probe).

import { callYandexGPT } from './shared/yandexgpt.js';
import { callGigaChat } from './shared/gigachat.js';
import * as cache from './cache.js';
import * as promptGuard from './promptGuard.js';
import * as blockedUsers from './blockedUsers.js';
import { CIRCUIT_THRESHOLD, CIRCUIT_COOLDOWN_MS, CIRCUIT_PROBE_MS, CIRCUIT_PROVIDERS } from './shared/circuit-config.js';

// ─── Конфигурация ───────────────────────────────────────────────

const RATE_LIMIT_PER_MINUTE = 20;
const RATE_WINDOW_MS = 60_000; // 1 минута
const APP_TOKEN_HEADER = 'x-app-token';
const REQUEST_ID_HEADER = 'x-request-id';

// ─── Circuit Breaker ─────────────────────────────────────────────
// Реализует паттерн Circuit Breaker для каждого AI-провайдера.
// CLOSED → OPEN (после threshold ошибок) → HALF_OPEN (после cooldown) → CLOSED/OPEN

// Константы вынесены в shared/circuit-config.js — синхронизировать с iOS CircuitBreakerConfig.swift

/**
 * @typedef {'CLOSED' | 'OPEN' | 'HALF_OPEN'} CircuitState
 * @typedef {object} CircuitEntry
 * @property {CircuitState} state
 * @property {number} failures
 * @property {number} lastFailureTime
 * @property {number} lastSuccessTime
 * @property {number} nextProbeTime
 * @property {number} totalFailures
 * @property {number} totalSuccesses
 */

/** @type {Map<string, CircuitEntry>} */
const circuitMap = new Map(
    CIRCUIT_PROVIDERS.map(name => [name, createCircuit()])
);

/**
 * Создаёт новую запись Circuit Breaker в состоянии CLOSED.
 * @returns {CircuitEntry}
 */
function createCircuit() {
    const now = Date.now();
    return {
        state: 'CLOSED',
        failures: 0,
        lastFailureTime: 0,
        lastSuccessTime: now,
        nextProbeTime: now,
        totalFailures: 0,
        totalSuccesses: 0,
    };
}

/**
 * Проверяет, разрешён ли запрос к провайдеру по состоянию Circuit Breaker.
 * В HALF_OPEN разрешает один пробный запрос (probe).
 *
 * @param {string} provider
 * @returns {{ allowed: boolean, state: CircuitState }}
 */
function circuitAllowed(provider) {
    const c = circuitMap.get(provider);
    if (!c) return { allowed: true, state: 'CLOSED' };

    const now = Date.now();

    switch (c.state) {
        case 'CLOSED':
            return { allowed: true, state: 'CLOSED' };

        case 'OPEN':
            if (now >= c.nextProbeTime) {
                c.state = 'HALF_OPEN';
                console.log(`[circuit] ${provider} -> HALF_OPEN (probe)`);
                return { allowed: true, state: 'HALF_OPEN' };
            }
            return { allowed: false, state: 'OPEN' };

        case 'HALF_OPEN':
            return { allowed: true, state: 'HALF_OPEN' };

        default:
            return { allowed: true, state: 'CLOSED' };
    }
}

/**
 * Сообщает Circuit Breaker об успехе запроса. Переводит -> CLOSED.
 * @param {string} provider
 */
function circuitSuccess(provider) {
    const c = circuitMap.get(provider);
    if (!c) return;

    const wasOpen = c.state !== 'CLOSED';
    c.failures = 0;
    c.lastSuccessTime = Date.now();
    c.totalSuccesses++;
    c.state = 'CLOSED';

    if (wasOpen) {
        console.log(`[circuit] ${provider} -> CLOSED (recovered after ${c.totalFailures} total failures)`);
    }
}

/**
 * Сообщает Circuit Breaker об ошибке. При достижении threshold -> OPEN с cooldown.
 * @param {string} provider
 * @param {Error} [err]
 */
function circuitFailure(provider, err) {
    const c = circuitMap.get(provider);
    if (!c) return;

    c.failures++;
    c.totalFailures++;
    c.lastFailureTime = Date.now();

    if (c.state === 'HALF_OPEN') {
        c.state = 'OPEN';
        c.nextProbeTime = Date.now() + CIRCUIT_COOLDOWN_MS;
        console.warn(`[circuit] ${provider} -> OPEN (probe failed, next probe in ${CIRCUIT_COOLDOWN_MS / 1000}s)`, {
            error: err ? String(err.message).slice(0, 120) : undefined
        });
        return;
    }

    if (c.failures >= CIRCUIT_THRESHOLD) {
        c.state = 'OPEN';
        c.nextProbeTime = Date.now() + CIRCUIT_COOLDOWN_MS;
        console.warn(`[circuit] ${provider} -> OPEN (${c.failures} consecutive failures, cooldown ${CIRCUIT_COOLDOWN_MS / 1000}s)`, {
            error: err ? String(err.message).slice(0, 120) : undefined
        });
    }
}

/**
 * Возвращает статус всех Circuit Breakers для health check / admin API.
 * @returns {Record<string, object>}
 */
function circuitStatusAll() {
    /** @type {Record<string, object>} */
    const status = {};
    for (const [name, c] of circuitMap) {
        status[name] = {
            state: c.state,
            failures: c.failures,
            totalFailures: c.totalFailures,
            totalSuccesses: c.totalSuccesses,
            lastFailureMsAgo: c.lastFailureTime ? Date.now() - c.lastFailureTime : null,
            nextProbeMs: c.state === 'OPEN' ? Math.max(0, c.nextProbeTime - Date.now()) : null,
        };
    }
    return status;
}

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
            circuitBreaker: circuitStatusAll(),
            blockedUsers: blockedUsers.getStats(),
            cache: cache.stats ? cache.stats() : null,
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

    // ── 5. Triplex Fallback (с Circuit Breaker) ──────────────────
    let text;
    let provider;
    let latencyMs;
    let circuitSkipped = null; // какой провайдер был пропущен CB

    // Попытка 1: YandexGPT
    const yandexCB = circuitAllowed('yandexgpt');
    if (yandexCB.allowed) {
        try {
            const yandexStart = Date.now();
            text = await callYandexGPT({ prompt, imageBase64, timeoutMs: 25000 });
            latencyMs = Date.now() - yandexStart;
            provider = 'yandexgpt';
            circuitSuccess('yandexgpt');
            log('info', 'YandexGPT success', { provider, latencyMs });
        } catch (err) {
            circuitFailure('yandexgpt', err);
            log('warn', 'YandexGPT failed', { error: String(err.message).slice(0, 120) });
        }
    } else {
        circuitSkipped = circuitSkipped || 'yandexgpt';
        log('warn', 'YandexGPT skipped by Circuit Breaker', { state: yandexCB.state });
    }

    // Попытка 2: GigaChat
    if (!text) {
        const gigaCB = circuitAllowed('gigachat');
        if (gigaCB.allowed) {
            try {
                const gigaStart = Date.now();
                text = await callGigaChat({ prompt, timeoutMs: 25000 });
                latencyMs = Date.now() - gigaStart;
                provider = 'gigachat';
                circuitSuccess('gigachat');
                log('info', 'GigaChat success', { provider, latencyMs });
            } catch (err) {
                circuitFailure('gigachat', err);
                log('warn', 'GigaChat failed', { error: String(err.message).slice(0, 120) });
            }
        } else {
            circuitSkipped = (circuitSkipped ? circuitSkipped + ',' : '') + 'gigachat';
            log('warn', 'GigaChat skipped by Circuit Breaker', { state: gigaCB.state });
        }
    }

    // Попытка 3: Cache (не зависит от Circuit Breaker)
    if (!text) {
        const cached = cache.get(prompt);
        if (cached) {
            text = cached.text;
            provider = 'cache';
            latencyMs = Date.now() - startTime;
            log('info', 'Cache hit', { cachedProvider: cached.provider });
        }
    }

    // ── 6. Fallback: если ничего не сработало ────────────────────
    if (!text) {
        text = 'Извините, все AI-провайдеры временно недоступны. Пожалуйста, попробуйте позже.';
        provider = 'unavailable';
        latencyMs = Date.now() - startTime;
        log('error', 'All providers exhausted', { circuitSkipped });
    }

    // ── 7. Кэшируем успешный ответ (кроме кэша) ──────────────────
    if (provider !== 'cache' && provider !== 'unavailable') {
        cache.set(prompt, text, provider);
    }

    // ── 8. Возвращаем ответ ──────────────────────────────────────
    const totalLatency = Date.now() - startTime;

    log('info', 'Response sent', {
        provider,
        latencyMs: totalLatency,
        rateLimitRemaining: rateInfo.remaining,
    });

    return jsonResponse(200, {
        text,
        provider,
        latencyMs: totalLatency,
        requestId,
        circuitBreaker: circuitSkipped ? { skipped: circuitSkipped } : undefined,
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
            circuitBreaker: circuitStatusAll(),
            cache: cache.stats ? cache.stats() : null,
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
        cache.clear();
        return jsonResponse(200, { ok: true, message: 'Cache cleared' });
    }

    // Circuit Breaker: get status (GET) or reset (POST)
    if (path === '/circuit' && method === 'GET') {
        return jsonResponse(200, { data: circuitStatusAll(), generatedAt: new Date().toISOString() });
    }
    if (path === '/circuit/reset' && method === 'POST') {
        for (const [name] of circuitMap) {
            circuitMap.set(name, createCircuit());
        }
        console.log('[admin] Circuit Breakers reset', { requestId: requestId?.slice(0, 8) });
        return jsonResponse(200, { ok: true, message: 'Circuit breakers reset to CLOSED', data: circuitStatusAll() });
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
