// backend/shared/circuit-breaker.js
// Единая реализация Circuit Breaker для всех JS-провайдеров.
// Константы (threshold, cooldown) — из circuit-config.js.
// Синхронизировать с AIVibe/Core/AI/CircuitBreaker.swift

import { CIRCUIT_THRESHOLD, CIRCUIT_COOLDOWN_MS, CIRCUIT_PROVIDERS } from './circuit-config.js';

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

export class CircuitBreaker {
    /** @type {Map<string, CircuitEntry>} */
    #circuitMap;

    constructor() {
        this.#circuitMap = new Map(
            CIRCUIT_PROVIDERS.map(name => [name, this.#createCircuit()])
        );
    }

    /**
     * Создаёт новую запись Circuit Breaker в состоянии CLOSED.
     * @returns {CircuitEntry}
     */
    #createCircuit() {
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
     * @param {string} provider
     * @returns {{ allowed: boolean, state: CircuitState }}
     */
    allowed(provider) {
        const c = this.#circuitMap.get(provider);
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
    success(provider) {
        const c = this.#circuitMap.get(provider);
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
    failure(provider, err) {
        const c = this.#circuitMap.get(provider);
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
    statusAll() {
        /** @type {Record<string, object>} */
        const status = {};
        for (const [name, c] of this.#circuitMap) {
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

    /**
     * Сбрасывает все Circuit Breaker-ы в CLOSED.
     */
    resetAll() {
        for (const [name] of this.#circuitMap) {
            this.#circuitMap.set(name, this.#createCircuit());
        }
        console.log('[circuit] All circuit breakers reset to CLOSED');
    }
}
