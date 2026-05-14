/**
 * Blocked Users Manager — управление блокировками пользователей AIVibe
 *
 * Функционал:
 *   - Persistent storage: blocked_users.json (создаётся при первом запуске)
 *   - Strike counting: 3 strikes (severity 3) → 24h ban
 *   - Immediate block: severity 4-5 → instant 24h ban
 *   - Auto-cleanup: expired blocks удаляются при каждой проверке
 *   - Admin API: list, unblock, stats
 *
 * Структура записи:
 *   {
 *     userId: string,
 *     blockedAt: ISO string,
 *     expiresAt: ISO string,
 *     reason: string,
 *     injectionPrompt: string,  // truncated to 200 chars
 *     severity: number,
 *     rule: string,
 *     isStrikeBan: boolean,   // true if from 3 strikes
 *     strikeCount: number,    // current strikes at ban time
 *   }
 */

'use strict';

const fs = require('fs');
const path = require('path');

// Путь к JSON-хранилищу (рядом с этим файлом)
const STORAGE_FILE = path.join(__dirname, 'blocked_users.json');

// TTL блокировки: 24 часа
const BAN_TTL_MS = 24 * 60 * 60 * 1000;

// Триггер: сколько strikes → бан
const STRIKE_THRESHOLD = 3;

// ============================================================================
// Persistence
// ============================================================================

function loadStorage() {
  try {
    if (fs.existsSync(STORAGE_FILE)) {
      const raw = fs.readFileSync(STORAGE_FILE, { encoding: 'utf8' });
      const parsed = JSON.parse(raw);
      return validateStorage(parsed);
    }
  } catch (e) {
    // Если файл битый — пишем в лог, создаём пустое хранилище
    console.error('Failed to load blocked_users.json:', (e && e.message) || 'unknown');
  }
  return { users: {}, strikes: {} };
}

function saveStorage(data) {
  // Минимизируем write-amplification: не пишем каждый раз, но сейчас sync
  try {
    fs.writeFileSync(STORAGE_FILE, JSON.stringify(data, null, 2), { encoding: 'utf8' });
  } catch (e) {
    console.error('Failed to save blocked_users.json:', (e && e.message) || 'unknown');
  }
}

function validateStorage(parsed) {
  const result = { users: {}, strikes: {} };
  if (parsed && typeof parsed === 'object') {
    if (parsed.users && typeof parsed.users === 'object') {
      result.users = parsed.users;
    }
    if (parsed.strikes && typeof parsed.strikes === 'object') {
      result.strikes = parsed.strikes;
    }
  }
  return result;
}

// In-memory (при рестарте YCF читаем с диска)
const memStorage = loadStorage();

// ============================================================================
// Core functions
// ============================================================================

function nowIso() {
  return new Date().toISOString();
}

function futureIso(ms) {
  return new Date(Date.now() + ms).toISOString();
}

function isExpired(entry) {
  return new Date(entry.expiresAt) < new Date();
}

function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '...' : str;
}

function sanitizeUserId(userId) {
  if (typeof userId !== 'string') return '';
  return userId.replace(/[^a-zA-Z0-9_\-.@]/g, '').slice(0, 64);
}

// ── Cleanup expired blocks ─────────────────────────────────────────────────
function cleanupExpired() {
  const beforeCount = Object.keys(memStorage.users).length;
  let cleaned = 0;

  for (const [userId, entry] of Object.entries(memStorage.users)) {
    if (isExpired(entry)) {
      delete memStorage.users[userId];
      cleaned++;
    }
  }

  if (cleaned > 0) {
    saveStorage(memStorage);
  }
  return { before: beforeCount, after: beforeCount - cleaned, cleaned };
}

// ── Check if user is currently blocked ─────────────────────────────────────
function isBlocked(userIdRaw) {
  const userId = sanitizeUserId(userIdRaw);
  if (!userId) return { blocked: false };

  const entry = memStorage.users[userId];
  if (!entry) return { blocked: false };

  if (isExpired(entry)) {
    delete memStorage.users[userId];
    saveStorage(memStorage);
    return { blocked: false };
  }

  return {
    blocked: true,
    blockedAt: entry.blockedAt,
    expiresAt: entry.expiresAt,
    reason: entry.reason,
    severity: entry.severity,
    isStrikeBan: entry.isStrikeBan,
    strikeCount: entry.strikeCount,
  };
}

// ── Increment strike count ─────────────────────────────────────────────────
function addStrike(userIdRaw, promptResult) {
  const userId = sanitizeUserId(userIdRaw);
  if (!userId) return { banned: false, strikes: 0 };

  const current = memStorage.strikes[userId] || { count: 0, lastTs: null, history: [] };
  current.count += 1;
  current.lastTs = nowIso();
  current.history.push({
    ts: nowIso(),
    reason: promptResult.reason,
    rule: promptResult.rule,
    severity: promptResult.severity,
    promptPreview: truncate(promptResult.prompt || '', 120),
  });

  // Keep history bounded
  if (current.history.length > 20) {
    current.history = current.history.slice(-20);
  }

  memStorage.strikes[userId] = current;

  // Check threshold
  if (current.count >= STRIKE_THRESHOLD) {
    const banResult = blockUser(userId, {
      reason: `${STRIKE_THRESHOLD} strikes reached (${promptResult.reason})`,
      injectionPrompt: promptResult.prompt || '',
      severity: Math.max(promptResult.severity, 3),
      rule: promptResult.rule,
      isStrikeBan: true,
      strikeCount: current.count,
    });
    saveStorage(memStorage);
    return { banned: true, strikes: current.count, banResult };
  }

  saveStorage(memStorage);
  return { banned: false, strikes: current.count };
}

// ── Immediate block ────────────────────────────────────────────────────────
function blockUser(userIdRaw, opts = {}) {
  const userId = sanitizeUserId(userIdRaw);
  if (!userId) return { ok: false, error: 'Invalid userId' };

  const now = nowIso();
  const expires = futureIso(BAN_TTL_MS);

  const entry = {
    userId,
    blockedAt: now,
    expiresAt: expires,
    reason: truncate(opts.reason || 'Policy violation', 200),
    injectionPrompt: truncate(opts.injectionPrompt || '', 200),
    severity: Math.min(Math.max(opts.severity || 4, 1), 5),
    rule: truncate(opts.rule || '', 128),
    isStrikeBan: !!opts.isStrikeBan,
    strikeCount: opts.strikeCount || (memStorage.strikes[userId]?.count || 0),
  };

  memStorage.users[userId] = entry;

  // Reset strikes on ban (they earned it, start fresh after ban)
  if (memStorage.strikes[userId]) {
    memStorage.strikes[userId].count = 0;
  }

  saveStorage(memStorage);

  return {
    ok: true,
    userId,
    blockedAt: now,
    expiresAt: expires,
    reason: entry.reason,
    severity: entry.severity,
  };
}

// ── Unblock (admin action) ─────────────────────────────────────────────────
function unblockUser(userIdRaw) {
  const userId = sanitizeUserId(userIdRaw);
  if (!userId) return { ok: false, error: 'Invalid userId' };

  const hadEntry = !!memStorage.users[userId];
  delete memStorage.users[userId];
  
  // Also clear strikes
  delete memStorage.strikes[userId];

  saveStorage(memStorage);

  return { ok: true, userId, wasBlocked: hadEntry };
}

// ── List all blocked users (admin) ─────────────────────────────────────────
function listBlocked() {
  cleanupExpired(); // clean before listing

  const list = Object.values(memStorage.users).map((entry) => ({
    userId: entry.userId,
    blockedAt: entry.blockedAt,
    expiresAt: entry.expiresAt,
    reason: entry.reason,
    severity: entry.severity,
    rule: entry.rule,
    isStrikeBan: entry.isStrikeBan,
    strikeCount: entry.strikeCount,
    injectionPrompt: entry.injectionPrompt,
    // Add computed: remaining time
    remainingMinutes: Math.max(0, Math.ceil((new Date(entry.expiresAt) - Date.now()) / 60000)),
  }));

  // Sort by severity desc, then by blockedAt desc
  list.sort((a, b) => {
    if (b.severity !== a.severity) return b.severity - a.severity;
    return new Date(b.blockedAt) - new Date(a.blockedAt);
  });

  return list;
}

// ── Statistics ─────────────────────────────────────────────────────────────
function getStats() {
  const all = Object.values(memStorage.users);
  const active = all.filter((e) => !isExpired(e));
  const totalBans = all.filter((e) => e.isStrikeBan).length;

  const severityCounts = { 5: 0, 4: 0, 3: 0 };
  active.forEach((e) => {
    if (e.severity >= 3 && e.severity <= 5) {
      severityCounts[e.severity] = (severityCounts[e.severity] || 0) + 1;
    }
  });

  const now = Date.now();
  const last24h = active.filter((e) => (now - new Date(e.blockedAt)) <= 86400000).length;

  return {
    activeBlocks: active.length,
    totalBlocksRecorded: all.length,
    strikeBans: totalBans,
    immediateBans: active.length - totalBans,
    severityBreakdown: severityCounts,
    last24hBlocks: last24h,
    strikeThreshold: STRIKE_THRESHOLD,
    banDurationHours: Math.floor(BAN_TTL_MS / 3600000),
  };
}

// ============================================================================
// Express middleware helpers
// ============================================================================

/**
 * Middleware: проверяет, не заблокирован ли userId в запросе.
 * Если заблокирован — 403 с сообщением.
 */
function checkBlockedMiddleware(req, res, next) {
  try {
    const userId = req.body && req.body.userId;
    if (!userId || typeof userId !== 'string') {
      return next();
    }

    const check = isBlocked(userId);
    if (check.blocked) {
      return res.status(403).json({
        error: 'User temporarily blocked.',
        blockedUntil: check.expiresAt,
        reason: check.reason,
      });
    }
    next();
  } catch (e) {
    console.error('Block check middleware error:', (e && e.message) || 'unknown');
    next();
  }
}

// ============================================================================
// Express route handlers (to be mounted in index.js)
// ============================================================================

function createBlockedUsersRouter() {
  const express = require('express');
  const router = express.Router();

  // List blocked users
  router.get('/blocked-users', (req, res) => {
    try {
      const list = listBlocked();
      res.json({
        data: list,
        total: list.length,
        stats: getStats(),
        generatedAt: nowIso(),
      });
    } catch (e) {
      console.error('List blocked error:', (e && e.message) || 'unknown');
      res.status(500).json({ error: 'Internal error' });
    }
  });

  // Unblock user
  router.delete('/blocked-users/:userId', (req, res) => {
    try {
      const userId = sanitizeUserId(req.params.userId);
      if (!userId) {
        return res.status(400).json({ error: 'Invalid userId' });
      }
      const result = unblockUser(userId);
      if (!result.ok) {
        return res.status(400).json({ error: result.error });
      }
      res.json(result);
    } catch (e) {
      console.error('Unblock error:', (e && e.message) || 'unknown');
      res.status(500).json({ error: 'Internal error' });
    }
  });

  // Stats only
  router.get('/blocked-users/stats', (req, res) => {
    try {
      res.json(getStats());
    } catch (e) {
      console.error('Stats error:', (e && e.message) || 'unknown');
      res.status(500).json({ error: 'Internal error' });
    }
  });

  // Cleanup trigger (admin or cron)
  router.post('/blocked-users/cleanup', (req, res) => {
    try {
      const result = cleanupExpired();
      res.json(result);
    } catch (e) {
      console.error('Cleanup error:', (e && e.message) || 'unknown');
      res.status(500).json({ error: 'Internal error' });
    }
  });

  return router;
}

module.exports = {
  // Core
  checkBlockedMiddleware,
  isBlocked,
  blockUser,
  unblockUser,
  addStrike,
  cleanupExpired,
  listBlocked,
  getStats,
  sanitizeUserId,

  // Express
  createBlockedUsersRouter,

  // Constants
  BAN_TTL_MS,
  STRIKE_THRESHOLD,
};
