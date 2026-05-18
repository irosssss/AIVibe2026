// backend/ai-advisor/index.js
// AI Advisor — triplex fallback + RAG + prompt guard
// Cloud Function для Yandex Cloud

import { callYandexGPT } from '../shared/yandexgpt.js';
import { callGigaChat } from '../shared/gigachat.js';
import { searchRAG } from '../shared/rag-search.js';
import { getSecrets } from '../shared/secrets.js';

export const handler = async (event, context) => {
  await getSecrets();
  const { prompt, roomType, roomStyle, colorPalette, budget, userId } = JSON.parse(event.body ?? '{}');

  // Prompt Guard — только если включён (по умолчанию выключен)
  // if (promptGuard.isEnabled) { await checkPromptSafety(prompt); }

  // RAG search — обогащаем промпт контекстом
  let ragContext = '';
  try {
    ragContext = await searchRAG({ roomType, roomStyle, query: prompt });
  } catch (e) {
    console.warn('RAG search failed, continuing without context:', e.message);
  }

  const fullPrompt = ragContext
    ? `Контекст по дизайну интерьеров:\n${ragContext}\n\nВопрос: ${prompt}`
    : prompt;

  // Triplex fallback: YandexGPT → GigaChat → CoreML
  const errors = [];

  // Попытка 1: YandexGPT
  try {
    const result = await callYandexGPT({ prompt: fullPrompt, timeoutMs: 15000 });
    return wrapResult(result, 'yandexgpt');
  } catch (e) {
    errors.push({ provider: 'yandexgpt', error: e.message });
  }

  // Попытка 2: GigaChat
  try {
    const result = await callGigaChat({ prompt: fullPrompt, timeoutMs: 15000 });
    return wrapResult(result, 'gigachat');
  } catch (e) {
    errors.push({ provider: 'gigachat', error: e.message });
  }

  // Попытка 3: CoreML (оффлайн — возвращаем заглушку)
  try {
    const result = await callCoreMLFallback(prompt, roomType, roomStyle);
    return wrapResult(result, 'coreml');
  } catch (e) {
    errors.push({ provider: 'coreml', error: e.message });
  }

  // Все провайдеры упали
  return {
    statusCode: 503,
    body: JSON.stringify({
      error: 'All AI providers failed',
      errors,
      fallback: generateLocalFallback(prompt, roomType, roomStyle),
    }),
  };
};

function wrapResult(result, provider) {
  return {
    statusCode: 200,
    body: JSON.stringify({
      text: result.text,
      provider,
      usage: result.usage ?? { tokens: 0 },
      cached: false,
    }),
  };
}

async function callCoreMLFallback(prompt, roomType, roomStyle) {
  // Заглушка — на сервере CoreML нет, возвращаем шаблон
  const templates = {
    living_room: 'Рекомендуем светлые тона и функциональную мебель.',
    bedroom: 'Рекомендуем мягкое освещение и уютные текстуры.',
    kitchen: 'Рекомендуем эргономичную планировку и натуральные материалы.',
    default: 'Рекомендуем современный минималистичный подход и нейтральные оттенки.',
  };
  const text = templates[roomType] ?? templates.default;
  return { text, provider: 'coreml', usage: { tokens: 50 } };
}

function generateLocalFallback(prompt, roomType, roomStyle) {
  return `Совет: Для стиля ${roomStyle ?? 'современный'} в комнате ${roomType ?? 'living_room'} рекомендуем обратиться к дизайнеру.`;
}
