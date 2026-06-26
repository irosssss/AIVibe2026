// backend/functions/web-billing/index.js
// Yandex Cloud Function — авторизация веб-кабинета (Яндекс ID / VK ID)
// и приём оплат подписки через ЮKassa.
//
// ⚠️ СТАБ ПОД КОНФИГУРАЦИЮ. Код рабочий, но «живым» становится только после
// того как владелец зарегистрирует приложения OAuth и магазин ЮKassa и положит
// секреты в окружение (или Yandex Lockbox). Список — см.
// docs/AUTH_PAYMENT_INTEGRATION.md. Без env-секретов эндпоинты честно вернут 503.
//
// Конвенции репозитория: ESM, без npm-зависимостей, только fetch,
// структурные логи { _l, _rid, _t, ... }, секреты только через process.env.

const SUB_PRICE_RUB = { pro_month: 1490, pro_year: 12900 }; // тарифы подписки, ₽
const ALLOWED_PLANS = new Set(Object.keys(SUB_PRICE_RUB));

// ─── утилиты ─────────────────────────────────────────────────────
function log(level, rid, msg, extra) {
  // структурный лог: _l=level, _rid=requestId, _t=ts, _m=message
  console.log(JSON.stringify({ _l: level, _rid: rid, _t: new Date().toISOString(), _m: msg, ...(extra || {}) }));
}
function getHeader(event, name) {
  const h = event.headers || {};
  return h[name] || h[name.toLowerCase()] || h[name.toUpperCase()] || null;
}
function json(statusCode, body) {
  return { statusCode, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}
function env(name) {
  const v = process.env[name];
  return v && v.trim() ? v.trim() : null;
}

// ─── ЮKassa: создание платежа ────────────────────────────────────
// POST /billing/create  { userId, plan }  →  { confirmationUrl, paymentId }
async function createPayment(event, rid) {
  const shopId = env('YOOKASSA_SHOP_ID');
  const secret = env('YOOKASSA_SECRET_KEY');
  const returnUrl = env('WEB_RETURN_URL') || 'https://aivibe.app/cabinet?paid=1';
  if (!shopId || !secret) {
    log('warn', rid, 'yookassa not configured');
    return json(503, { ok: false, reason: 'not-configured', message: 'Оплата подключится после регистрации магазина ЮKassa.' });
  }

  let payload;
  try { payload = JSON.parse(event.body || '{}'); } catch { return json(400, { ok: false, reason: 'bad-json' }); }
  const plan = String(payload.plan || '');
  const userId = String(payload.userId || '').slice(0, 128);
  if (!ALLOWED_PLANS.has(plan)) return json(400, { ok: false, reason: 'bad-plan' });
  if (!userId) return json(400, { ok: false, reason: 'no-user' });

  const amount = SUB_PRICE_RUB[plan];
  const auth = Buffer.from(`${shopId}:${secret}`).toString('base64');
  const idempotenceKey = crypto.randomUUID();

  try {
    const res = await fetch('https://api.yookassa.ru/v3/payments', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Idempotence-Key': idempotenceKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: { value: amount.toFixed(2), currency: 'RUB' },
        capture: true,
        confirmation: { type: 'redirect', return_url: returnUrl },
        description: `AIVibe — подписка ${plan}`,
        metadata: { userId, plan },
      }),
    });
    const data = await res.json();
    if (!res.ok) {
      log('error', rid, 'yookassa create failed', { status: res.status });
      return json(502, { ok: false, reason: 'yookassa-error' });
    }
    log('info', rid, 'payment created', { paymentId: data.id, plan, amount });
    return json(200, { ok: true, paymentId: data.id, confirmationUrl: data.confirmation?.confirmation_url || null });
  } catch (e) {
    log('error', rid, 'yookassa fetch error', { err: String(e && e.message) });
    return json(502, { ok: false, reason: 'yookassa-unreachable' });
  }
}

// ─── ЮKassa: вебхук уведомлений ──────────────────────────────────
// POST /billing/webhook  { event, object }  — подтверждаем оплату ПЕРЕПРОВЕРКОЙ
// статуса платежа в API (не доверяем телу запроса вслепую).
async function handleWebhook(event, rid) {
  const shopId = env('YOOKASSA_SHOP_ID');
  const secret = env('YOOKASSA_SECRET_KEY');
  if (!shopId || !secret) return json(503, { ok: false, reason: 'not-configured' });

  let body;
  try { body = JSON.parse(event.body || '{}'); } catch { return json(400, { ok: false }); }
  const paymentId = body?.object?.id;
  if (!paymentId) return json(400, { ok: false, reason: 'no-payment-id' });

  const auth = Buffer.from(`${shopId}:${secret}`).toString('base64');
  try {
    const res = await fetch(`https://api.yookassa.ru/v3/payments/${encodeURIComponent(paymentId)}`, {
      headers: { 'Authorization': `Basic ${auth}` },
    });
    const data = await res.json();
    if (!res.ok) return json(502, { ok: false, reason: 'verify-failed' });

    if (data.status === 'succeeded' && data.paid) {
      // TODO(persist): отметить подписку пользователя активной в YDB
      // metadata.userId / metadata.plan → запись подписки с датой окончания.
      log('info', rid, 'payment confirmed', { paymentId, userId: data.metadata?.userId, plan: data.metadata?.plan });
    } else {
      log('info', rid, 'payment not succeeded', { paymentId, status: data.status });
    }
    return json(200, { ok: true }); // ЮKassa требует 200, иначе ретраит
  } catch (e) {
    log('error', rid, 'webhook verify error', { err: String(e && e.message) });
    return json(502, { ok: false });
  }
}

// ─── OAuth Яндекс ID: обмен кода на токен + профиль ──────────────
// GET /auth/yandex/callback?code=...  →  редирект в кабинет с сессией
async function yandexCallback(event, rid) {
  const clientId = env('YANDEX_OAUTH_CLIENT_ID');
  const clientSecret = env('YANDEX_OAUTH_CLIENT_SECRET');
  if (!clientId || !clientSecret) return json(503, { ok: false, reason: 'not-configured', message: 'Яндекс ID не настроен.' });

  const code = (event.queryStringParameters || {}).code;
  if (!code) return json(400, { ok: false, reason: 'no-code' });

  try {
    const tokenRes = await fetch('https://oauth.yandex.ru/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'authorization_code', code, client_id: clientId, client_secret: clientSecret }),
    });
    const token = await tokenRes.json();
    if (!tokenRes.ok || !token.access_token) return json(502, { ok: false, reason: 'token-failed' });

    const infoRes = await fetch('https://login.yandex.ru/info?format=json', {
      headers: { 'Authorization': `OAuth ${token.access_token}` },
    });
    const info = await infoRes.json();
    // TODO(session): создать/найти пользователя в YDB, выдать сессионный JWT,
    // вернуть Set-Cookie + редирект на WEB_RETURN_URL.
    log('info', rid, 'yandex auth ok', { uid: info.id });
    return json(200, { ok: true, provider: 'yandex', user: { id: info.id, name: info.real_name || info.display_name, email: info.default_email || null } });
  } catch (e) {
    log('error', rid, 'yandex oauth error', { err: String(e && e.message) });
    return json(502, { ok: false, reason: 'oauth-error' });
  }
}

// VK ID использует OAuth 2.1 + PKCE (code_verifier/device_id) — обмен делает
// VK ID SDK на фронте, бэкенд верифицирует id_token. Реализуется при подключении
// VK ID (см. docs). Здесь — явная заглушка, чтобы не выдавать неверный flow.
function vkCallback(event, rid) {
  log('warn', rid, 'vk id not implemented');
  return json(501, { ok: false, reason: 'vk-id-todo', message: 'VK ID подключается через VK ID SDK (PKCE) — см. docs/AUTH_PAYMENT_INTEGRATION.md.' });
}

// ─── роутер ──────────────────────────────────────────────────────
export const handler = async (event) => {
  const rid = getHeader(event, 'x-request-id') || crypto.randomUUID();
  const method = event.httpMethod || 'GET';
  const path = (event.path || event.rawPath || '/').replace(/\/+$/, '') || '/';

  try {
    if (method === 'POST' && path.endsWith('/billing/create')) return await createPayment(event, rid);
    if (method === 'POST' && path.endsWith('/billing/webhook')) return await handleWebhook(event, rid);
    if (method === 'GET' && path.endsWith('/auth/yandex/callback')) return await yandexCallback(event, rid);
    if (method === 'GET' && path.endsWith('/auth/vk/callback')) return vkCallback(event, rid);
    return json(404, { ok: false, reason: 'not-found' });
  } catch (e) {
    log('error', rid, 'unhandled', { err: String(e && e.message) });
    return json(500, { ok: false, reason: 'internal' });
  }
};
