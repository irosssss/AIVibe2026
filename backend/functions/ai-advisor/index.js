// backend/functions/ai-advisor/index.js
// Yandex Cloud Function — AI Advisor (лёгкая точка входа без prompt guard).
// Использует единую реализацию triplexFallback из shared/triplex-fallback.js
// для избежания дублирования Circuit Breaker, cache и fallback-логики.

import { triplexFallback } from '../../shared/triplex-fallback.js';

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
        const body = JSON.parse(event.body || '{}');
        const { prompt, userId, imageBase64 } = body;

        if (!prompt || !userId) {
            return buildResponse(400, { error: 'Missing required fields: prompt, userId' });
        }

        // Rate limit
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
