// backend/shared/rag-category.js
// Единая эвристика категорий дизайн-знаний.
// Используется в двух местах и обязана совпадать:
//   - rag-indexer — категория записывается в каждый чанк при индексации;
//   - rag-search — категория запроса определяет пре-фильтр на стороне YDB.
// Расхождение эвристик = пустая выдача поиска, поэтому копий быть не должно.

export const GENERAL_CATEGORY = 'general';

/**
 * Определяет категорию дизайн-текста по ключевым стемам.
 * Стемы (а не словоформы) — чтобы покрыть склонения: «кухня/кухни/кухню»,
 * «спальня/спальне» и т.д. Это важно для поисковых запросов пользователя.
 * @param {string} text
 * @returns {string} living_room | bedroom | kitchen | color | general
 */
export function detectCategory(text) {
    const t = String(text ?? '').toLowerCase();
    if (t.includes('гостин') || t.includes('диван')) return 'living_room';
    if (t.includes('спальн') || t.includes('кроват')) return 'bedroom';
    if (t.includes('кухн')) return 'kitchen';
    if (t.includes('цвет') || t.includes('палитр')) return 'color';
    return GENERAL_CATEGORY;
}
