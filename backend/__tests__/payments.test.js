// backend/__tests__/payments.test.js
// Тесты функции payments (ЮKassa): create / status / вебхук с перепроверкой по API.
// node --test, без внешних зависимостей; fetch мокается, YDB — graceful (endpoint не задан).

import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { handler, isSubscriptionActive, PLANS } from '../functions/payments/index.js';

const TOKEN = 'test-app-token';
const realFetch = globalThis.fetch;

beforeEach(() => {
    process.env.APP_TOKEN = TOKEN;
    process.env.YOOKASSA_SHOP_ID = 'shop-1';
    process.env.YOOKASSA_SECRET_KEY = 'sk-test';
    delete process.env.YDB_DOCUMENT_API_ENDPOINT; // YDB в graceful no-op режиме
});

afterEach(() => {
    globalThis.fetch = realFetch;
});

function appEvent(body, { token = TOKEN } = {}) {
    return {
        httpMethod: 'POST',
        headers: { 'x-app-token': token },
        body: JSON.stringify(body),
    };
}

function webhookEvent(body) {
    // Вебхук ЮKassa приходит БЕЗ X-App-Token.
    return { httpMethod: 'POST', headers: {}, body: JSON.stringify(body) };
}

function parse(res) {
    return { status: res.statusCode, body: JSON.parse(res.body) };
}

// ─── Общие проверки ──────────────────────────────────────────────

test('OPTIONS → 200 (CORS preflight)', async () => {
    const res = await handler({ httpMethod: 'OPTIONS', headers: {} });
    assert.equal(res.statusCode, 200);
});

test('action без токена → 403', async () => {
    const res = await handler(appEvent({ action: 'status', userId: 'u1' }, { token: 'wrong' }));
    assert.equal(res.statusCode, 403);
});

test('невалидный JSON → 400', async () => {
    const res = await handler({ httpMethod: 'POST', headers: { 'x-app-token': TOKEN }, body: '{oops' });
    assert.equal(res.statusCode, 400);
});

test('неизвестный action → 400', async () => {
    const { status } = parse(await handler(appEvent({ action: 'refund', userId: 'u1' })));
    assert.equal(status, 400);
});

// ─── create ──────────────────────────────────────────────────────

test('create: happy path возвращает confirmationUrl', async () => {
    let captured;
    globalThis.fetch = async (url, opts) => {
        captured = { url: String(url), opts };
        return new Response(JSON.stringify({
            id: 'pay-123',
            status: 'pending',
            confirmation: { type: 'redirect', confirmation_url: 'https://yookassa.ru/checkout/pay-123' },
        }), { status: 200 });
    };

    const { status, body } = parse(await handler(appEvent({ action: 'create', userId: 'user-1', plan: 'pro' })));
    assert.equal(status, 200);
    assert.equal(body.paymentId, 'pay-123');
    assert.equal(body.confirmationUrl, 'https://yookassa.ru/checkout/pay-123');
    assert.equal(body.amountRub, 599);

    // Запрос ушёл в ЮKassa с Basic auth, Idempotence-Key и канонической суммой.
    assert.ok(captured.url.includes('api.yookassa.ru/v3/payments'));
    assert.ok(captured.opts.headers.Authorization.startsWith('Basic '));
    assert.ok(captured.opts.headers['Idempotence-Key'].startsWith('sub-user-1-pro-'));
    const sent = JSON.parse(captured.opts.body);
    assert.equal(sent.amount.value, '599.00');
    assert.equal(sent.amount.currency, 'RUB');
    assert.deepEqual(sent.metadata, { userId: 'user-1', plan: 'pro' });
});

test('create: невалидный plan → 400', async () => {
    const { status } = parse(await handler(appEvent({ action: 'create', userId: 'u1', plan: 'gold' })));
    assert.equal(status, 400);
});

test('create: невалидный userId → 400', async () => {
    const { status } = parse(await handler(appEvent({ action: 'create', userId: 'плохой id!', plan: 'pro' })));
    assert.equal(status, 400);
});

test('create: ЮKassa не сконфигурирована → 503', async () => {
    delete process.env.YOOKASSA_SHOP_ID;
    const { status } = parse(await handler(appEvent({ action: 'create', userId: 'u1', plan: 'pro' })));
    assert.equal(status, 503);
});

test('PLANS соответствуют канону цен (STRATEGY §1.3)', () => {
    assert.equal(PLANS.pro.amountRub, 599);
    assert.equal(PLANS.business.amountRub, 2490);
});

// ─── status ──────────────────────────────────────────────────────

test('status: без записи в YDB → free/inactive', async () => {
    const { status, body } = parse(await handler(appEvent({ action: 'status', userId: 'nouser' })));
    assert.equal(status, 200);
    assert.equal(body.plan, 'free');
    assert.equal(body.isActive, false);
});

// ─── isSubscriptionActive (чистая логика) ────────────────────────

test('isSubscriptionActive: активная не истёкшая → true', () => {
    const sub = { status: 'active', expiresAt: new Date(Date.now() + 86400_000).toISOString() };
    assert.equal(isSubscriptionActive(sub), true);
});

test('isSubscriptionActive: истёкшая → false', () => {
    const sub = { status: 'active', expiresAt: new Date(Date.now() - 1000).toISOString() };
    assert.equal(isSubscriptionActive(sub), false);
});

test('isSubscriptionActive: null/не active/битая дата → false', () => {
    assert.equal(isSubscriptionActive(null), false);
    assert.equal(isSubscriptionActive({ status: 'canceled', expiresAt: '2999-01-01' }), false);
    assert.equal(isSubscriptionActive({ status: 'active', expiresAt: 'not-a-date' }), false);
});

// ─── Вебхук ──────────────────────────────────────────────────────

test('вебхук payment.succeeded: перепроверяет по API и активирует подписку', async () => {
    const apiCalls = [];
    globalThis.fetch = async (url) => {
        apiCalls.push(String(url));
        // getPayment → подтверждённый платёж с метаданными
        return new Response(JSON.stringify({
            id: 'pay-777',
            status: 'succeeded',
            metadata: { userId: 'user-7', plan: 'pro' },
        }), { status: 200 });
    };

    const { status, body } = parse(await handler(webhookEvent({
        type: 'notification',
        event: 'payment.succeeded',
        object: { id: 'pay-777', status: 'succeeded' },
    })));

    assert.equal(status, 200);
    assert.equal(body.processed, true);
    // Главная проверка безопасности: был запрос к API ЮKassa за реальным статусом.
    assert.ok(apiCalls.some((u) => u.includes('/v3/payments/pay-777')));
});

test('вебхук: API говорит pending → платёж игнорируется (защита от подделки тела)', async () => {
    globalThis.fetch = async () => new Response(JSON.stringify({
        id: 'pay-888',
        status: 'pending', // в теле вебхука «succeeded», но API говорит иначе
        metadata: { userId: 'user-8', plan: 'pro' },
    }), { status: 200 });

    const { status, body } = parse(await handler(webhookEvent({
        type: 'notification',
        event: 'payment.succeeded',
        object: { id: 'pay-888', status: 'succeeded' },
    })));

    assert.equal(status, 200);
    assert.equal(body.ignored, true);
    assert.notEqual(body.processed, true);
});

test('вебхук: неизвестный платёж (404 от API) → ignored, не 500', async () => {
    globalThis.fetch = async () => new Response(JSON.stringify({
        code: 'not_found', description: 'Payment not found',
    }), { status: 404 });

    const { status, body } = parse(await handler(webhookEvent({
        type: 'notification',
        event: 'payment.succeeded',
        object: { id: 'pay-fake' },
    })));

    assert.equal(status, 200);
    assert.equal(body.ignored, true);
});

test('вебхук: события кроме payment.succeeded подтверждаются без обработки', async () => {
    let apiCalled = false;
    globalThis.fetch = async () => { apiCalled = true; return new Response('{}', { status: 200 }); };

    const { status, body } = parse(await handler(webhookEvent({
        type: 'notification',
        event: 'payment.canceled',
        object: { id: 'pay-9' },
    })));

    assert.equal(status, 200);
    assert.equal(body.ignored, true);
    assert.equal(apiCalled, false); // даже не ходили в API
});

test('вебхук: битые метаданные (нет userId/plan) → ignored', async () => {
    globalThis.fetch = async () => new Response(JSON.stringify({
        id: 'pay-10', status: 'succeeded', metadata: {},
    }), { status: 200 });

    const { status, body } = parse(await handler(webhookEvent({
        type: 'notification',
        event: 'payment.succeeded',
        object: { id: 'pay-10' },
    })));

    assert.equal(status, 200);
    assert.equal(body.ignored, true);
});

test('вебхук без object.id → 400', async () => {
    const { status } = parse(await handler(webhookEvent({ type: 'notification', event: 'payment.succeeded' })));
    assert.equal(status, 400);
});
