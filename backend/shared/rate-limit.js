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
 * Достаёт IP клиента из события Yandex Cloud Function.
 *
 * Используем ТОЛЬКО доверенное платформенное поле requestContext.identity.sourceIp.
 * X-Forwarded-For намеренно НЕ используем: Yandex сохраняет присланный клиентом
 * XFF, поэтому первый хоп — под контролем клиента и позволял бы обойти IP-лимит
 * ротацией заголовка (Codex P1). Если sourceIp отсутствует — общий bucket
 * 'unknown' (over-restrictive, но не обходится).
 * @param {object} event
 * @returns {string}
 */
export function clientIp(event) {
  const ip = event?.requestContext?.identity?.sourceIp;
  return (typeof ip === 'string' && ip.length > 0) ? ip : 'unknown';
}
