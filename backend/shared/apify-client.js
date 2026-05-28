// backend/shared/apify-client.js
// ESM — клиент Apify API
import { getSecrets } from './secrets.js';

const APIFY_BASE = 'https://api.apify.com/v2';

/**
 * Запускает актор синхронно и возвращает items датасета.
 * Используй для быстрых задач (< 2 мин): Marketplace, Image Gen.
 */
export async function runActor(actorId, input, options = {}) {
  const secrets = await getSecrets();
  const token = secrets.APIFY_API_TOKEN;
  if (!token) throw new Error('APIFY_API_TOKEN not set in Lockbox');

  const timeoutSecs = options.timeoutSecs ?? 120;
  const memoryMbytes = options.memoryMbytes;

  const params = new URLSearchParams({ timeout: String(timeoutSecs) });
  if (memoryMbytes != null) params.set('memory', String(memoryMbytes));
  const url = `${APIFY_BASE}/acts/${encodeURIComponent(actorId)}/run-sync-get-dataset-items?${params}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(input),
    signal: AbortSignal.timeout((timeoutSecs + 15) * 1000),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Apify ${actorId} error ${response.status}: ${err}`);
  }

  const items = await response.json();
  return Array.isArray(items) ? items : [];
}

/**
 * Запускает актор асинхронно. Для долгих задач (RAG, Newsletter).
 * @returns {string} runId — передай в getRunResults()
 */
export async function startActor(actorId, input, options = {}) {
  const secrets = await getSecrets();
  const token = secrets.APIFY_API_TOKEN;
  const memoryMbytes = options.memoryMbytes ?? 512;

  const response = await fetch(
    `${APIFY_BASE}/acts/${encodeURIComponent(actorId)}/runs?memory=${memoryMbytes}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(input),
    }
  );

  if (!response.ok) throw new Error(`Apify start error: ${response.status}`);
  const data = await response.json();
  return data.data.id;
}

/**
 * Получить статус + результаты по runId.
 * @returns {{ status: 'RUNNING'|'SUCCEEDED'|'FAILED', items: Array }}
 */
export async function getRunResults(runId) {
  // Защита от path-traversal: runId от Apify имеет формат [a-zA-Z0-9]+,
  // но мы не доверяем сторонним значениям. Жёсткая регэксп-валидация.
  if (!/^[a-zA-Z0-9]+$/.test(runId)) {
    throw new Error(`Invalid runId format: ${String(runId).slice(0, 40)}`);
  }

  const secrets = await getSecrets();
  const token = secrets.APIFY_API_TOKEN;
  const authHeaders = { 'Authorization': `Bearer ${token}` };

  const statusRes = await fetch(`${APIFY_BASE}/actor-runs/${encodeURIComponent(runId)}`, { headers: authHeaders });
  const statusData = await statusRes.json();
  const status = statusData.data.status;

  if (status !== 'SUCCEEDED') return { status, items: [] };

  const datasetId = statusData.data.defaultDatasetId;
  if (!/^[a-zA-Z0-9]+$/.test(datasetId)) {
    throw new Error(`Invalid datasetId from Apify: ${String(datasetId).slice(0, 40)}`);
  }
  const itemsRes = await fetch(`${APIFY_BASE}/datasets/${encodeURIComponent(datasetId)}/items`, { headers: authHeaders });
  const items = await itemsRes.json();
  return { status, items };
}