// backend/functions/ai-advisor/index.js
// Yandex Cloud Function — AI Advisor.
// Использует единую реализацию triplexFallback из shared/triplex-fallback.js
// для избежания дублирования Circuit Breaker, cache и fallback-логики.

import { triplexFallback } from '../../shared/triplex-fallback.js';
import { guardPrompt, MAX_PROMPT_LENGTH } from '../../shared/promptGuard.js';

const APP_TOKEN_HEADER = 'x-app-token';
const MAX_USER_ID_LENGTH = 64;
const MAX_BASE64_LENGTH = 7 * 1024 * 1024; // ~5MB raw

// In-memory rate limit store: { userId: { count, resetAt } }
const rateLimitStore = new Map();
const RATE_LIMIT_PER_MINUTE = 20;
const RATE_WINDOW_MS = 60_000;

/**
 * Проверка rate limit (in-memory, без внешних зависимостей)
 * Для продакшна заменить на Redis / YDB
 */
function checkRateLimit(userId) {
    const now = Date.now();
    let entry = rateLimitStore.get(userId);

    if (!entry || now > entry.resetAt) {
        rateLimitStore.set(userId, { count: 1, resetAt: now + RATE_WINDOW_MS });
        return { allowed: true, remaining: RATE_LIMIT_PER_MINUTE - 1 };
    }

    if (entry.count >= RATE_LIMIT_PER_MINUTE) {
        return { allowed: false, remaining: 0 };
    }

    entry.count++;
    return { allowed: true, remaining: Math.max(0, RATE_LIMIT_PER_MINUTE - entry.count) };
}

/**
 * Handler Yandex Cloud Function
 */
export const handler = async (event, context) => {
    const startTime = Date.now();

    try {
        // 1. APP_TOKEN check — закрывает unauthenticated abuse (#20 / #14)
        const appToken = event.headers?.[APP_TOKEN_HEADER]
                      || event.headers?.[APP_TOKEN_HEADER.toLowerCase()];
        const expectedToken = process.env.APP_TOKEN;
        if (!expectedToken || appToken !== expectedToken) {
            return buildResponse(403, { error: 'Forbidden: invalid App Token' });
        }

        // 2. Parse + базовая валидация типов
        let body;
        try {
            body = JSON.parse(event.body || '{}');
        } catch {
            return buildResponse(400, { error: 'Invalid JSON body' });
        }
        const { prompt, userId, imageBase64 } = body;

        if (!prompt || typeof prompt !== 'string') {
            return buildResponse(400, { error: 'Missing required field: prompt' });
        }
        if (!userId || typeof userId !== 'string') {
            return buildResponse(400, { error: 'Missing required field: userId' });
        }

        // 3. Input limits + regex (M2 imageBase64 / M3 userId)
        if (prompt.length > MAX_PROMPT_LENGTH) {
            return buildResponse(413, { error: 'Prompt too long' });
        }
        if (userId.length > MAX_USER_ID_LENGTH || !/^[a-zA-Z0-9_.-]+$/.test(userId)) {
            return buildResponse(400, { error: 'Invalid userId format' });
        }
        if (imageBase64 && typeof imageBase64 === 'string' && imageBase64.length > MAX_BASE64_LENGTH) {
            return buildResponse(413, { error: 'imageBase64 too large' });
        }

        // 4. Prompt guard — injection-паттерны и cost-amplification.
        // Наружу отдаём обобщённое сообщение; технический reason — только в логах.
        const guardVerdict = guardPrompt(prompt);
        if (!guardVerdict.allowed) {
            console.warn('[warn] prompt rejected by guard', JSON.stringify({
                _l: 'warn',
                userId: userId.slice(0, 16),
                reason: guardVerdict.reason,
            }));
            return buildResponse(400, { error: 'Content policy violation' });
        }

        // 5. Rate limit
        const rateInfo = checkRateLimit(userId);
        if (!rateInfo.allowed) {
            return buildResponse(429, {
                error: 'Rate limit exceeded. Max 20 req/min.',
                retryAfter: 60
            });
        }

        // Единый triplex fallback (Circuit Breaker + кэш — в shared/triplex-fallback.js)
        const result = await triplexFallback({
            prompt,
            imageBase64,
            timeoutMs: 25000,
            log: (level, msg, extra) => {
                const entry = { _l: level, _t: Date.now() - startTime, userId: userId?.slice(0, 16), ...extra };
                console[level === 'error' ? 'error' : level === 'warn' ? 'warn' : 'log'](
                    `[${level}] ${msg}`, JSON.stringify(entry).slice(0, 500)
                );
            }
        });

        const totalLatency = Date.now() - startTime;

        return buildResponse(200, {
            text: result.text,
            provider: result.provider,
            latency_ms: totalLatency,
            errorLog: result.errorLog.length > 0 ? result.errorLog : undefined,
            circuitSkipped: result.circuitSkipped || undefined,
            rateLimit: {
                remaining: rateInfo.remaining,
                resetInMs: RATE_WINDOW_MS
            }
        });

    } catch (err) {
        // L2 fix: не отдаём err.message наружу — log internally, generic response
        const requestId = (typeof crypto !== 'undefined' && crypto.randomUUID)
            ? crypto.randomUUID()
            : String(Date.now());
        console.error('aiAdvisor fatal error:', JSON.stringify({
            requestId,
            message: err.message,
            stack: err.stack?.slice(0, 500)
        }));
        return buildResponse(500, {
            error: 'internal_error',
            requestId,
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
            'Access-Control-Allow-Headers': 'Content-Type, X-App-Token'
        },
        body: JSON.stringify(body)
    };
}
