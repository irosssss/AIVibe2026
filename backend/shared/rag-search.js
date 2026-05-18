// backend/shared/rag-search.js
// Поиск по RAG (cosine similarity) — ESM

import { getEmbedding } from './yandexgpt.js';
import { ydbClient } from './ydb-client.js';

export async function searchRAG(query, topK = 3) {
  try {
    const queryEmbedding = await getEmbedding(query);
    const allChunks = await ydbClient.scan('rag_chunks', { limit: 500 });

    const scored = allChunks.map(chunk => ({
      ...chunk,
      score: cosineSimilarity(queryEmbedding, JSON.parse(chunk.embedding)),
    }));

    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, topK).map(c => c.content);
  } catch (err) {
    console.error('RAG search failed (non-fatal):', err.message);
    return [];
  }
}

function cosineSimilarity(a, b) {
  const dot = a.reduce((sum, v, i) => sum + v * b[i], 0);
  const magA = Math.sqrt(a.reduce((sum, v) => sum + v * v, 0));
  const magB = Math.sqrt(b.reduce((sum, v) => sum + v * v, 0));
  return magA && magB ? dot / (magA * magB) : 0;
}
