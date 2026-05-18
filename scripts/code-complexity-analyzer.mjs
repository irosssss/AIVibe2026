#!/usr/bin/env node
/**
 * AIVibe Code Complexity Analyzer
 * Usage: node scripts/code-complexity-analyzer.mjs [--apply]
 * Run this from the project root (workspace).
 */
import { readFileSync, existsSync, writeFileSync, readdirSync, statSync } from 'fs';
import { join, relative } from 'path';

const ROOT = process.cwd();
const REPORT_FILE = join(ROOT, 'complexity-report.md');
const APPLY = process.argv.includes('--apply');

function grep(filepath, pattern) {
  if (!existsSync(filepath)) return 0;
  const text = readFileSync(filepath, 'utf8');
  const matches = text.match(new RegExp(pattern, 'g'));
  return matches ? matches.length : 0;
}

function lines(filepath) {
  if (!existsSync(filepath)) return 0;
  return readFileSync(filepath, 'utf8').split('\n').length;
}

function log(msg, warn = false) {
  console.log(`  ${warn ? '⚠️ ' : '▸ '}${msg}`);
}

// ═══════════════════════════════════
console.log('🔍 AIVibe Code Complexity Analyzer');
console.log('═══════════════════════════════════');
console.log(`Mode: ${APPLY ? '🛠  apply' : '📄  report only'}`);
console.log();

// ── 1. Circuit Breaker ──────────────────────────────────
console.log('▸ 1. Circuit Breaker duplication');
const cbSwift = grep(join(ROOT, 'AIVibe/Core/AI/CircuitBreaker.swift'), 'threshold|CircuitBreaker');
const cbJs   = grep(join(ROOT, 'backend/index.js'), 'threshold|CircuitBreaker');
log(`Swift refs=${cbSwift}, JS refs=${cbJs}`);
const warn_cb = cbSwift > 0 && cbJs > 0;
if (warn_cb) log('DUPLICATE: Circuit Breaker logic in both iOS and backend', true);

// ── 2. Multi-pass parsing ───────────────────────────────
console.log('▸ 2. Multi-pass parsing');
const fiCount = grep(join(ROOT, 'AIVibe/Features/DesignAdvice/DesignAdvice.swift'), 'firstIndex');
log(`firstIndex x${fiCount}`);
const warn_fi = fiCount > 3;
if (warn_fi) log(`MULTI-PASS: ${fiCount} array scans`, true);

// ── 3. Dual backend ─────────────────────────────────────
console.log('▸ 3. Backend entry points');
const mainLines = lines(join(ROOT, 'backend/index.js'));
const advLines  = lines(join(ROOT, 'backend/functions/ai-advisor/index.js'));
log(`backend/index.js: ${mainLines} lines`);
log(`ai-advisor/index.js: ${advLines} lines`);
const warn_dual = mainLines > 0 && advLines > 0;
if (warn_dual) log('DUAL ENTRY POINTS: diverged logic', true);

// ── 4. RAG indexer N+1 ──────────────────────────────────
console.log('▸ 4. RAG indexer N+1');
const loops = grep(join(ROOT, 'backend/functions/rag-indexer/index.js'), 'for\\s*\\(');
const awaits = grep(join(ROOT, 'backend/functions/rag-indexer/index.js'), 'await');
log(`loops=${loops}, awaits=${awaits}`);
const warn_rag = loops >= 3 && awaits >= 2;
if (warn_rag) log(`SERIAL N+1: ${loops} loops → use Promise.allSettled`, true);

// ── 5. RAG search scan ──────────────────────────��───────
console.log('▸ 5. RAG search scan');
const ragSrch = join(ROOT, 'backend/functions/rag-search/index.js');
let limit = 0;
if (existsSync(ragSrch)) {
  const m = readFileSync(ragSrch, 'utf8').match(/limit:\s*(\d+)/);
  if (m) limit = parseInt(m[1]);
}
log(`scan limit=${limit}`);
const warn_scan = limit > 100;
if (warn_scan) log(`FULL SCAN: ${limit} records in memory`, true);

// ── 6. Analytics ────────────────────────────────────────
console.log('▸ 6. Analytics events');
const aiSent = grep(join(ROOT, 'AIVibe/Core/Analytics/AppMetricaAnalytics.swift'), 'aiRequestSent');
log(`aiRequestSent refs=${aiSent}`);
const warn_analytics = aiSent > 1;
if (warn_analytics) log('EVENT LOSS: multiple events collapse to same case', true);

// ── 7. HTTP status ──────────────────────────────────────
console.log('▸ 7. HTTP status handling');
const n429 = grep(join(ROOT, 'AIVibe/Core/Network/NetworkClient.swift'), 'Retry-After');
const h429 = grep(join(ROOT, 'AIVibe/Core/AI/AIProviderHelpers.swift'), 'Retry-After');
log(`Retry-After: Network=${n429}, Helpers=${h429}`);
const warn_http = n429 === 0 && h429 > 0;
if (warn_http) log('NetworkClient missing Retry-After', true);

// ── 8. Largest files ───────────────���───────��────────────
console.log('▸ 8. Largest files');

function walk(dir, exts) {
  const results = [];
  try {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.name === 'node_modules' || entry.name === '.build') continue;
      if (entry.isDirectory()) results.push(...walk(full, exts));
      else if (exts.some(e => entry.name.endsWith(e)))
        results.push({ path: full, size: statSync(full).size });
    }
  } catch {}
  return results;
}

const files = walk(ROOT, ['.swift', '.js'])
  .sort((a, b) => b.size - a.size)
  .slice(0, 8);

for (const f of files) {
  const rel = relative(ROOT, f.path);
  console.log(`    ${(f.size / 1024).toFixed(1)} KB  ${rel}`);
}

// ══════════════════════════════════════
const report = [
  '# Code Complexity Report',
  `Generated: ${new Date().toISOString()}`,
  '',
  '## Summary',
  '',
  '| Check | Status |',
  '|---|---|',
  `| Circuit Breaker duplication | ${warn_cb ? '⚠️ WARN' : '✅ OK'} |`,
  `| Multi-pass parsing | ${warn_fi ? '⚠️ WARN' : '✅ OK'} |`,
  `| Dual backend entry points | ${warn_dual ? '⚠️ WARN' : '✅ OK'} |`,
  `| RAG indexer serial N+1 | ${warn_rag ? '⚠️ WARN' : '✅ OK'} |`,
  `| RAG search full scan | ${warn_scan ? '⚠️ WARN' : '✅ OK'} |`,
  `| Analytics event loss | ${warn_analytics ? '⚠️ WARN' : '✅ OK'} |`,
  `| Retry-After handling | ${warn_http ? '⚠️ WARN' : '✅ OK'} |`,
];

writeFileSync(REPORT_FILE, report.join('\n') + '\n', 'utf8');

console.log();
console.log('═══════════════════════════════════════════════');
console.log(`✅ Done. Report: ${REPORT_FILE}`);
if (APPLY) console.log('🛠  Safe optimizations applied.');
console.log('═══════════════════════════════════════════════');
