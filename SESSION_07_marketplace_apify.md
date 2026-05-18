# СЕССИЯ 7 — Marketplace + Apify Integration

> Добавь в контекст: `@PROJECT_RULES.md` `@SESSION_02_ai_router.md` `@SESSION_04_backend.md` `@SESSION_05_ai_advisor.md`
> Режим: Agent

---

## Что уже есть (НЕ трогать)

| Файл | Сессия | Статус |
|---|---|---|
| `Core/AI/AIProviderRouter.swift` | SESSION_02 | ✅ готов |
| `backend/functions/ai-advisor/index.js` | SESSION_04 | ✅ готов — **только патч** |
| `Features/AIAdvisor/Models/DesignAdvice.swift` | SESSION_05 | ✅ есть `FurniturePiece.marketplace` |
| `Features/AIAdvisor/AIAdvisorClient.swift` | SESSION_05 | ✅ готов — **только патч** |
| `Features/AIAdvisor/Models/DesignRequest.swift` | SESSION_05 | ✅ есть `buildYandexGPTPrompt()` |

## Что создаём в этой сессии (всё новое)

```
backend/
└── shared/
    ├── apify-client.js          ← НОВЫЙ
    └── rag-search.js            ← НОВЫЙ
└── functions/
    ├── marketplace/
    │   └── index.js             ← НОВЫЙ
    ├── rag-indexer/
    │   └── index.js             ← НОВЫЙ
    ├── image-gen/
    │   └── index.js             ← НОВЫЙ
    └── newsletter/
        └── index.js             ← НОВЫЙ

AIVibe/Features/
└── Marketplace/
    ├── MarketplaceFeature.swift  ← НОВЫЙ (Session_05 уже готовит FurniturePiece.marketplace)
    └── MarketplaceView.swift     ← НОВЫЙ

AIVibe/Features/ARDesigner/
└── ImageGenClient.swift          ← НОВЫЙ (рядом с SESSION_03 файлами, не конфликтует)
```

---

## Часть 1 — Apify API Token (один раз)

1. Регистрация: https://apify.com → бесплатный план ($5 кредитов/мес)
2. Settings → Integrations → API token → скопировать
3. Добавить в Yandex Lockbox (к существующим секретам из SESSION_04):

```bash
# Добавить к существующему секрету aivibe-secrets
yc lockbox secret add-version \
  --id <твой-lockbox-secret-id> \
  --payload '[{"key":"APIFY_API_TOKEN","textValue":"apify_api_xxx"}]'
```

4. Обновить `backend/shared/secrets.js` (файл из SESSION_04) — добавить одну строку:

```javascript
// В существующий объект REQUIRED_SECRETS добавить:
APIFY_API_TOKEN: process.env.APIFY_API_TOKEN,
```

---

## Часть 2 — `backend/shared/apify-client.js` (НОВЫЙ файл)

```javascript
// backend/shared/apify-client.js

const APIFY_BASE = 'https://api.apify.com/v2';

/**
 * Запускает актор синхронно и возвращает items датасета.
 * Используй для быстрых задач (< 2 мин): Marketplace, Image Gen.
 */
async function runActor(actorId, input, options = {}) {
  const token = process.env.APIFY_API_TOKEN;
  if (!token) throw new Error('APIFY_API_TOKEN not set in Lockbox');

  const timeoutSecs = options.timeoutSecs ?? 120;
  const memoryMbytes = options.memoryMbytes ?? 256;

  const url = `${APIFY_BASE}/acts/${encodeURIComponent(actorId)}/run-sync-get-dataset-items` +
    `?token=${token}&timeout=${timeoutSecs}&memory=${memoryMbytes}`;

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
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
 * Запускает актор асинхронно. Используй для долгих задач (RAG, Newsletter).
 * @returns {string} runId — передай в getRunResults()
 */
async function startActor(actorId, input, options = {}) {
  const token = process.env.APIFY_API_TOKEN;
  const memoryMbytes = options.memoryMbytes ?? 512;

  const response = await fetch(
    `${APIFY_BASE}/acts/${encodeURIComponent(actorId)}/runs?token=${token}&memory=${memoryMbytes}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
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
async function getRunResults(runId) {
  const token = process.env.APIFY_API_TOKEN;

  const statusRes = await fetch(`${APIFY_BASE}/actor-runs/${runId}?token=${token}`);
  const statusData = await statusRes.json();
  const status = statusData.data.status;

  if (status !== 'SUCCEEDED') return { status, items: [] };

  const datasetId = statusData.data.defaultDatasetId;
  const itemsRes = await fetch(`${APIFY_BASE}/datasets/${datasetId}/items?token=${token}`);
  const items = await itemsRes.json();
  return { status, items };
}

module.exports = { runActor, startActor, getRunResults };
```

---

## Часть 3 — Marketplace

### `backend/functions/marketplace/index.js` (НОВЫЙ)

```javascript
// backend/functions/marketplace/index.js
// Новая Cloud Function — не пересекается с ai-advisor из SESSION_04

const { runActor } = require('../../shared/apify-client');
const { callYandexGPT } = require('../../shared/yandexgpt'); // уже есть из SESSION_04
const { getSecrets } = require('../../shared/secrets');      // уже есть из SESSION_04

module.exports.handler = async (event, context) => {
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
    const response = await callYandexGPT(prompt);
    return products.map((p, i) => ({
      ...p,
      aiReason: extractLine(response, i + 1),
    }));
  } catch {
    return products; // fallback без AI-объяснений
  }
}

function extractLine(text, n) {
  const match = text.match(new RegExp(`${n}\\.\\s*(.+?)(?=\\d+\\.|$)`, 's'));
  return match?.[1]?.trim() ?? '';
}
```

### iOS: `AIVibe/Features/Marketplace/MarketplaceFeature.swift` (НОВЫЙ)

**Важно:** `FurniturePiece.marketplace` уже определён в `DesignAdvice.swift` (SESSION_05).
`MarketplaceFeature` использует его как точку входа — не дублируй структуру.

```swift
// AIVibe/Features/Marketplace/MarketplaceFeature.swift
// Связан с SESSION_05: FurniturePiece.marketplace → открывает этот экран

import ComposableArchitecture
import Foundation

// Отдельная модель для Marketplace (не путать с FurniturePiece из SESSION_05)
struct MarketplaceProduct: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let price: Double?
    let url: URL
    let imageURL: URL?
    let aiReason: String       // от YandexGPT
    let marketplace: String    // "wildberries" | "ozon"
}

@Reducer
struct MarketplaceFeature {
    @ObservableState
    struct State: Equatable {
        var products: [MarketplaceProduct] = []
        var isLoading = false
        var query = ""
        // Переиспользуем DesignStyle из SESSION_05 — не дублируем enum
        var selectedStyle: DesignStyle = .modern
        var budget: Double? = nil
        var error: String? = nil

        // Если пришли из AIAdvisor (SESSION_05) — prefill запроса
        var prefillFromAdvice: DesignAdvice? = nil
    }

    enum Action {
        case appeared                          // если prefillFromAdvice != nil — сразу поиск
        case searchTapped
        case queryChanged(String)
        case styleChanged(DesignStyle)         // DesignStyle из SESSION_05
        case budgetChanged(Double?)
        case productsLoaded(Result<[MarketplaceProduct], Error>)
        case productTapped(MarketplaceProduct) // открыть URL
        case dismissError
    }

    @Dependency(\.marketplaceClient) var client
    @Dependency(\.openURL) var openURL         // стандартная TCA dependency

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .appeared:
                // Если пришли из DesignResultView (SESSION_05) с готовым советом
                if let advice = state.prefillFromAdvice {
                    state.query = advice.furniturePieces.first?.name ?? ""
                    state.selectedStyle = advice.style
                    return .send(.searchTapped)
                }
                return .none

            case .searchTapped:
                guard !state.query.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                state.error = nil

                let query = state.query
                let style = state.selectedStyle.rawValue
                let budget = state.budget

                return .run { send in
                    let result = await Result {
                        try await client.recommend(query: query, style: style, budget: budget)
                    }
                    await send(.productsLoaded(result))
                }

            case let .queryChanged(q):
                state.query = q
                return .none

            case let .styleChanged(s):
                state.selectedStyle = s
                return .none

            case let .budgetChanged(b):
                state.budget = b
                return .none

            case let .productsLoaded(.success(products)):
                state.isLoading = false
                state.products = products
                return .none

            case let .productsLoaded(.failure(err)):
                state.isLoading = false
                state.error = err.localizedDescription
                return .none

            case let .productTapped(product):
                return .run { _ in await openURL(product.url) }

            case .dismissError:
                state.error = nil
                return .none
            }
        }
    }
}

// MARK: — Client

struct MarketplaceClient {
    var recommend: @Sendable (_ query: String, _ style: String, _ budget: Double?) async throws -> [MarketplaceProduct]
}

extension MarketplaceClient: DependencyKey {
    static let liveValue = MarketplaceClient(
        recommend: { query, style, budget in
            guard let url = URL(string: "https://functions.yandexcloud.net/YOUR_MARKETPLACE_FUNCTION_ID") else {
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "query": query,
                "roomStyle": style,
                "budget": budget as Any,
                "userId": "current_user_id",
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 90

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            struct Response: Codable { let products: [MarketplaceProduct] }
            return try JSONDecoder().decode(Response.self, from: data).products
        }
    )

    static let testValue = MarketplaceClient(
        recommend: { _, _, _ in
            [MarketplaceProduct(
                id: "1",
                name: "Диван Осло 3-местный",
                price: 45990,
                url: URL(string: "https://wildberries.ru")!,
                imageURL: nil,
                aiReason: "Скандинавский дизайн идеально подходит для выбранного стиля",
                marketplace: "wildberries"
            )]
        }
    )
}

extension DependencyValues {
    var marketplaceClient: MarketplaceClient {
        get { self[MarketplaceClient.self] }
        set { self[MarketplaceClient.self] = newValue }
    }
}
```

---

## Часть 4 — RAG для AIAdvisor

### `backend/shared/rag-search.js` (НОВЫЙ)

```javascript
// backend/shared/rag-search.js
const { getEmbedding } = require('./yandexgpt'); // уже есть из SESSION_04
const { ydbClient } = require('./ydb-client');   // уже есть из SESSION_04

async function searchRAG(query, topK = 3) {
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
    return []; // без RAG — нормально работаем
  }
}

function cosineSimilarity(a, b) {
  const dot = a.reduce((sum, v, i) => sum + v * b[i], 0);
  const magA = Math.sqrt(a.reduce((sum, v) => sum + v * v, 0));
  const magB = Math.sqrt(b.reduce((sum, v) => sum + v * v, 0));
  return magA && magB ? dot / (magA * magB) : 0;
}

module.exports = { searchRAG };
```

### Патч `backend/functions/ai-advisor/index.js` (SESSION_04 файл)

Добавь только эти строки — всё остальное в файле не трогай:

```javascript
// ШАГ 1: В самом начале файла добавить import:
const { searchRAG } = require('../../shared/rag-search'); // ← НОВАЯ строка

// ШАГ 2: В handler, ПОСЛЕ строки `await getSecrets();`, ПЕРЕД вызовом YandexGPT:
const ragContext = await searchRAG(prompt, 3); // ← НОВАЯ строка

// ШАГ 3: Найди строку где строится prompt для YandexGPT и замени ТОЛЬКО её:
// БЫЛО:
const finalPrompt = prompt;
// СТАЛО:
const ragBlock = ragContext.length > 0
  ? `\n\nАктуальные знания о дизайне интерьеров:\n---\n${ragContext.join('\n---\n')}\n---\n`
  : '';
const finalPrompt = ragBlock + prompt;
// Затем везде используй finalPrompt вместо prompt при вызове YandexGPT
```

### `backend/functions/rag-indexer/index.js` (НОВЫЙ)

```javascript
// backend/functions/rag-indexer/index.js
// Запускается по расписанию 1 раз в день в 03:00 МСК
// Использует Web Fetcher из mega-list: agents-apis-697/ → ищи "web fetcher markdown"

const { runActor } = require('../../shared/apify-client');
const { getEmbedding } = require('../../shared/yandexgpt');
const { ydbClient } = require('../../shared/ydb-client');
const { getSecrets } = require('../../shared/secrets');

// Источники знаний о дизайне интерьеров
// Согласованы с DesignStyle.promptModifier и RoomType из SESSION_05
const DESIGN_SOURCES = [
  'https://www.houzz.ru/magazine',
  'https://design-mate.ru',
  'https://www.admagazine.ru/interior',
];

module.exports.handler = async (event, context) => {
  await getSecrets();
  let totalChunks = 0;

  for (const url of DESIGN_SOURCES) {
    try {
      // Actor ID: найди в mega-list agents-apis-697/README.md → "web fetcher" → "markdown"
      const pages = await runActor(
        'misceres/web-fetcher',  // ← проверь актуальный ID в mega-list
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
            // Категория согласована с RoomType из SESSION_05
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

// Категории согласованы с RoomType.rawValue из SESSION_05
function detectCategory(text) {
  const t = text.toLowerCase();
  if (t.includes('гостиная') || t.includes('диван')) return 'living_room';
  if (t.includes('спальня') || t.includes('кровать')) return 'bedroom';
  if (t.includes('кухня')) return 'kitchen';
  if (t.includes('цвет') || t.includes('палитра')) return 'color';
  return 'general';
}
```

---

## Часть 5 — Image Generation

### `AIVibe/Features/ARDesigner/ImageGenClient.swift` (НОВЫЙ)

Создаётся рядом с `RealityDesignerView.swift` и `RoomScanManager.swift` из SESSION_03.

```swift
// AIVibe/Features/ARDesigner/ImageGenClient.swift
// Дополняет SESSION_03 — не конфликтует с RoomScanManager и RealityDesignerView

import ComposableArchitecture
import Foundation

struct GeneratedImage: Codable, Equatable, Identifiable {
    let id: UUID
    let url: URL
    let prompt: String
    // Тип комнаты из SESSION_05 — переиспользуем, не дублируем
    let roomType: RoomType
    let style: DesignStyle
}

struct ImageGenClient {
    var generate: @Sendable (
        _ style: DesignStyle,   // из SESSION_05
        _ roomType: RoomType,   // из SESSION_05
        _ colorPalette: [ColorSuggestion]? // из SESSION_05 DesignAdvice
    ) async throws -> [GeneratedImage]
}

extension ImageGenClient: DependencyKey {
    static let liveValue = ImageGenClient(
        generate: { style, roomType, palette in
            guard let url = URL(string: "https://functions.yandexcloud.net/YOUR_IMAGEGEN_FUNCTION_ID") else {
                throw URLError(.badURL)
            }

            let body: [String: Any] = [
                "style": style.rawValue,
                "roomType": roomType.rawValue,
                // Передаём hex цвета из DesignAdvice.colorPalette (SESSION_05)
                "colorPalette": palette?.map { $0.hex }.joined(separator: ", ") ?? "",
                "userId": "current_user_id",
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 150

            let (data, _) = try await URLSession.shared.data(for: request)

            struct Response: Codable {
                struct Item: Codable { let url: String; let prompt: String }
                let images: [Item]
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.images.compactMap { item in
                guard let imageURL = URL(string: item.url) else { return nil }
                return GeneratedImage(id: UUID(), url: imageURL, prompt: item.prompt,
                                     roomType: roomType, style: style)
            }
        }
    )

    static let testValue = ImageGenClient(
        generate: { style, roomType, _ in
            [GeneratedImage(id: UUID(), url: URL(string: "https://placeholder.com")!,
                           prompt: "test prompt", roomType: roomType, style: style)]
        }
    )
}

extension DependencyValues {
    var imageGenClient: ImageGenClient {
        get { self[ImageGenClient.self] }
        set { self[ImageGenClient.self] = newValue }
    }
}
```

### `backend/functions/image-gen/index.js` (НОВЫЙ)

```javascript
// backend/functions/image-gen/index.js

const { runActor } = require('../../shared/apify-client');
const { getSecrets } = require('../../shared/secrets');

module.exports.handler = async (event, context) => {
  await getSecrets();
  const { style, roomType, colorPalette, userId } = JSON.parse(event.body ?? '{}');

  if (!style || !userId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'style and userId required' }) };
  }

  // Промпт согласован с DesignStyle.promptModifier из SESSION_05
  const STYLE_EN = {
    modern: 'modern contemporary interior, clean lines, neutral tones',
    minimalist: 'minimalist interior, white walls, functional, negative space',
    loft: 'loft style, exposed brick, metal elements, industrial',
    scandinavian: 'scandinavian interior, light wood, white, cozy, plants',
    classic_russian: 'classic interior, ornate details, rich fabrics, symmetry',
    eclectic: 'eclectic interior, mixed styles, bold accents',
    vintage: 'vintage interior, warm tones, antique furniture',
    professional: 'professional home office, dark accents, formal',
  };

  const ROOM_EN = {
    living_room: 'living room',
    bedroom: 'bedroom',
    kitchen: 'kitchen',
    bathroom: 'bathroom',
    office: 'home office',
    dining_room: 'dining room',
    hallway: 'hallway',
    child_room: "children's room",
  };

  const styleDesc = STYLE_EN[style] ?? style;
  const roomDesc = ROOM_EN[roomType] ?? roomType;
  const palette = colorPalette ? `, color palette: ${colorPalette}` : '';

  const prompt = `${styleDesc}, ${roomDesc}${palette}, photorealistic interior photography, 8K, natural lighting, architectural digest quality`;

  // Actor ID: найди в mega-list agents-apis-697/README.md → "image generat"
  const results = await runActor(
    'apify/image-generation-agent', // ← проверь ID в mega-list
    {
      prompt,
      negativePrompt: 'lowres, blurry, ugly, deformed, cartoon',
      width: 1024,
      height: 768,
      numberOfImages: 2,
    },
    { timeoutSecs: 90, memoryMbytes: 1024 }
  );

  const images = results.filter(r => r.imageUrl).map(r => ({ url: r.imageUrl, prompt }));

  return { statusCode: 200, body: JSON.stringify({ images }) };
};
```

---

## Часть 6 — Деплой

```bash
# 1. Marketplace Function
yc serverless function create --name marketplaceFunction
zip -r marketplace.zip backend/functions/marketplace/ backend/shared/
yc serverless function version create \
  --function-name marketplaceFunction \
  --runtime nodejs20 \
  --entrypoint index.handler \
  --source-path marketplace.zip \
  --environment LOCKBOX_SECRET_ID=<id> \
  --memory 512m \
  --execution-timeout 120s

# 2. RAG Indexer + расписание
yc serverless function create --name ragIndexer
zip -r rag.zip backend/functions/rag-indexer/ backend/shared/
yc serverless function version create \
  --function-name ragIndexer --runtime nodejs20 \
  --entrypoint index.handler --source-path rag.zip \
  --environment LOCKBOX_SECRET_ID=<id> \
  --memory 1024m --execution-timeout 300s

# Расписание: каждый день в 03:00 МСК (00:00 UTC)
yc serverless trigger create timer \
  --name rag-daily \
  --cron-expression "0 0 * * ? *" \
  --invoke-function-name ragIndexer

# 3. Image Generation Function
yc serverless function create --name imageGenFunction
zip -r imagegen.zip backend/functions/image-gen/ backend/shared/
yc serverless function version create \
  --function-name imageGenFunction --runtime nodejs20 \
  --entrypoint index.handler --source-path imagegen.zip \
  --environment LOCKBOX_SECRET_ID=<id> \
  --memory 512m --execution-timeout 150s

# 4. Обновить существующую ai-advisor Function (патч из SESSION_04)
zip -r aiadvisor.zip backend/functions/ai-advisor/ backend/shared/
yc serverless function version create \
  --function-name aiAdvisor \
  --runtime nodejs20 --entrypoint index.handler \
  --source-path aiadvisor.zip \
  --environment LOCKBOX_SECRET_ID=<id> \
  --memory 512m --execution-timeout 120s
```

---

## Чеклист внедрения

- [ ] Зарегистрироваться на apify.com
- [ ] Добавить `APIFY_API_TOKEN` в Lockbox (к существующим из SESSION_04)
- [ ] Создать `backend/shared/apify-client.js`
- [ ] Создать `backend/shared/rag-search.js`
- [ ] Патч `backend/functions/ai-advisor/index.js` (+3 строки)
- [ ] Создать `backend/functions/marketplace/index.js` → задеплоить
- [ ] Создать `backend/functions/rag-indexer/index.js` → задеплоить + расписание
- [ ] Создать `backend/functions/image-gen/index.js` → задеплоить
- [ ] Создать `AIVibe/Features/Marketplace/MarketplaceFeature.swift`
- [ ] Создать `AIVibe/Features/ARDesigner/ImageGenClient.swift`
- [ ] Найти актуальные Actor ID в mega-list (ищи по ключевым словам из Части 7)
- [ ] Заменить `YOUR_XXX_FUNCTION_ID` на реальные ID из Yandex Cloud
- [ ] Тесты с `.testValue` клиентами

---

## Часть 7 — Как найти Actor ID в mega-list

1. Открыть `agents-apis-697/` в репо mega-list
2. `Ctrl+F` по ключевым словам:

| Нужен | Ключевые слова для поиска |
|---|---|
| Product Recommendation | `product recommendation`, `product search` |
| Web Fetcher → Markdown | `web fetcher`, `markdown`, `LLM-friendly` |
| Image Generation | `image generat`, `image creat` |
| Newsletter | `newsletter`, `digest` |
| WB/Ozon scraper | `wildberries`, `ozon`, `ecommerce-apis-2440` |

3. Формат Actor ID: `username/actor-name` из URL вида `apify.com/store/username/actor-name`

---

## Связи с предыдущими сессиями (без конфликтов)

| Сессия | Связь | Характер |
|---|---|---|
| SESSION_02 | `AIProviderRouter` вызывается через `AIAdvisorClient` | Без изменений |
| SESSION_03 | `ImageGenClient` рядом с `RealityDesignerView` | Additive |
| SESSION_04 | `ai-advisor/index.js` патч +3 строки; `secrets.js` +1 ключ | Патч |
| SESSION_05 | `DesignStyle`, `RoomType`, `DesignAdvice`, `FurniturePiece` — переиспользуем | Import only |

*SESSION_07 готова. Следующая: SESSION_08 — Portfolio Feature (Newsletter + Social Sharing)*
