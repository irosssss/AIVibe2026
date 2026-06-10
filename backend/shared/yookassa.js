// backend/shared/yookassa.js
// Клиент ЮKassa API v3 через fetch() — без npm-зависимостей (правило no-deps).
// Поток дохода №1: подписка PRO/BUSINESS, оплата на сайте (Apple IAP в РФ недоступен).
// См. docs/UPGRADE_PLAN.md — Фаза 1, A3.1; docs/BUSINESS_MODEL.md §3.
//
// Конфигурация (Lockbox / process.env):
//   YOOKASSA_SHOP_ID    — идентификатор магазина
//   YOOKASSA_SECRET_KEY — секретный ключ (Basic auth)
//
// ВАЖНО (безопасность): ЮKassa НЕ подписывает тела вебхуков. Любое входящее
// уведомление обязано перепроверяться повторным запросом getPayment(id) —
// доверяем только ответу API, полученному с нашими учётными данными.

const YOOKASSA_API = 'https://api.yookassa.ru/v3';
const REQUEST_TIMEOUT_MS = 15000;

/** Ошибка конфигурации/вызова ЮKassa. */
export class YooKassaError extends Error {
    constructor(message, { statusCode = 0, code = 'yookassa_error' } = {}) {
        super(message);
        this.name = 'YooKassaError';
        this.statusCode = statusCode;
        this.code = code;
    }
}

/** Читает учётные данные на момент вызова (тестируемость + Lockbox-инжект). */
function credentials() {
    const shopId = process.env.YOOKASSA_SHOP_ID;
    const secretKey = process.env.YOOKASSA_SECRET_KEY;
    if (!shopId || !secretKey) {
        throw new YooKassaError('YOOKASSA_SHOP_ID / YOOKASSA_SECRET_KEY не заданы', {
            code: 'not_configured',
        });
    }
    return { shopId, secretKey };
}

function authHeader() {
    const { shopId, secretKey } = credentials();
    return `Basic ${Buffer.from(`${shopId}:${secretKey}`).toString('base64')}`;
}

async function yookassaRequest(method, path, { body, idempotenceKey } = {}) {
    const headers = {
        Authorization: authHeader(),
        'Content-Type': 'application/json',
    };
    if (idempotenceKey) headers['Idempotence-Key'] = idempotenceKey;

    const res = await fetch(`${YOOKASSA_API}${path}`, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });

    const text = await res.text();
    let data;
    try {
        data = text ? JSON.parse(text) : {};
    } catch {
        data = { raw: text };
    }

    if (!res.ok) {
        throw new YooKassaError(
            `ЮKassa ${method} ${path} HTTP ${res.status}: ${data.description || text}`,
            { statusCode: res.status, code: data.code || 'http_error' },
        );
    }
    return data;
}

/**
 * Создаёт платёж подписки.
 * @param {object} p
 * @param {number} p.amountRub   — сумма в рублях (599 → "599.00")
 * @param {string} p.description — назначение платежа (видно пользователю)
 * @param {string} p.returnUrl   — куда вернуть пользователя после оплаты
 * @param {string} p.idempotenceKey — уникальный ключ запроса (повтор = тот же платёж)
 * @param {object} p.metadata    — { userId, plan } — вернётся в вебхуке/при getPayment
 * @returns {Promise<object>} объект платежа ЮKassa (id, status, confirmation.confirmation_url)
 */
export async function createPayment({ amountRub, description, returnUrl, idempotenceKey, metadata }) {
    return yookassaRequest('POST', '/payments', {
        idempotenceKey,
        body: {
            amount: { value: amountRub.toFixed(2), currency: 'RUB' },
            capture: true,
            confirmation: { type: 'redirect', return_url: returnUrl },
            description,
            metadata,
        },
    });
}

/**
 * Возвращает платёж по ID — ЕДИНСТВЕННЫЙ доверенный источник статуса
 * (верификация вебхуков: тело уведомления не подписано, перепроверяем по API).
 * @param {string} paymentId
 * @returns {Promise<object>}
 */
export async function getPayment(paymentId) {
    return yookassaRequest('GET', `/payments/${encodeURIComponent(paymentId)}`);
}

/** Настроен ли клиент (для health-check / graceful-ответов). */
export function isConfigured() {
    return Boolean(process.env.YOOKASSA_SHOP_ID && process.env.YOOKASSA_SECRET_KEY);
}
