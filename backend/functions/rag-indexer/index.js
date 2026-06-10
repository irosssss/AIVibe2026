// backend/functions/rag-indexer/index.js
// Запускается по расписанию 1 раз в день в 03:00 МСК
// Использует Web Fetcher из mega-list: agents-apis-697/ → ищи "web fetcher markdown"

import { runActor } from '../../shared/apify-client.js';
import { getEmbedding } from '../../shared/yandexgpt.js';
import { ydbClient } from '../../shared/ydb-client.js';
import { getSecrets } from '../../shared/secrets.js';
import { guardPrompt } from '../../shared/promptGuard.js';
import { detectCategory } from '../../shared/rag-category.js';

const DESIGN_SOURCES = [
  'https://www.houzz.ru/magazine',
  'https://design-mate.ru',
  'https://www.admagazine.ru/interior',
];

// Whitelist хостов: краулер ходит по ссылкам и может уйти на чужой домен.
// Индексируем только страницы с доверенных дизайн-источников.
const ALLOWED_HOSTS = new Set(DESIGN_SOURCES.map(u => new URL(u).hostname));

function isAllowedHost(pageUrl) {
  try {
    return ALLOWED_HOSTS.has(new URL(pageUrl).hostname);
  } catch {
    return false;
  }
}

// Срезает невидимые символы, которыми можно спрятать инструкции в краулёном
// контенте: Unicode tag block (ASCII smuggling), zero-width, bidi, control C0/C1.
function sanitizeForIndex(text) {
  return text
    .replace(/[\u{E0000}-\u{E007F}]/gu, '')                       // Unicode tag block
    .replace(/[\u200B-\u200D\uFEFF]/g, '')                       // zero-width + BOM
    .replace(/[\u202A-\u202E\u2066-\u2069]/g, '')               // bidi overrides
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g, ''); // control
}

export const handler = async (event, context) => {
  await getSecrets();
  let totalChunks = 0;
  let skippedChunks = 0;

  for (const url of DESIGN_SOURCES) {
    try {
      const pages = await runActor(
        'misceres/web-fetcher',
        {
          startUrls: [{ url }],
          maxCrawlPages: 8,
          outputFormat: 'markdown',
          removeNavigation: true,
        },
        { timeoutSecs: 180, memoryMbytes: 512 }
      );

      for (const page of pages) {
        if (!page.markdown || page.markdown.length < 100) continue;

        // Whitelist: не индексируем страницы, на которые краулер ушёл за домен.
        const pageUrl = page.url || url;
        if (!isAllowedHost(pageUrl)) {
          console.warn(`[rag] skip off-domain page: ${String(pageUrl).slice(0, 120)}`);
          continue;
        }

        const chunks = splitChunks(sanitizeForIndex(page.markdown), 2000);

        // Отбрасываем чанки с известными injection-паттернами (RAG poisoning):
        // их нельзя класть в индекс — позже они попадут в контекст LLM.
        const cleanChunks = chunks.filter(chunk => {
          if (guardPrompt(chunk).allowed) return true;
          skippedChunks++;
          return false;
        });

        // Параллельные эмбеддинги — убираем N+1 serial bottleneck
        // Лимит 10 параллельных запросов к embedding API
        const embeddings = await parallelLimit(
          cleanChunks,
          10,
          chunk => getEmbedding(chunk).catch(err => {
            console.error(`Embedding failed for chunk of ${pageUrl}:`, err.message);
            return null;
          })
        );

        for (let i = 0; i < cleanChunks.length; i++) {
          const embedding = embeddings[i];
          if (!embedding) continue; // skip failed embeddings
          await ydbClient.upsert('rag_chunks', {
            id: Buffer.from(pageUrl + cleanChunks[i].slice(0, 40)).toString('base64').slice(0, 32),
            source_url: pageUrl,
            content: cleanChunks[i],
            embedding: JSON.stringify(embedding),
            category: detectCategory(cleanChunks[i]),
            created_at: new Date().toISOString(),
          });
          totalChunks++;
        }
      }
    } catch (err) {
      console.error(`Failed to index ${url}:`, err.message);
    }
  }

  return { statusCode: 200, body: JSON.stringify({ indexed: totalChunks, skipped: skippedChunks }) };
};

function splitChunks(text, maxChars) {
  const chunks = [];
  const paragraphs = text.split('\n\n');
  let current = '';
  for (const p of paragraphs) {
    if (current.length + p.length > maxChars && current.length > 50) {
      chunks.push(current.trim());
      current = '';
    }
    current += p + '\n\n';
  }
  if (current.trim().length > 50) chunks.push(current.trim());
  return chunks;
}

/**
 * Выполняет limit параллельных промисов из tasks.
 * @template T
 * @param {T[]} items
 * @param {number} limit
 * @param {(item: T) => Promise<any>} fn
 * @returns {Promise<Array<any>>}
 */
async function parallelLimit(items, limit, fn) {
  const results = new Array(items.length);
  let cursor = 0;

  async function worker() {
    while (cursor < items.length) {
      const idx = cursor++;
      results[idx] = await fn(items[idx]);
    }
  }

  const workers = Array.from({ length: Math.min(limit, items.length) }, () => worker());
  await Promise.all(workers);
  return results;
}
