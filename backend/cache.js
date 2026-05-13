// backend/cache.js
// In-memory cache for the last 50 AI responses.
// Key = first 50 chars of the prompt (normalised + trimmed).
// TTL = 1 hour.

const MAX_ENTRIES = 50;
const TTL_MS = 60 * 60 * 1000; // 1 час

/**
 * @typedef {{ text: string, provider: string, cachedAt: number }} CacheEntry
 */

/** @type {Map<string, CacheEntry>} */
const store = new Map();

/**
 * Нормализует промпт для использования в качестве ключа кэша.
 * Берёт первые 50 символов, приводит к нижнему регистру, обрезает пробелы.
 * @param {string} prompt
 * @returns {string}
 */
function makeKey(prompt) {
    return prompt.trim().toLowerCase().slice(0, 50);
}

/**
 * Возвращает кэшированный ответ, если есть и TTL не истёк.
 * @param {string} prompt
 * @returns {{ text: string, provider: string } | null}
 */
function get(prompt) {
    const key = makeKey(prompt);
    const entry = store.get(key);

    if (!entry) return null;

    const age = Date.now() - entry.cachedAt;
    if (age > TTL_MS) {
        store.delete(key);
        return null;
    }

    return { text: entry.text, provider: entry.provider };
}

/**
 * Сохраняет ответ в кэш.
 * При превышении MAX_ENTRIES удаляет самую старую запись.
 * @param {string} prompt
 * @param {string} text
 * @param {string} provider
 */
function set(prompt, text, provider) {
    if (store.size >= MAX_ENTRIES) {
        // Удаляем самую старую запись
        let oldestKey = null;
        let oldestTime = Infinity;

        for (const [k, v] of store) {
            if (v.cachedAt < oldestTime) {
                oldestTime = v.cachedAt;
                oldestKey = k;
            }
        }

        if (oldestKey) store.delete(oldestKey);
    }

    const key = makeKey(prompt);
    store.set(key, { text, provider, cachedAt: Date.now() });
}

/**
 * Очищает весь кэш (для тестов).
 */
function clear() {
    store.clear();
}

/**
 * Возвращает количество записей в кэше.
 * @returns {number}
 */
function size() {
    return store.size;
}

module.exports = { get, set, clear, size };
