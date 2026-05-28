// backend/shared/rate-limit.js
// Лёгкий in-memory fixed-window rate limiter (без внешних зависимостей).
//
// ⚠️ Состояние per-instance: на холодных стартах Yandex Cloud Function
// сбрасывается, поэтому распределённый обход возможен. Это INTERIM-защита (#17);
// постоянное состояние (YDB/Redis) и привязка к verified userId из JWT — позже.
//
// Назначение: ограничить cost-amplification, когда атакующий ротирует userId
// в теле запроса. Лимит по IP закрывает основной канал такой ротации.

/**
 * Создаёт независимый лимитер с собственным in-memory стором.
 * @param {{ max: number, windowMs?: number }} opts
 * @returns {(key: string) => { allowed: boolean, remaining: number }}
 */
export function createRateLimiter({ max, windowMs = 60_000 }) {
  const store = new Map();
  return function check(key) {
    const now = Date.now();
    const entry = store.get(key);
    if (!entry || now > entry.resetAt) {
      store.set(key, { count: 1, resetAt: now + windowMs });
      return { allowed: true, remaining: max - 1 };
    }
    if (entry.count >= max) return { allowed: false, remaining: 0 };
    entry.count++;
    return { allowed: true, remaining: Math.max(0, max - entry.count) };
  };
}

/**
 * Достаёт IP клиента из события Yandex Cloud Function (разные форматы шлюза).
 * @param {object} event
 * @returns {string}
 */
export function clientIp(event) {
  const fromCtx = event?.requestContext?.identity?.sourceIp;
  if (typeof fromCtx === 'string' && fromCtx.length > 0) return fromCtx;
  const xff = event?.headers?.['X-Forwarded-For'] ?? event?.headers?.['x-forwarded-for'];
  if (typeof xff === 'string' && xff.length > 0) return xff.split(',')[0].trim();
  return 'unknown';
}
