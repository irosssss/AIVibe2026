// backend/shared/circuit-config.js
// Единый источник констант Circuit Breaker для всех JS-провайдеров.
// Синхронизировать с AIVibe/Core/AI/CircuitBreakerConfig.swift

/** Количество ошибок до размыкания */
export const CIRCUIT_THRESHOLD = 3;

/** Время в мс в состоянии OPEN, после которого делается пробный запрос (HALF_OPEN) */
export const CIRCUIT_COOLDOWN_MS = 5 * 60_000; // 5 минут

/** Время в мс между пробными запросами в HALF_OPEN (не используется, оставлено для совместимости) */
export const CIRCUIT_PROBE_MS = 60_000;

/** Имена провайдеров, отслеживаемых Circuit Breaker */
export const CIRCUIT_PROVIDERS = ['yandexgpt', 'gigachat'];
