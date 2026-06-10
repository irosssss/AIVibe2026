// backend/shared/rag-search.js
// Поиск по RAG-знаниям дизайна (B6, Фаза 2).
//
// Было: full-scan до 500 чанков ЦЕЛИКОМ (включая эмбеддинги — мегабайты на
// каждый запрос) + косинус по всем в Node. Нарушало правило «не тащить таблицу
// в функцию».
//
// Стало: пре-фильтр на стороне YDB (FilterExpression по category — категорию
// запроса определяет та же эвристика, что размечала чанки при индексации) +
// ProjectionExpression (только content и embedding) + постраничный сбор с
// потолком. Косинусное ранжирование осталось в Node, но уже по малому набору
// кандидатов: настоящий KNN через Document API недоступен (нет YQL/Knn:: —
// вердикт PoC B5 в docs/UPGRADE_PLAN.md).

import { getEmbedding } from './yandexgpt.js';
import { ydbClient } from './ydb-client.js';
import { detectCategory, GENERAL_CATEGORY } from './rag-category.js';

const CHUNKS_TABLE = 'rag_chunks';
const PAGE_LIMIT = 100;      // записей сканируется за страницу (фильтр — после чтения)
const MAX_PAGES = 8;         // потолок страниц — ограничивает худший случай
const CANDIDATE_TARGET = 48; // кандидатов достаточно для ранжирования topK ≤ 5

/**
 * Возвращает topK самых релевантных запросу фрагментов дизайн-знаний.
 * Любая ошибка не фатальна: RAG — обогащение контекста, не критический путь.
 * @param {string} query
 * @param {number} [topK=3]
 * @returns {Promise<string[]>}
 */
export async function searchRAG(query, topK = 3) {
  try {
    const queryEmbedding = await getEmbedding(query);
    const candidates = await fetchCandidates(detectCategory(query));

    const scored = [];
    for (const chunk of candidates) {
      const embedding = parseEmbedding(chunk.embedding);
      // Битый JSON или эмбеддинг другой размерности — чанк пропускаем.
      if (!embedding || embedding.length !== queryEmbedding.length) continue;
      scored.push({
        content: chunk.content,
        score: cosineSimilarity(queryEmbedding, embedding),
      });
    }

    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, topK).map(c => c.content);
  } catch (err) {
    console.error('RAG search failed (non-fatal):', err.message);
    return [];
  }
}

/**
 * Собирает кандидатов с пре-фильтром по категории на стороне YDB.
 * Тематический запрос ищет в своей категории + general (категория могла быть
 * распознана неточно при индексации); нераспознанный — без фильтра, но в тех
 * же пределах страниц.
 */
async function fetchCandidates(category) {
  const base = {
    projection: '#content, #embedding',
    names: { '#content': 'content', '#embedding': 'embedding' },
    pageLimit: PAGE_LIMIT,
    maxPages: MAX_PAGES,
    targetCount: CANDIDATE_TARGET,
  };

  if (category === GENERAL_CATEGORY) {
    return ydbClient.scanFiltered(CHUNKS_TABLE, base);
  }

  return ydbClient.scanFiltered(CHUNKS_TABLE, {
    ...base,
    names: { ...base.names, '#category': 'category' },
    filterExpression: '#category = :cat OR #category = :gen',
    values: { cat: category, gen: GENERAL_CATEGORY },
  });
}

/** Эмбеддинг хранится JSON-строкой (см. rag-indexer) — парсим с защитой. */
function parseEmbedding(raw) {
  if (typeof raw !== 'string') return null;
  try {
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? arr : null;
  } catch {
    return null;
  }
}

function cosineSimilarity(a, b) {
  const dot = a.reduce((sum, v, i) => sum + v * b[i], 0);
  const magA = Math.sqrt(a.reduce((sum, v) => sum + v * v, 0));
  const magB = Math.sqrt(b.reduce((sum, v) => sum + v * v, 0));
  return magA && magB ? dot / (magA * magB) : 0;
}
