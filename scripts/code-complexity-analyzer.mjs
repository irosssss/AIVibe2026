#!/usr/bin/env node
/**
 * AIVibe Code Complexity Analyzer
 *
 * Сканирует кодовую базу на типовые архитектурные проблемы:
 * рассинхрон констант, N+1 запросы, потерянные analytics-события,
 * многопроходный парсинг, full-scan по БД.
 *
 * Запуск:
 *   node scripts/code-complexity-analyzer.mjs
 *
 * Exit codes:
 *   0 — все проверки прошли
 *   1 — есть WARN'ы (в CI можно использовать как gate)
 *   2 — внутренняя ошибка скрипта
 *
 * При добавлении новой проверки — следовать паттерну:
 *   const check = checkSomething();
 *   results.push(check);
 *
 * Все пути относительно корня репозитория.
 */

import { readFileSync, existsSync, writeFileSync, readdirSync, statSync } from 'fs';
import { join, relative } from 'path';

// ─── Конфиг ──────────────────────────────────────────────────────

const ROOT = process.cwd();
const REPORT_FILE = join(ROOT, 'complexity-report.md');

// Пути проекта (актуализированы под текущую структуру)
const PATHS = {
    // iOS
    cbConfigSwift:   'AIVibe/Core/AI/CircuitBreakerConfig.swift',
    cbSwift:         'AIVibe/Core/AI/CircuitBreaker.swift',
    designAdvice:    'AIVibe/Features/AIAdvisor/Models/DesignAdvice.swift',
    analytics:       'AIVibe/Core/Analytics/AppMetricaAnalytics.swift',
    networkClient:   'AIVibe/Core/Network/NetworkClient.swift',
    helpers:         'AIVibe/Core/AI/AIProviderHelpers.swift',
    // Backend
    cbConfigJs:      'backend/shared/circuit-config.js',
    cbJs:            'backend/shared/circuit-breaker.js',
    backendIndex:    'backend/index.js',
    aiAdvisor:       'backend/functions/ai-advisor/index.js',
    ragIndexer:      'backend/functions/rag-indexer/index.js',
    ragSearch:       'backend/shared/rag-search.js',
};

// Пороги для warn-условий
const THRESHOLDS = {
    multiPassFirstIndex: 3,
    ragSearchScanLimit:  100,
    ragIndexerLoops:     3,
    ragIndexerAwaits:    2,
    analyticsCollisions: 1,
};

// ─── Утилиты ─────────────────────────────────────────────────────

const COLORS = { reset: '\x1b[0m', red: '\x1b[31m', yellow: '\x1b[33m', green: '\x1b[32m', dim: '\x1b[2m' };

function fileExists(relPath) {
    return existsSync(join(ROOT, relPath));
}

function readFile(relPath) {
    const full = join(ROOT, relPath);
    if (!existsSync(full)) return null;
    return readFileSync(full, 'utf8');
}

function countMatches(relPath, pattern) {
    const text = readFile(relPath);
    if (text === null) return null; // null = файл не найден (distinct from 0)
    const matches = text.match(new RegExp(pattern, 'g'));
    return matches ? matches.length : 0;
}

function lineCount(relPath) {
    const text = readFile(relPath);
    if (text === null) return null;
    return text.split('\n').length;
}

function extractNumber(relPath, regex) {
    const text = readFile(relPath);
    if (text === null) return null;
    const m = text.match(regex);
    return m ? parseInt(m[1], 10) : null;
}

function logCheck(num, title) {
    console.log(`\n▸ ${num}. ${title}`);
}

function logInfo(msg) {
    console.log(`   ${COLORS.dim}${msg}${COLORS.reset}`);
}

function logWarn(msg) {
    console.log(`   ${COLORS.yellow}⚠️  ${msg}${COLORS.reset}`);
}

function logOk(msg) {
    console.log(`   ${COLORS.green}✅ ${msg}${COLORS.reset}`);
}

function logMissing(path) {
    console.log(`   ${COLORS.red}❌ Файл не найден: ${path}${COLORS.reset}`);
}

// ─── Старт ───────────────────────────────────────────────────────

console.log(`\n${COLORS.green}🔍 AIVibe Code Complexity Analyzer${COLORS.reset}`);
console.log('═══════════════════════════════════════════════════');
console.log(`Root: ${ROOT}`);

const results = [];

// ─── 1. Circuit Breaker: рассинхрон констант iOS ↔ backend ───────

logCheck(1, 'Circuit Breaker — синхронизация констант');

const swiftThreshold = extractNumber(PATHS.cbConfigSwift, /threshold:\s*(\d+)/);
const swiftTimeout   = extractNumber(PATHS.cbConfigSwift, /timeout:\s*(\d+)/);
const jsThreshold    = extractNumber(PATHS.cbConfigJs, /CIRCUIT_THRESHOLD\s*=\s*(\d+)/);
const jsCooldownMs   = extractNumber(PATHS.cbConfigJs, /CIRCUIT_COOLDOWN_MS\s*=\s*(\d+)\s*\*\s*(\d+)_000/);

if (swiftThreshold === null) logMissing(PATHS.cbConfigSwift);
if (jsThreshold === null) logMissing(PATHS.cbConfigJs);

// JS cooldown в миллисекундах — конвертируем в секунды
const jsTimeoutSec = jsCooldownMs !== null
    ? extractNumber(PATHS.cbConfigJs, /CIRCUIT_COOLDOWN_MS\s*=\s*(\d+)\s*\*\s*60_000/) * 60
    : null;

logInfo(`Swift: threshold=${swiftThreshold}, timeout=${swiftTimeout}s`);
logInfo(`JS:    threshold=${jsThreshold}, cooldown=${jsTimeoutSec}s`);

const warn_cb = (
    swiftThreshold !== null && jsThreshold !== null && swiftThreshold !== jsThreshold
) || (
    swiftTimeout !== null && jsTimeoutSec !== null && swiftTimeout !== jsTimeoutSec
);

if (warn_cb) {
    logWarn('РАССИНХРОН: Circuit Breaker константы различаются между iOS и backend!');
} else if (swiftThreshold === jsThreshold && swiftTimeout === jsTimeoutSec) {
    logOk('Константы синхронизированы');
}
results.push({ name: 'Circuit Breaker constants sync', warn: warn_cb });

// ─── 2. Multi-pass parsing in DesignAdvice ───────────────────────

logCheck(2, 'Multi-pass parsing (DesignAdvice.swift)');

const fiCount = countMatches(PATHS.designAdvice, 'firstIndex');

if (fiCount === null) {
    logMissing(PATHS.designAdvice);
    results.push({ name: 'Multi-pass parsing', warn: false, skipped: true });
} else {
    logInfo(`firstIndex × ${fiCount}`);
    const warn_fi = fiCount > THRESHOLDS.multiPassFirstIndex;
    if (warn_fi) {
        logWarn(`${fiCount} проходов по массиву — рассмотреть single-pass парсер`);
    } else {
        logOk(`${fiCount} ≤ ${THRESHOLDS.multiPassFirstIndex} (порог)`);
    }
    results.push({ name: 'Multi-pass parsing', warn: warn_fi });
}

// ─── 3. Backend entry points (информационно) ─────────────────────

logCheck(3, 'Backend entry points (info)');

const mainLines = lineCount(PATHS.backendIndex);
const advLines  = lineCount(PATHS.aiAdvisor);

if (mainLines !== null) logInfo(`${PATHS.backendIndex}: ${mainLines} строк`);
else logMissing(PATHS.backendIndex);

if (advLines !== null) logInfo(`${PATHS.aiAdvisor}: ${advLines} строк`);
else logMissing(PATHS.aiAdvisor);

// Проверяем что оба используют единый triplex-fallback (не дублируют логику)
const mainUsesShared = readFile(PATHS.backendIndex)?.includes("from './shared/triplex-fallback")
                    || readFile(PATHS.backendIndex)?.includes('shared/triplex-fallback');
const advUsesShared  = readFile(PATHS.aiAdvisor)?.includes('triplex-fallback');

const warn_dual = (mainLines !== null && advLines !== null)
               && !(mainUsesShared && advUsesShared);

if (mainUsesShared && advUsesShared) {
    logOk('Оба entry-point используют shared/triplex-fallback — норма');
} else if (warn_dual) {
    logWarn('Один из entry-points НЕ использует shared/triplex-fallback — риск дублирования');
}
results.push({ name: 'Backend entry points use shared fallback', warn: warn_dual });

// ─── 4. RAG indexer serial N+1 ────────────────────────────────────

logCheck(4, 'RAG indexer — serial N+1 HTTP calls');

const loops  = countMatches(PATHS.ragIndexer, 'for\\s*\\(');
const awaits = countMatches(PATHS.ragIndexer, 'await');

if (loops === null) {
    logMissing(PATHS.ragIndexer);
    results.push({ name: 'RAG indexer N+1', warn: false, skipped: true });
} else {
    logInfo(`loops=${loops}, awaits=${awaits}`);
    const warn_rag = loops >= THRESHOLDS.ragIndexerLoops && awaits >= THRESHOLDS.ragIndexerAwaits;
    // Дополнительно проверяем наличие parallelLimit / Promise.all — антидот к N+1
    const hasParallel = readFile(PATHS.ragIndexer)?.match(/parallelLimit|Promise\.all/);
    if (warn_rag && !hasParallel) {
        logWarn(`${loops} циклов с ${awaits} awaits — serial N+1, нет Promise.all/parallelLimit`);
    } else if (hasParallel) {
        logOk('Найден parallelLimit / Promise.all — параллелизация присутствует');
    } else {
        logOk('Нет признаков N+1');
    }
    results.push({ name: 'RAG indexer N+1', warn: warn_rag && !hasParallel });
}

// ─── 5. RAG search — full scan лимит ──────────────────────────────
// После B6 поиск обязан идти через scanFiltered (пре-фильтр на стороне YDB,
// страницы с потолком), а не через ydbClient.scan() всей таблицы.

logCheck(5, 'RAG search — full scan лимит');

const ragSearchText = readFile(PATHS.ragSearch);

if (ragSearchText === null) {
    logMissing(PATHS.ragSearch);
    results.push({ name: 'RAG search full scan', warn: false, skipped: true });
} else {
    const usesFullScan = /ydbClient\.scan\(/.test(ragSearchText);
    const usesFiltered = /scanFiltered\(/.test(ragSearchText);
    const pageLimit = extractNumber(PATHS.ragSearch, /PAGE_LIMIT\s*=\s*(\d+)/);
    logInfo(`scanFiltered: ${usesFiltered}, full scan: ${usesFullScan}, PAGE_LIMIT = ${pageLimit}`);

    let warn_scan = false;
    if (usesFullScan || !usesFiltered) {
        warn_scan = true;
        logWarn('RAG-поиск не использует scanFiltered — full scan загружает все записи в память');
        logWarn('Фильтрация должна выполняться на стороне YDB (B6)');
    } else if (pageLimit !== null && pageLimit > THRESHOLDS.ragSearchScanLimit) {
        warn_scan = true;
        logWarn(`PAGE_LIMIT ${pageLimit} > ${THRESHOLDS.ragSearchScanLimit} — слишком крупные страницы скана`);
    } else {
        logOk(`Пре-фильтр на стороне YDB, страница ≤ ${THRESHOLDS.ragSearchScanLimit}`);
    }
    results.push({ name: 'RAG search full scan', warn: warn_scan });
}

// ─── 6. Analytics event loss ──────────────────────────────────────

logCheck(6, 'Analytics — event loss (коллизия enum cases)');

const aiSent = countMatches(PATHS.analytics, 'aiRequestSent');

if (aiSent === null) {
    logMissing(PATHS.analytics);
    results.push({ name: 'Analytics event loss', warn: false, skipped: true });
} else {
    logInfo(`aiRequestSent упомянуто × ${aiSent}`);
    const warn_analytics = aiSent > THRESHOLDS.analyticsCollisions;
    if (warn_analytics) {
        logWarn(`Несколько типов событий схлопываются в один enum case`);
    } else {
        logOk('Нет коллизий event-ов');
    }
    results.push({ name: 'Analytics event loss', warn: warn_analytics });
}

// ─── 7. HTTP status handling: Retry-After ─────────────────────────

logCheck(7, 'HTTP status — Retry-After handling');

const n429 = countMatches(PATHS.networkClient, 'Retry-After');
const h429 = countMatches(PATHS.helpers, 'Retry-After');

if (n429 === null) logMissing(PATHS.networkClient);
if (h429 === null) logMissing(PATHS.helpers);

if (n429 !== null && h429 !== null) {
    logInfo(`Retry-After: NetworkClient=${n429}, AIProviderHelpers=${h429}`);
    const warn_http = n429 === 0 && h429 > 0;
    if (warn_http) {
        logWarn('NetworkClient не обрабатывает Retry-After, хотя AIProviderHelpers — обрабатывает');
    } else {
        logOk('Retry-After обрабатывается согласованно');
    }
    results.push({ name: 'Retry-After handling', warn: warn_http });
}

// ─── 8. Largest files (info, not a check) ─────────────────────────

logCheck(8, 'Largest files (top 8 .swift/.js)');

function walk(dir, exts, ignore = ['node_modules', '.build', '.git']) {
    const results = [];
    try {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            if (ignore.includes(entry.name)) continue;
            const full = join(dir, entry.name);
            if (entry.isDirectory()) results.push(...walk(full, exts, ignore));
            else if (exts.some(e => entry.name.endsWith(e))) {
                results.push({ path: full, size: statSync(full).size });
            }
        }
    } catch {}
    return results;
}

const files = walk(ROOT, ['.swift', '.js']).sort((a, b) => b.size - a.size).slice(0, 8);

for (const f of files) {
    const rel = relative(ROOT, f.path);
    console.log(`   ${(f.size / 1024).toFixed(1).padStart(6)} KB  ${rel}`);
}

// ─── Финальный отчёт ──────────────────────────────────────────────

const warnCount = results.filter(r => r.warn).length;
const skipCount = results.filter(r => r.skipped).length;
const okCount = results.length - warnCount - skipCount;

console.log('\n═══════════════════════════════════════════════════');
console.log(`Итого: ${okCount} ✅   ${warnCount} ⚠️    ${skipCount} ⏭`);

// ─── Markdown отчёт ───────────────────────────────────────────────

const reportLines = [
    '# Code Complexity Report',
    '',
    `Generated: ${new Date().toISOString()}`,
    `Script: \`scripts/code-complexity-analyzer.mjs\``,
    '',
    '## Сводка',
    '',
    `- ✅ OK: ${okCount}`,
    `- ⚠️  WARN: ${warnCount}`,
    `- ⏭  Skipped (файлы не найдены): ${skipCount}`,
    '',
    '## Проверки',
    '',
    '| # | Проверка | Статус |',
    '|---|----------|--------|',
];

results.forEach((r, i) => {
    const status = r.skipped ? '⏭ SKIPPED' : (r.warn ? '⚠️ WARN' : '✅ OK');
    reportLines.push(`| ${i + 1} | ${r.name} | ${status} |`);
});

reportLines.push('');
reportLines.push('## Топ-8 файлов по размеру');
reportLines.push('');
reportLines.push('| Размер | Путь |');
reportLines.push('|--------|------|');
files.forEach(f => {
    const rel = relative(ROOT, f.path);
    reportLines.push(`| ${(f.size / 1024).toFixed(1)} KB | \`${rel}\` |`);
});

reportLines.push('');
reportLines.push('---');
reportLines.push('');
reportLines.push('Запуск: `node scripts/code-complexity-analyzer.mjs`');
reportLines.push('При наличии WARN скрипт завершается с exit code 1 — можно использовать как CI gate.');

writeFileSync(REPORT_FILE, reportLines.join('\n') + '\n', 'utf8');

console.log(`Отчёт: ${REPORT_FILE}`);
console.log('═══════════════════════════════════════════════════\n');

// Exit code: 1 если есть warn'ы (для CI)
process.exit(warnCount > 0 ? 1 : 0);
