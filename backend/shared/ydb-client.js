// backend/shared/ydb-client.js
// Клиент Yandex Database Document API (DynamoDB-совместимый) через fetch().
//
// Document API YDB совместим с Amazon DynamoDB HTTP API: запросы идут обычным
// POST с заголовком X-Amz-Target. Поэтому npm-SDK не нужен — только fetch().
//
// Конфигурация:
//   YDB_DOCUMENT_API_ENDPOINT — например:
//     https://docapi.serverless.yandexcloud.net/ru-central1/b1g.../etn...
//   IAM-токен — через getIamToken() из ./yandexgpt.js (metadata service).
//
// Graceful degradation: если YDB_DOCUMENT_API_ENDPOINT не задан, методы логируют
// предупреждение и возвращают пустые данные (не бросают ошибку). Это позволяет
// запускать backend локально без YDB.

import { getIamToken } from './yandexgpt.js';

const DYNAMO_TARGET_PREFIX = 'DynamoDB_20120810';
const REQUEST_TIMEOUT_MS = 15000;

// ─── Сериализация типов DynamoDB ─────────────────────────────────

/**
 * JS-объект → DynamoDB Item.
 * string→{S}, number→{N:"123"}, boolean→{BOOL}, null/undefined→{NULL:true},
 * object/array→JSON.stringify→{S}.
 * @param {object} obj
 * @returns {object}
 */
function toDynamo(obj) {
    const item = {};
    for (const [key, value] of Object.entries(obj ?? {})) {
        if (value === null || value === undefined) {
            item[key] = { NULL: true };
        } else if (typeof value === 'string') {
            item[key] = { S: value };
        } else if (typeof value === 'number') {
            item[key] = { N: String(value) };
        } else if (typeof value === 'boolean') {
            item[key] = { BOOL: value };
        } else {
            // object / array — сериализуем в JSON-строку
            item[key] = { S: JSON.stringify(value) };
        }
    }
    return item;
}

/**
 * DynamoDB Item → JS-объект.
 * Контракт round-trip: примитивы восстанавливаются (string/number/boolean/null);
 * сложные поля, записанные через toDynamo как JSON-строка, возвращаются СТРОКОЙ —
 * их парсит сам вызывающий код (например rag-search.js делает JSON.parse(embedding)).
 * Здесь строки НЕ авто-парсятся: иначе обычная строка вида "[...]" превратилась бы
 * в массив, а повторный JSON.parse у потребителя упал бы.
 * @param {object} dynamoItem
 * @returns {object}
 */
function fromDynamo(dynamoItem) {
    const obj = {};
    for (const [key, attr] of Object.entries(dynamoItem ?? {})) {
        if (attr == null || typeof attr !== 'object') continue;
        if ('NULL' in attr) {
            obj[key] = null;
        } else if ('S' in attr) {
            obj[key] = attr.S;
        } else if ('N' in attr) {
            obj[key] = Number(attr.N);
        } else if ('BOOL' in attr) {
            obj[key] = Boolean(attr.BOOL);
        } else {
            // Неизвестный тип — отдаём как есть
            obj[key] = attr;
        }
    }
    return obj;
}

/**
 * JS-значения → ExpressionAttributeValues с плейсхолдерами ":имя".
 * Только примитивы: в FilterExpression/KeyConditionExpression сложным типам
 * делать нечего, а молчаливый JSON.stringify дал бы фильтр, который никогда
 * не совпадёт.
 * @param {object} values — например { cat: 'kitchen', wmin: 170 }
 * @returns {object} — { ':cat': {S:'kitchen'}, ':wmin': {N:'170'} }
 */
function toExpressionValues(values) {
    const out = {};
    for (const [key, value] of Object.entries(values ?? {})) {
        const placeholder = key.startsWith(':') ? key : `:${key}`;
        if (typeof value === 'string') {
            out[placeholder] = { S: value };
        } else if (typeof value === 'number') {
            out[placeholder] = { N: String(value) };
        } else if (typeof value === 'boolean') {
            out[placeholder] = { BOOL: value };
        } else {
            throw new Error(`toExpressionValues: неподдерживаемый тип для "${key}" (${typeof value})`);
        }
    }
    return out;
}

// ─── Базовый HTTP-запрос к Document API ──────────────────────────

/**
 * Выполняет один запрос к Document API.
 * Если endpoint не задан — логирует предупреждение и возвращает null.
 * Если HTTP-ошибка — бросает Error с деталями.
 * @param {string} operation — например 'PutItem', 'GetItem', 'Scan'
 * @param {object} body — тело по схеме DynamoDB
 * @returns {Promise<object|null>}
 */
async function dynamoRequest(operation, body) {
    const endpoint = process.env.YDB_DOCUMENT_API_ENDPOINT;
    if (!endpoint) {
        console.warn(`[ydb] YDB_DOCUMENT_API_ENDPOINT not set — skipping ${operation}`);
        return null;
    }

    const iamToken = await getIamToken();

    const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-amz-json-1.0',
            'X-Amz-Target': `${DYNAMO_TARGET_PREFIX}.${operation}`,
            Authorization: `Bearer ${iamToken}`,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });

    if (!res.ok) {
        const errText = await res.text();
        throw new Error(`YDB ${operation} HTTP ${res.status}: ${errText}`);
    }

    return res.json();
}

// ─── Публичный API ───────────────────────────────────────────────

export const ydbClient = {
    /**
     * Вставить или обновить запись (PutItem перезаписывает по ключу).
     * @param {string} tableName
     * @param {object} item — должен содержать поле первичного ключа
     */
    async upsert(tableName, item) {
        const res = await dynamoRequest('PutItem', {
            TableName: tableName,
            Item: toDynamo(item),
        });
        // null = YDB не настроен; сохраняем non-breaking-контракт { ok: true }.
        return { ok: true, skipped: res === null };
    },

    /**
     * Получить запись по первичному ключу.
     * @returns {Promise<object|null>} объект или null, если не найден / YDB off
     */
    async get(tableName, keyName, keyValue) {
        const res = await dynamoRequest('GetItem', {
            TableName: tableName,
            Key: { [keyName]: { S: String(keyValue) } },
        });
        if (!res || !res.Item) return null;
        return fromDynamo(res.Item);
    },

    /**
     * Просканировать таблицу (до opts.limit записей, по умолчанию 500).
     * @returns {Promise<object[]>}
     */
    async scan(tableName, opts = {}) {
        const res = await dynamoRequest('Scan', {
            TableName: tableName,
            Limit: opts.limit ?? 500,
        });
        if (!res) return [];
        return (res.Items ?? []).map(fromDynamo);
    },

    /**
     * Постраничное сканирование с фильтрацией на стороне YDB (B5/B6).
     *
     * Особенность Document API: FilterExpression применяется ПОСЛЕ чтения
     * порции (до 1MB или pageLimit записей), поэтому метод сам идёт по
     * страницам через LastEvaluatedKey, пока не наберёт targetCount
     * подходящих записей, не упрётся в maxPages или в конец таблицы.
     *
     * Все имена атрибутов в выражениях передавайте через names (#алиасы):
     * у DynamoDB-синтаксиса длинный список зарезервированных слов (name,
     * size, ...), алиасы снимают проблему целиком.
     *
     * @param {string} tableName
     * @param {object} opts
     * @param {string} [opts.filterExpression] — например '#category = :cat OR #category = :gen'
     * @param {object} [opts.values] — JS-значения плейсхолдеров: { cat: 'kitchen', gen: 'general' }
     * @param {object} [opts.names] — алиасы атрибутов: { '#category': 'category' }
     * @param {string} [opts.projection] — ProjectionExpression: '#id, #content'
     * @param {number} [opts.pageLimit=100] — записей СКАНИРУЕТСЯ за страницу (фильтр — после)
     * @param {number} [opts.maxPages=8] — потолок страниц (ограничивает худший случай)
     * @param {number} [opts.targetCount=50] — досрочный выход, когда кандидатов достаточно
     * @returns {Promise<object[]>}
     */
    async scanFiltered(tableName, opts = {}) {
        const {
            filterExpression,
            values,
            names,
            projection,
            pageLimit = 100,
            maxPages = 8,
            targetCount = 50,
        } = opts;

        const collected = [];
        let exclusiveStartKey;

        for (let page = 0; page < maxPages; page++) {
            const body = { TableName: tableName, Limit: pageLimit };
            if (filterExpression) {
                body.FilterExpression = filterExpression;
                body.ExpressionAttributeValues = toExpressionValues(values);
            }
            if (names) body.ExpressionAttributeNames = names;
            if (projection) body.ProjectionExpression = projection;
            if (exclusiveStartKey) body.ExclusiveStartKey = exclusiveStartKey;

            const res = await dynamoRequest('Scan', body);
            if (!res) return collected; // YDB не настроен — graceful, отдаём что есть

            collected.push(...(res.Items ?? []).map(fromDynamo));
            exclusiveStartKey = res.LastEvaluatedKey;
            if (!exclusiveStartKey || collected.length >= targetCount) break;
        }
        return collected;
    },

    /**
     * Query по ключу или глобальному вторичному индексу (B5).
     * В отличие от Scan читает только записи, попавшие под условие ключа, —
     * для таблиц, где партиционный ключ совпадает с осью поиска (например,
     * products по индексу category).
     *
     * @param {string} tableName
     * @param {object} opts
     * @param {string} opts.keyConditionExpression — например '#category = :cat'
     * @param {object} opts.values — JS-значения плейсхолдеров
     * @param {object} [opts.names] — алиасы атрибутов
     * @param {string} [opts.filterExpression] — доп. фильтр по неключевым атрибутам
     * @param {string} [opts.projection]
     * @param {string} [opts.indexName] — имя глобального вторичного индекса
     * @param {number} [opts.limit=100]
     * @returns {Promise<object[]>}
     */
    async query(tableName, opts = {}) {
        const {
            keyConditionExpression,
            values,
            names,
            filterExpression,
            projection,
            indexName,
            limit = 100,
        } = opts;
        if (!keyConditionExpression) {
            throw new Error('ydbClient.query: keyConditionExpression обязателен');
        }

        const body = {
            TableName: tableName,
            KeyConditionExpression: keyConditionExpression,
            ExpressionAttributeValues: toExpressionValues(values),
            Limit: limit,
        };
        if (filterExpression) body.FilterExpression = filterExpression;
        if (names) body.ExpressionAttributeNames = names;
        if (projection) body.ProjectionExpression = projection;
        if (indexName) body.IndexName = indexName;

        const res = await dynamoRequest('Query', body);
        if (!res) return [];
        return (res.Items ?? []).map(fromDynamo);
    },

    /**
     * Удалить запись по первичному ключу.
     */
    async deleteItem(tableName, keyName, keyValue) {
        const res = await dynamoRequest('DeleteItem', {
            TableName: tableName,
            Key: { [keyName]: { S: String(keyValue) } },
        });
        return { ok: true, skipped: res === null };
    },
};

/**
 * Health-check: Scan таблицы 'sessions' с Limit: 1.
 * @returns {Promise<{ok: boolean, error?: string}>}
 */
export async function ydbHealthCheck() {
    try {
        const res = await dynamoRequest('Scan', { TableName: 'sessions', Limit: 1 });
        if (res === null) return { ok: false, error: 'YDB_DOCUMENT_API_ENDPOINT not set' };
        return { ok: true };
    } catch (e) {
        return { ok: false, error: (e && e.message) || 'unknown' };
    }
}

export { toDynamo, fromDynamo, toExpressionValues };
