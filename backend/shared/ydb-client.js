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

export { toDynamo, fromDynamo };
