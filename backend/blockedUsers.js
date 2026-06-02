/**
 * Blocked Users Manager — управление блокировками пользователей AIVibe
 *
 * Хранение in-memory: состояние сбрасывается при cold start функции.
 * YDB persistence — следующая итерация.
 *
 * Функционал:
 *   - In-memory storage: два Map (blockedStore, strikesStore)
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

// TTL блокировки: 24 часа
const BAN_TTL_MS = 24 * 60 * 60 * 1000;

// Триггер: сколько strikes → бан
const STRIKE_THRESHOLD = 3;

// ============================================================================
// In-memory storage
// ============================================================================
// blockedStore: userId → запись блокировки
// strikesStore: userId → { count, lastTs, history[] }
// При холодном старте функции оба Map пусты — это допустимо для MVP.

const blockedStore = new Map();
const strikesStore = new Map();

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
  const beforeCount = blockedStore.size;
  let cleaned = 0;

  for (const [userId, entry] of blockedStore) {
    if (isExpired(entry)) {
      blockedStore.delete(userId);
      cleaned++;
    }
  }

  return { before: beforeCount, after: beforeCount - cleaned, cleaned };
}

// ── Check if user is currently blocked ─────────────────────────────────────
function isBlocked(userIdRaw) {
  const userId = sanitizeUserId(userIdRaw);
  if (!userId) return { blocked: false };

  const entry = blockedStore.get(userId);
  if (!entry) return { blocked: false };

  if (isExpired(entry)) {
    blockedStore.delete(userId);
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

  const current = strikesStore.get(userId) || { count: 0, lastTs: null, history: [] };
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

  strikesStore.set(userId, current);

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
    return { banned: true, strikes: current.count, banResult };
  }

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
    strikeCount: opts.strikeCount || (strikesStore.get(userId)?.count || 0),
  };

  blockedStore.set(userId, entry);

  // Reset strikes on ban (they earned it, start fresh after ban)
  const strikes = strikesStore.get(userId);
  if (strikes) {
    strikes.count = 0;
  }

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

  const hadEntry = blockedStore.has(userId);
  blockedStore.delete(userId);

  // Also clear strikes
  strikesStore.delete(userId);

  return { ok: true, userId, wasBlocked: hadEntry };
}

// ── List all blocked users (admin) ─────────────────────────────────────────
function listBlocked() {
  cleanupExpired(); // clean before listing

  const list = Array.from(blockedStore.values()).map((entry) => ({
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
  const all = Array.from(blockedStore.values());
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
// NOTE: Express middleware/route handlers are NOT used here.
// Admin API is handled directly in backend/index.js → handleAdminApi()
// which calls isBlocked(), listBlocked(), unblockUser(), etc. directly.
// This avoids an unnecessary dependency on Express.
// ============================================================================

export {
  // Core
  isBlocked,
  blockUser,
  unblockUser,
  addStrike,
  cleanupExpired,
  listBlocked,
  getStats,
  sanitizeUserId,

  // Constants
  BAN_TTL_MS,
  STRIKE_THRESHOLD,
};
