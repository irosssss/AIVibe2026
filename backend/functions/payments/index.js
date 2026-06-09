// backend/functions/payments/index.js
// Yandex Cloud Function — подписка PRO/BUSINESS через ЮKassa (поток дохода №1).
// См. docs/UPGRADE_PLAN.md — Фаза 1, A3.1; docs/BUSINESS_MODEL.md §3 (599₽/2490₽).
//
// Маршруты (по полю action в JSON-теле):
//   { action: "create", userId, plan }  → создать платёж, вернуть confirmationUrl
//   { action: "status", userId }        → текущая подписка пользователя
//   { type: "notification", ... }       → вебхук ЮKassa (БЕЗ X-App-Token — см. ниже)
//
// Security pipeline (как в marketplace/index.js):
//   1. X-App-Token для create/status (вебхук — отдельная модель доверия)
//   2. Валидация входа (userId regex, plan whitelist)
//   3. Rate limit per-IP
//   4. Вебхук: телу НЕ доверяем — статус перепроверяется запросом getPayment(id)
//      к API ЮKassa (тело вебхука не подписано); идемпотентность по paymentId.
//
// Auto-renewal (сохранённые методы оплаты) — вне MVP; подписка продлевается
// повторной оплатой. TTL подписки — 30 дней с момента успешного платежа.

import { createPayment, getPayment, isConfigured, YooKassaError } from '../../shared/yookassa.js';
import { ydbClient } from '../../shared/ydb-client.js';
import { createRateLimiter, clientIp } from '../../shared/rate-limit.js';

const APP_TOKEN_HEADER = 'x-app-token';
const MAX_USER_ID_LENGTH = 64;
const USER_ID_REGEX = /^[a-zA-Z0-9_.-]+$/;
const SUBSCRIPTION_DAYS = 30;

const SUBSCRIPTIONS_TABLE = 'subscriptions';
const PROCESSED_TABLE = 'payments_processed';

// Канон цен — STRATEGY.md §1.3 / BUSINESS_MODEL.md §4.
const PLANS = {
    pro: { amountRub: 599, title: 'AIVibe PRO — 1 месяц' },
    business: { amountRub: 2490, title: 'AIVibe BUSINESS — 1 месяц' },
};

const RETURN_URL = process.env.PAYMENTS_RETURN_URL || 'https://aivibe.ru/payment/done';

// Лимит щедрее AI-эндпоинтов: вебхуки ЮKassa ретраятся пачками.
const ipLimiter = createRateLimiter({ max: 120 });

function buildResponse(statusCode, body) {
    return {
        statusCode,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-App-Token',
        },
        body: JSON.stringify(body),
    };
}

function log(level, msg, extra = {}) {
    const line = JSON.stringify({ _l: level, _t: new Date().toISOString(), msg, ...extra });
    if (level === 'error') console.error(line);
    else if (level === 'warn') console.warn(line);
    else console.log(line);
}

function validUserId(userId) {
    return typeof userId === 'string'
        && userId.length > 0
        && userId.length <= MAX_USER_ID_LENGTH
        && USER_ID_REGEX.test(userId);
}

/** Активна ли подписка на момент now. */
export function isSubscriptionActive(sub, now = Date.now()) {
    if (!sub || sub.status !== 'active' || !sub.expiresAt) return false;
    const expires = Date.parse(sub.expiresAt);
    return Number.isFinite(expires) && expires > now;
}

// ─── action: create ──────────────────────────────────────────────

async function handleCreate(body) {
    const { userId, plan } = body;
    if (!validUserId(userId)) {
        return buildResponse(400, { error: 'Invalid userId format' });
    }
    const planDef = PLANS[plan];
    if (!planDef) {
        return buildResponse(400, { error: `Invalid plan. Allowed: ${Object.keys(PLANS).join(', ')}` });
    }
    if (!isConfigured()) {
        log('error', 'yookassa_not_configured');
        return buildResponse(503, { error: 'Payments are not configured' });
    }

    // Идемпотентность на стороне ЮKassa: одинаковый ключ → тот же платёж.
    // Ключ меняется раз в минуту: повторный тап «Оплатить» не плодит платежи,
    // а через минуту пользователь может попробовать снова.
    const minuteBucket = Math.floor(Date.now() / 60_000);
    const idempotenceKey = `sub-${userId}-${plan}-${minuteBucket}`;

    const payment = await createPayment({
        amountRub: planDef.amountRub,
        description: planDef.title,
        returnUrl: RETURN_URL,
        idempotenceKey,
        metadata: { userId, plan },
    });

    log('info', 'payment_created', {
        paymentId: payment.id,
        plan,
        userId: userId.slice(0, 16),
    });

    return buildResponse(200, {
        paymentId: payment.id,
        status: payment.status,
        confirmationUrl: payment.confirmation?.confirmation_url ?? null,
        amountRub: planDef.amountRub,
    });
}

// ─── action: status ──────────────────────────────────────────────

async function handleStatus(body) {
    const { userId } = body;
    if (!validUserId(userId)) {
        return buildResponse(400, { error: 'Invalid userId format' });
    }

    const sub = await ydbClient.get(SUBSCRIPTIONS_TABLE, 'userId', userId);
    const active = isSubscriptionActive(sub);

    return buildResponse(200, {
        plan: active ? sub.plan : 'free',
        isActive: active,
        expiresAt: active ? sub.expiresAt : null,
    });
}

// ─── Вебхук ЮKassa ───────────────────────────────────────────────

async function handleWebhook(body) {
    const event = body.event;
    const paymentId = body.object?.id;

    if (!paymentId || typeof paymentId !== 'string') {
        return buildResponse(400, { error: 'Missing payment id' });
    }

    // Интересует только успешная оплата; остальные события подтверждаем (200),
    // чтобы ЮKassa не ретраила.
    if (event !== 'payment.succeeded') {
        log('info', 'webhook_ignored', { event, paymentId });
        return buildResponse(200, { ok: true, ignored: true });
    }

    // Идемпотентность: платёж уже обработан → подтверждаем без побочных эффектов.
    const processed = await ydbClient.get(PROCESSED_TABLE, 'paymentId', paymentId);
    if (processed) {
        log('info', 'webhook_duplicate', { paymentId });
        return buildResponse(200, { ok: true, duplicate: true });
    }

    // ДОВЕРЕННАЯ проверка: тело вебхука не подписано — статус берём только
    // из ответа API ЮKassa по нашим учётным данным.
    let payment;
    try {
        payment = await getPayment(paymentId);
    } catch (e) {
        if (e instanceof YooKassaError && e.statusCode === 404) {
            log('warn', 'webhook_unknown_payment', { paymentId });
            return buildResponse(200, { ok: true, ignored: true });
        }
        throw e;
    }

    if (payment.status !== 'succeeded') {
        log('warn', 'webhook_status_mismatch', { paymentId, apiStatus: payment.status });
        return buildResponse(200, { ok: true, ignored: true });
    }

    const userId = payment.metadata?.userId;
    const plan = payment.metadata?.plan;
    if (!validUserId(userId) || !PLANS[plan]) {
        log('error', 'webhook_bad_metadata', { paymentId });
        return buildResponse(200, { ok: true, ignored: true });
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + SUBSCRIPTION_DAYS * 24 * 60 * 60 * 1000);

    await ydbClient.upsert(SUBSCRIPTIONS_TABLE, {
        userId,
        plan,
        status: 'active',
        expiresAt: expiresAt.toISOString(),
        updatedAt: now.toISOString(),
        lastPaymentId: paymentId,
    });
    await ydbClient.upsert(PROCESSED_TABLE, {
        paymentId,
        userId,
        processedAt: now.toISOString(),
    });

    log('info', 'subscription_activated', {
        paymentId,
        plan,
        userId: userId.slice(0, 16),
        expiresAt: expiresAt.toISOString(),
    });

    return buildResponse(200, { ok: true, processed: true });
}

// ─── Handler ─────────────────────────────────────────────────────

export const handler = async (event) => {
    try {
        if (event.httpMethod === 'OPTIONS') {
            return buildResponse(200, {});
        }

        // Rate limit per-IP — на все маршруты, включая вебхук.
        const ipInfo = ipLimiter(clientIp(event));
        if (!ipInfo.allowed) {
            return buildResponse(429, { error: 'Rate limit exceeded (per-IP).', retryAfter: 60 });
        }

        let body;
        try {
            body = JSON.parse(event.body ?? '{}');
        } catch {
            return buildResponse(400, { error: 'Invalid JSON body' });
        }

        // Вебхук ЮKassa: { type: "notification", event: "...", object: {...} }.
        // Приходит ИЗВНЕ без X-App-Token; модель доверия — перепроверка по API.
        if (body.type === 'notification') {
            return await handleWebhook(body);
        }

        // Остальные маршруты — только от приложения (X-App-Token).
        const appToken = event.headers?.[APP_TOKEN_HEADER]
            || event.headers?.['X-App-Token'];
        const expectedToken = process.env.APP_TOKEN;
        if (!expectedToken || appToken !== expectedToken) {
            return buildResponse(403, { error: 'Forbidden: invalid App Token' });
        }

        switch (body.action) {
            case 'create': return await handleCreate(body);
            case 'status': return await handleStatus(body);
            default:
                return buildResponse(400, { error: 'Unknown action. Allowed: create, status' });
        }
    } catch (e) {
        log('error', 'payments_unhandled', { message: e?.message });
        return buildResponse(500, { error: 'Internal error' });
    }
};

export { PLANS, SUBSCRIPTION_DAYS };
