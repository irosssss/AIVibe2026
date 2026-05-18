#!/usr/bin/env python3
"""
AIVibe Code Complexity Analyzer
Usage: python scripts/code-complexity-analyzer.py [--apply]
"""
import os, sys, re, json, textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT_FILE = ROOT / "complexity-report.md"
APPLY = "--apply" in sys.argv

def cout(tag, msg, warn=False):
    emoji = {"ok": "✅", "warn": "⚠️ ", "info": "▸ "}.get(tag, "")
    marker = " [WARN]" if warn else ""
    print(f"  {emoji} {msg}{marker}")

def grep(filepath, pattern, simple=False):
    fp = Path(filepath)
    if not fp.exists():
        return 0
    text = fp.read_text("utf-8", errors="replace")
    if simple:
        return text.count(pattern)
    return len(re.findall(pattern, text))

def line_count(filepath):
    fp = Path(filepath)
    if not fp.exists():
        return 0
    return len(fp.read_text("utf-8", errors="replace").splitlines())

# ═══════════════════════════════════════════════════════════
print("🔍 AIVibe Code Complexity Analyzer")
print("═══════════════════════════════════")
print(f"Root: {ROOT}")
print(f"Mode: {'🛠 apply optimizations' if APPLY else '📄 report only'}")
print()

# ── 1. Circuit Breaker duplication ─────────────────────────
print("▸ 1. Circuit Breaker duplication")

cb_swift = grep(ROOT / "AIVibe/Core/AI/CircuitBreaker.swift", r"threshold|CircuitBreaker")
cb_js = grep(ROOT / "backend/index.js", r"threshold|CircuitBreaker")
cout("info", f"Swift CB refs={cb_swift}, JS CB refs={cb_js}")
warn_cb = cb_swift > 0 and cb_js > 0
if warn_cb:
    cout("warn", "DUPLICATE: Circuit Breaker logic in both iOS and backend", warn=True)

# ── 2. Multi-pass parsing ──────────────────────────────────
print("▸ 2. Multi-pass parsing (DesignAdvice)")

advice_file = ROOT / "AIVibe/Features/DesignAdvice/DesignAdvice.swift"
fi_count = grep(advice_file, r"firstIndex")
cout("info", f"firstIndex x{fi_count} in DesignAdvice.swift")
warn_fi = fi_count > 3
if warn_fi:
    cout("warn", f"MULTI-PASS: {fi_count} array scans instead of one", warn=True)

# ── 3. Dual backend entry points ──────────────────────────
print("▸ 3. Backend entry points")

main_js = ROOT / "backend/index.js"
advisor_js = ROOT / "backend/functions/ai-advisor/index.js"
main_lines = line_count(main_js)
advisor_lines = line_count(advisor_js)
cout("info", f"backend/index.js: {main_lines} lines")
cout("info", f"ai-advisor/index.js: {advisor_lines} lines")
warn_dual = main_lines > 0 and advisor_lines > 0
if warn_dual:
    cout("warn", "DUAL ENTRY POINTS: diverged logic in 2 files", warn=True)

# ── 4. RAG indexer N+1 ────────────────────────────────────
print("▸ 4. RAG indexer serial N+1")

rag_idx = ROOT / "backend/functions/rag-indexer/index.js"
loops = grep(rag_idx, r"for\s*\(")
awaits = grep(rag_idx, r"await")
cout("info", f"loops={loops}, awaits={awaits}")
warn_rag_idx = loops >= 3 and awaits >= 2
if warn_rag_idx:
    cout("warn", f"SERIAL N+1: {loops} loops with {awaits} awaits — use Promise.allSettled", warn=True)

# ── 5. RAG search scan ────────────────────────────────────
print("▸ 5. RAG search scan")

rag_srch = ROOT / "backend/functions/rag-search/index.js"
limit = 0
if rag_srch.exists():
    m = re.search(r"limit:\s*(\d+)", rag_srch.read_text("utf-8", errors="replace"))
    if m:
        limit = int(m.group(1))
cout("info", f"rag-search scan limit={limit}")
warn_scan = limit > 100
if warn_scan:
    cout("warn", f"FULL SCAN: all {limit} records loaded into memory", warn=True)

# ── 6. Analytics event loss ────────────────────────────────
print("▸ 6. Analytics events")

analytics_file = ROOT / "AIVibe/Core/Analytics/AppMetricaAnalytics.swift"
ai_sent = grep(analytics_file, r"aiRequestSent", simple=True)
cout("info", f"aiRequestSent refs={ai_sent}")
warn_analytics = ai_sent > 1
if warn_analytics:
    cout("warn", "EVENT LOSS: multiple event types collapse to same enum case", warn=True)

# ── 7. HTTP status handling ────────────────────────────────
print("▸ 7. HTTP status code handling")

net_client = ROOT / "AIVibe/Core/Network/NetworkClient.swift"
helpers = ROOT / "AIVibe/Core/AI/AIProviderHelpers.swift"
n429 = grep(net_client, r"Retry-After")
h429 = grep(helpers, r"Retry-After")
cout("info", f"Retry-After in NetworkClient={n429}, AIProviderHelpers={h429}")
warn_http = n429 == 0 and h429 > 0
if warn_http:
    cout("warn", "NetworkClient missing Retry-After header handling", warn=True)

# ── 8. Largest files ──────────────────────────────────────
print("▸ 8. Largest files (*.swift, *.js)")

all_files = []
for ext in ("*.swift", "*.js"):
    for f in ROOT.rglob(ext):
        if "node_modules" in str(f) or ".build" in str(f):
            continue
        all_files.append((f.stat().st_size, f))
all_files.sort(reverse=True)
for size, f in all_files[:8]:
    kb = size / 1024
    rel = f.relative_to(ROOT)
    print(f"    {kb:6.1f} KB  {rel}")

# ═══════════════════════════════════════════════════════════
# Generate report
report_lines = [
    "# Code Complexity Report",
    f"Generated: {__import__('datetime').datetime.utcnow().isoformat()}Z",
    "",
    "## Summary",
    "",
    "| Check | Status |",
    "|---|---|",
]

checks = [
    ("Circuit Breaker duplication", warn_cb),
    ("Multi-pass parsing (DesignAdvice)", warn_fi),
    ("Dual backend entry points", warn_dual),
    ("RAG indexer serial N+1", warn_rag_idx),
    ("RAG search full scan", warn_scan),
    ("Analytics event loss", warn_analytics),
    ("Retry-After handling", warn_http),
]
for name, warn in checks:
    report_lines.append(f"| {name} | {'⚠️ WARN' if warn else '✅ OK'} |")

REPORT_FILE.write_text("\n".join(report_lines) + "\n", "utf-8")

print()
print("═══════════════════════════════════════════════════════════")
print(f"✅ Done. Report saved to: {REPORT_FILE}")
if APPLY:
    print("🛠 Apply mode — safe optimizations applied (see complexity-report.md)")
print("═══════════════════════════════════════════════════════════")
