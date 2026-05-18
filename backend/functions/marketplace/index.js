// backend/functions/marketplace/index.js
// Новая Cloud Function — не пересекается с ai-advisor из SESSION_04

import { runActor } from '../../shared/apify-client.js';
import { callYandexGPT } from '../../shared/yandexgpt.js';
import { getSecrets } from '../../shared/secrets.js';

export const handler = async (event, context) => {
  await getSecrets();

  const body = JSON.parse(event.body ?? '{}');
  const { query, roomStyle, budget, userId } = body;

  if (!query || !userId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'query and userId required' }) };
  }

  // 1. Найти актор в mega-list: agents-apis-697/README.md → ищи "product recommendation"
  const recommendations = await runActor(
    'apify/product-recommendation-agent', // ← заменить на ID из mega-list
    {
      query: `${query} для интерьера в стиле ${roomStyle ?? 'современный'}`,
      maxResults: 10,
      language: 'ru',
      marketplaces: ['wildberries.ru', 'ozon.ru'],
    },
    { timeoutSecs: 60, memoryMbytes: 512 }
  );

  // 2. Фильтр по бюджету
  const filtered = budget
    ? recommendations.filter(r => !r.price || r.price <= budget)
    : recommendations;

  // 3. AI-объяснение через YandexGPT (уже используется в SESSION_04)
  const enriched = await enrichWithYandexGPT(filtered, query, roomStyle);

  return {
    statusCode: 200,
    body: JSON.stringify({ products: enriched }),
  };
};

async function enrichWithYandexGPT(products, query, roomStyle) {
  if (products.length === 0) return [];

  const list = products.slice(0, 5)
    .map((p, i) => `${i + 1}. ${p.name} — ${p.price ?? '?'} руб.`)
    .join('\n');

  // Промпт — СОГЛАСОВАН с DesignStyle.promptModifier из SESSION_05
  const prompt = `Ты эксперт по дизайну интерьеров (стиль: ${roomStyle ?? 'современный'}).
Клиент ищет: "${query}".

Товары:
${list}

Для каждого — одно предложение: подходит или нет для этого стиля, и почему.
Формат: "1. [причина]"`;

  try {
    const result = await callYandexGPT({ prompt });
    return products.map((p, i) => ({
      ...p,
      aiReason: extractLine(result.text, i + 1),
    }));
  } catch {
    return products; // fallback без AI-объяснений
  }
}

function extractLine(text, n) {
  const match = text.match(new RegExp(`${n}\\.\\s*(.+?)(?=\\d+\\.|$)`, 's'));
  return match?.[1]?.trim() ?? '';
}
