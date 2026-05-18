// backend/functions/rag-indexer/index.js
// Запускается по расписанию 1 раз в день в 03:00 МСК
// Использует Web Fetcher из mega-list: agents-apis-697/ → ищи "web fetcher markdown"

import { runActor } from '../../shared/apify-client.js';
import { getEmbedding } from '../../shared/yandexgpt.js';
import { ydbClient } from '../../shared/ydb-client.js';
import { getSecrets } from '../../shared/secrets.js';

const DESIGN_SOURCES = [
  'https://www.houzz.ru/magazine',
  'https://design-mate.ru',
  'https://www.admagazine.ru/interior',
];

export const handler = async (event, context) => {
  await getSecrets();
  let totalChunks = 0;

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
        const chunks = splitChunks(page.markdown, 2000);

        for (const chunk of chunks) {
          const embedding = await getEmbedding(chunk);
          await ydbClient.upsert('rag_chunks', {
            id: Buffer.from(url + chunk.slice(0, 40)).toString('base64').slice(0, 32),
            source_url: url,
            content: chunk,
            embedding: JSON.stringify(embedding),
            category: detectCategory(chunk),
            created_at: new Date().toISOString(),
          });
          totalChunks++;
        }
      }
    } catch (err) {
      console.error(`Failed to index ${url}:`, err.message);
    }
  }

  return { statusCode: 200, body: JSON.stringify({ indexed: totalChunks }) };
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

function detectCategory(text) {
  const t = text.toLowerCase();
  if (t.includes('гостиная') || t.includes('диван')) return 'living_room';
  if (t.includes('спальня') || t.includes('кровать')) return 'bedroom';
  if (t.includes('кухня')) return 'kitchen';
  if (t.includes('цвет') || t.includes('палитра')) return 'color';
  return 'general';
}