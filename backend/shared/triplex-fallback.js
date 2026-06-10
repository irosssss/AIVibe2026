// backend/shared/triplex-fallback.js
// Единая реализация Triplex Fallback для всех JS-функций.
// YandexGPT → GigaChat → Cache
// Встроенный Circuit Breaker per provider (3 ошибки → 5мин cooldown).
// Используется: backend/index.js, backend/functions/ai-advisor/index.js

import { callYandexGPT } from './yandexgpt.js';
import { callGigaChat } from './gigachat.js';
import { CircuitBreaker } from './circuit-breaker.js';

const circuitBreaker = new CircuitBreaker();

/**
 * Простой in-memory кэш для fallback-ответов.
 * TTL: 24 часа.
 */
const responseCache = new Map();
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Простой хеш строки (без внешних зависимостей).
 * @param {string} str
 * @returns {string}
 */
function simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        hash = ((hash << 5) - hash) + str.charCodeAt(i);
        hash |= 0;
    }
    return hash.toString(36);
}

/**
 * Получить кэшированный ответ.
 * @param {string} prompt
 * @returns {string|null}
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
 * Сохранить ответ в кэш.
 * @param {string} prompt
 * @param {string} text
 */
function cacheResponse(prompt, text) {
    const hash = simpleHash(prompt);
    responseCache.set(hash, { text, savedAt: Date.now() });
}

/**
 * Очистить кэш (для admin API).
 */
export function clearCache() {
    responseCache.clear();
}

/**
 * Возвращает размер кэша.
 * @returns {number}
 */
export function cacheSize() {
    return responseCache.size;
}

/**
 * Выполняет Triplex Fallback: YandexGPT → GigaChat → Cache.
 *
 * @param {object} options
 * @param {string} options.prompt — текстовый промпт
 * @param {string} [options.imageBase64] — base64 изображения (для vision)
 * @param {number} [options.timeoutMs=25000] — таймаут на попытку (мс)
 * @param {'pro'|'lite'} [options.model='pro'] — модель YandexGPT (B7, решение роутера)
 * @param {function} [options.log] — логгер: (level, msg, extra?) => void
 * @returns {Promise<{ text: string, provider: string, model: string|null, usage: object|null, latencyMs: number, circuitSkipped: string|null, errorLog: Array<{provider: string, error: string}> }>}
 */
export async function triplexFallback({ prompt, imageBase64, timeoutMs = 25000, model = 'pro', log }) {
    const logFn = log || (() => {});
    const startTime = Date.now();

    /** @type {string|null} */
    let text = null;
    /** @type {string} */
    let provider = 'unavailable';
    /** @type {string|null} — фактическая модель (B7.3: для замера цены запроса) */
    let modelUsed = null;
    /** @type {object|null} — usage провайдера (prompt/completion tokens) */
    let usage = null;
    /** @type {string|null} */
    let circuitSkipped = null;
    /** @type {Array<{provider: string, error: string}>} */
    const errorLog = [];

    // ── Попытка 1: YandexGPT ────────────────────
    const yandexCB = circuitBreaker.allowed('yandexgpt');
    if (yandexCB.allowed) {
        try {
            const yandexStart = Date.now();
            const result = await callYandexGPT({ prompt, imageBase64, timeoutMs, model });
            text = result.text;
            provider = 'yandexgpt';
            modelUsed = result.model;
            usage = result.usage || null;
            circuitBreaker.success('yandexgpt');
            logFn('info', 'YandexGPT success', { latencyMs: Date.now() - yandexStart, model: modelUsed, usage });
        } catch (err) {
            circuitBreaker.failure('yandexgpt', err);
            const msg = String(err.message).slice(0, 120);
            errorLog.push({ provider: 'yandexgpt', error: msg });
            logFn('warn', 'YandexGPT failed', { error: msg });
        }
    } else {
        const msg = `skipped (CB: ${yandexCB.state})`;
        circuitSkipped = 'yandexgpt';
        errorLog.push({ provider: 'yandexgpt', error: msg });
        logFn('warn', 'YandexGPT skipped by Circuit Breaker', { state: yandexCB.state });
    }

    // ── Попытка 2: GigaChat ─────────────────────
    if (!text) {
        const gigaCB = circuitBreaker.allowed('gigachat');
        if (gigaCB.allowed) {
            try {
                const gigaStart = Date.now();
                const result = await callGigaChat({ prompt, timeoutMs });
                text = result.text;
                provider = 'gigachat';
                modelUsed = 'GigaChat-Max'; // фиксированная модель клиента gigachat.js
                usage = result.usage || null;
                circuitBreaker.success('gigachat');
                logFn('info', 'GigaChat success', { latencyMs: Date.now() - gigaStart, model: modelUsed, usage });
            } catch (err) {
                circuitBreaker.failure('gigachat', err);
                const msg = String(err.message).slice(0, 120);
                errorLog.push({ provider: 'gigachat', error: msg });
                logFn('warn', 'GigaChat failed', { error: msg });
            }
        } else {
            const msg = `skipped (CB: ${gigaCB.state})`;
            circuitSkipped = (circuitSkipped ? circuitSkipped + ',' : '') + 'gigachat';
            errorLog.push({ provider: 'gigachat', error: msg });
            logFn('warn', 'GigaChat skipped by Circuit Breaker', { state: gigaCB.state });
        }
    }

    // ── Попытка 3: Cache ────────────────────────
    if (!text) {
        const cached = getCachedResponse(prompt);
        if (cached) {
            text = cached;
            provider = 'cache';
            logFn('info', 'Cache hit');
        }
    }

    // ── Fallback: все провайдеры недоступны ────
    if (!text) {
        text = 'Извините, все AI-провайдеры временно недоступны. Пожалуйста, попробуйте позже.';
        provider = 'unavailable';
        logFn('error', 'All providers exhausted', { circuitSkipped });
    }

    // ── Кэшируем успешный ответ ────────────────
    if (provider !== 'cache' && provider !== 'unavailable') {
        cacheResponse(prompt, text);
    }

    return {
        text,
        provider,
        model: modelUsed,
        usage,
        latencyMs: Date.now() - startTime,
        circuitSkipped: circuitSkipped || null,
        errorLog
    };
}

/**
 * Возвращает статус Circuit Breaker-ов.
 * @returns {Record<string, object>}
 */
export function circuitStatus() {
    return circuitBreaker.statusAll();
}

/**
 * Сбрасывает Circuit Breaker-ы в CLOSED.
 */
export function circuitReset() {
    circuitBreaker.resetAll();
}
