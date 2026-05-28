// backend/__tests__/rate-limit.test.js
// Unit-тесты для shared/rate-limit.js (node --test, без внешних зависимостей).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRateLimiter, clientIp } from '../shared/rate-limit.js';

test('allows up to max requests, then blocks', () => {
  const check = createRateLimiter({ max: 3 });
  assert.equal(check('a').allowed, true);
  assert.equal(check('a').allowed, true);
  assert.equal(check('a').allowed, true);
  assert.equal(check('a').allowed, false); // 4-й — блок
});

test('remaining counts down', () => {
  const check = createRateLimiter({ max: 2 });
  assert.equal(check('k').remaining, 1);
  assert.equal(check('k').remaining, 0);
  assert.equal(check('k').allowed, false);
});

test('different keys have independent budgets', () => {
  const check = createRateLimiter({ max: 1 });
  assert.equal(check('ip1').allowed, true);
  assert.equal(check('ip2').allowed, true); // другой ключ — свой бюджет
  assert.equal(check('ip1').allowed, false);
});

test('window reset restores budget', () => {
  const check = createRateLimiter({ max: 1, windowMs: -1 }); // окно уже истекло
  assert.equal(check('x').allowed, true);
  assert.equal(check('x').allowed, true); // окно «протухло» → новый бюджет
});

test('clientIp reads requestContext.identity.sourceIp', () => {
  const event = { requestContext: { identity: { sourceIp: '203.0.113.5' } } };
  assert.equal(clientIp(event), '203.0.113.5');
});

test('clientIp falls back to X-Forwarded-For (first hop)', () => {
  const event = { headers: { 'X-Forwarded-For': '198.51.100.7, 10.0.0.1' } };
  assert.equal(clientIp(event), '198.51.100.7');
});

test('clientIp returns "unknown" when nothing present', () => {
  assert.equal(clientIp({}), 'unknown');
  assert.equal(clientIp(null), 'unknown');
});
