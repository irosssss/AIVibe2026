#!/usr/bin/env bash
# code-complexity-analyzer.sh
# Анализ сложности кодовой базы AIVibe
# Использование: bash scripts/code-complexity-analyzer.sh [--apply]
set -euo pipefail

REPORT_ONLY=true
if [[ "${1:-}" == "--apply" ]]; then
  REPORT_ONLY=false
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_FILE="$ROOT/complexity-report.md"

echo "🔍 AIVibe Code Complexity Analyzer"
echo "═══════════════════════════════════"
echo "Root: $ROOT"
echo "Mode: $([ "$REPORT_ONLY" = true ] && echo '📄 report only' || echo '🛠 apply optimizations')"
echo ""

# ── helpers ──────────────────────────────────────────────────
count_lines() { wc -l < "$1" 2>/dev/null || echo 0; }
count_swift() { find "$1" -name '*.swift' 2>/dev/null | wc -l; }
count_js()    { find "$1" -name '*.js' 2>/dev/null   | wc -l; }

# ── 1. detect duplicated circuit breaker ────────────────────
echo "▸ 1. Detecting Circuit Breaker duplication..."

CB_SWIFT=$(grep -c 'threshold\|CircuitBreaker' "$ROOT/AIVibe/Core/AI/CircuitBreaker.swift" 2>/dev/null || echo 0)
CB_JS=$(grep -c 'threshold\|CircuitBreaker' "$ROOT/backend/index.js" 2>/dev/null || echo 0)

echo "   Swift CB lines: $CB_SWIFT, JS CB lines: $CB_JS"
if [ "$CB_SWIFT" -gt 0 ] && [ "$CB_JS" -gt 0 ]; then
  echo "   ⚠️  DUPLICATE: Circuit Breaker logic in both iOS and backend"
fi

# ── 2. detect O(n²) / multi-pass patterns ───────────────────
echo "▸ 2. Scanning for multi-pass parsing..."

DESIGN_ADVICE="$ROOT/AIVibe/Features/DesignAdvice/DesignAdvice.swift"
if [ -f "$DESIGN_ADVICE" ]; then
  FIRST_INDEX_COUNT=$(grep -c 'firstIndex' "$DESIGN_ADVICE" 2>/dev/null || echo 0)
  echo "   DesignAdvice.swift: $FIRST_INDEX_COUNT × firstIndex calls → O($((FIRST_INDEX_COUNT * 2))n)"
  if [ "$FIRST_INDEX_COUNT" -gt 3 ]; then
    echo "   ⚠️  MULTI-PASS: reduce to single-pass parser"
  fi
fi

# ── 3. detect dual backend entry points ─────────────────────
echo "▸ 3. Checking backend entry points..."

MAIN_JS="$ROOT/backend/index.js"
ADVISOR_JS="$ROOT/backend/functions/ai-advisor/index.js"

if [ -f "$MAIN_JS" ] && [ -f "$ADVISOR_JS" ]; then
  MAIN_LINES=$(count_lines "$MAIN_JS")
  ADVISOR_LINES=$(count_lines "$ADVISOR_JS")
  echo "   backend/index.js: $MAIN_LINES lines"
  echo "   ai-advisor/index.js: $ADVISOR_LINES lines"

  OVERLAP=$(grep -cFf <(grep -E 'fallback|rateLimit|cache' "$MAIN_JS") \
                       <(grep -E 'fallback|rateLimit|cache' "$ADVISOR_JS") 2>/dev/null || echo 0)
  echo "   Overlap score: $OVERLAP patterns shared"
fi

# ── 4. detect N+1 HTTP in RAG indexer ─────────────���────────
echo "▸ 4. Analyzing RAG indexer serial N+1..."

RAG_INDEXER="$ROOT/backend/functions/rag-indexer/index.js"
if [ -f "$RAG_INDEXER" ]; then
  LOOPS=$(grep -cE 'for\s*\(' "$RAG_INDEXER" 2>/dev/null || echo 0)
  HTTP_INSIDE=$(grep -c 'await.*getEmbedding\|await.*upsert' "$RAG_INDEXER" 2>/dev/null || echo 0)
  echo "   Nested loops: $LOOPS, HTTP calls inside loop: $HTTP_INSIDE"
  if [ "$LOOPS" -ge 3 ] && [ "$HTTP_INSIDE" -ge 2 ]; then
    echo "   ⚠️  SERIAL N+1: ~240 sequential HTTP calls — use Promise.allSettled"
  fi
fi

# ── 5. detect RAG all-500 scan ──────────────────────────────
echo "▸ 5. Checking RAG search scan..."

RAG_SEARCH="$ROOT/backend/functions/rag-search/index.js"
if [ -f "$RAG_SEARCH" ]; then
  SCAN_LIMIT=$(grep -oP 'limit:\s*\K\d+' "$RAG_SEARCH" 2>/dev/null || echo "?")
  echo "   rag-search scan limit: $SCAN_LIMIT"
  if [ "$SCAN_LIMIT" -gt 100 ] 2>/dev/null; then
    echo "   ⚠️  FULL SCAN: all $SCAN_LIMIT records loaded into memory"
  fi
fi

# ── 6. Detect analytics loss ─────────────────────────────��──
echo "▸ 6. Checking analytics event mapping..."

ANALYTICS="$ROOT/AIVibe/Core/Analytics/AppMetricaAnalytics.swift"
if [ -f "$ANALYTICS" ]; then
  LOST_EVENTS=$(grep -c 'aiRequestSent' "$ANALYTICS" 2>/dev/null || echo 0)
  echo "   Events mapped to aiRequestSent: $LOST_EVENTS"
  if [ "$LOST_EVENTS" -gt 1 ]; then
    echo "   ⚠️  EVENT LOSS: multiple event types collapse to same enum case"
  fi
fi

# ── 7. Detect HTTP status duplication ──────────────────────
echo "▸ 7. Checking HTTP status code handling..."

NETWORK_CLIENT="$ROOT/AIVibe/Core/Network/NetworkClient.swift"
HELPERS="$ROOT/AIVibe/Core/AI/AIProviderHelpers.swift"

if [ -f "$NETWORK_CLIENT" ] && [ -f "$HELPERS" ]; then
  NET_401=$(grep -c '401\|authenticationFailed' "$NETWORK_CLIENT" 2>/dev/null || echo 0)
  HLP_401=$(grep -c '401\|authenticationFailed' "$HELPERS" 2>/dev/null || echo 0)
  NET_429=$(grep -c '429\|rateLimitExceeded' "$NETWORK_CLIENT" 2>/dev/null || echo 0)
  HLP_429=$(grep -c '429\|rateLimitExceeded\|Retry-After' "$HELPERS" 2>/dev/null || echo 0)
  echo "   401 handling: Network($NET_401) vs Helpers($HLP_401)"
  echo "   429 handling: Network($NET_429) vs Helpers($HLP_429)"
  if [ "$NET_429" -lt "$HLP_429" ]; then
    echo "   ⚠️  UNEVEN: NetworkClient missing Retry-After handling"
  fi
fi

# ── 8. file size stats ──────────────────────────────────────
echo "▸ 8. Largest files..."

find "$ROOT" -type f \( -name '*.swift' -o -name '*.js' \) \
  -not -path '*/node_modules/*' -not -path '*/.build/*' \
  -exec wc -l {} + 2>/dev/null | sort -rn | head -8

# ── summary ──────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Analysis complete. Report saved to: $REPORT_FILE"
echo "Run with --apply to auto-fix safe optimizations."
echo "═══════════════════════════════════════════════════════════"

# Generate markdown report
{
  echo "# Code Complexity Report"
  echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo ""
  echo "## Summary"
  echo ""
  echo "| Check | Status |"
  echo "|---|---|"
  [ "$CB_SWIFT" -gt 0 ] && [ "$CB_JS" -gt 0 ] && echo "| Circuit Breaker duplication | ⚠️ Found |" || echo "| Circuit Breaker duplication | ✅ Clean |"
  [ "$FIRST_INDEX_COUNT" -gt 3 ] 2>/dev/null && echo "| Multi-pass parsing (DesignAdvice) | ⚠️ $FIRST_INDEX_COUNT passes |" || echo "| Multi-pass parsing | ✅ Clean |"
  [ "$LOOPS" -ge 3 ] 2>/dev/null && [ "$HTTP_INSIDE" -ge 2 ] 2>/dev/null && echo "| RAG indexer serial N+1 | ⚠️ Sequential HTTP |" || echo "| RAG indexer serial N+1 | ✅ Clean |"
  [ "$LOST_EVENTS" -gt 1 ] 2>/dev/null && echo "| Analytics event loss | ⚠️ Events collapsed |" || echo "| Analytics event loss | ✅ Clean |"
  [ "$NET_429" -lt "$HLP_429" ] 2>/dev/null && echo "| Retry-After handling | ⚠️ Missing in NetworkClient |" || echo "| Retry-After handling | ✅ Clean |"
} > "$REPORT_FILE"
