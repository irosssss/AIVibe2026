// backend/shared/model-router.js
// B7.1: роутер выбора модели YandexGPT — Lite (дёшево/быстро) vs Pro (умнее/дороже).
// Рычаг затрат: простые короткие вопросы не должны оплачиваться по тарифу Pro.
//
// Размещён ВНЕ ядра (рекомендация UPGRADE_PLAN): ядро (triplex-fallback,
// yandexgpt) только пробрасывает уже принятое решение, сама эвристика — здесь.
// Решение детерминировано по промпту, поэтому кэш triplex-fallback (ключ —
// промпт) остаётся корректным: один промпт → всегда одна и та же модель.

export const MODEL_PRO = 'pro';
export const MODEL_LITE = 'lite';

// Порог длины: длинный промпт = развёрнутое ТЗ, лучше отдаём Pro.
const LONG_PROMPT_CHARS = 600;

// Стемы «сложных» запросов: планирование, расчёты, сравнение вариантов —
// то, где Lite заметно слабее и экономия обернётся плохим ответом.
const COMPLEX_PATTERNS = [
  /расстановк|планировк|перепланировк|зонировани/iu, // пространственное планирование
  /бюджет|смет[ауыео]|стоимост|рассчит|расч[её]т/iu, // деньги и расчёты
  /дизайн-проект|проект\b/iu,                        // комплексный проект
  /сравни|альтернатив|вариант(?:а|ов|ы)\b/iu,        // сравнение вариантов
  /\d[\d\s.,]*(?:₽|руб|тыс|млн)/iu,                  // суммы в рублях
];

/**
 * Выбирает модель для запроса советника.
 * Классифицируется ИСХОДНЫЙ промпт пользователя (до RAG-обогащения!) —
 * иначе добавленные выдержки всегда уводили бы запрос в Pro по длине.
 *
 * @param {string} prompt — исходный промпт пользователя
 * @param {{ hasImage?: boolean }} [options]
 * @returns {{ model: 'pro'|'lite', reason: string }}
 */
export function selectModel(prompt, { hasImage = false } = {}) {
  if (hasImage) {
    return { model: MODEL_PRO, reason: 'image' }; // vision у Lite недоступен
  }
  if (prompt.length > LONG_PROMPT_CHARS) {
    return { model: MODEL_PRO, reason: 'long_prompt' };
  }
  if ((prompt.match(/\?/g) || []).length > 1) {
    return { model: MODEL_PRO, reason: 'multi_question' };
  }
  for (const pattern of COMPLEX_PATTERNS) {
    if (pattern.test(prompt)) {
      return { model: MODEL_PRO, reason: 'complex_topic' };
    }
  }
  return { model: MODEL_LITE, reason: 'simple_query' };
}
