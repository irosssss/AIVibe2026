param([switch]$Apply)

# Detect project root (the git repo root)
$ScriptDir = Split-Path -Parent $PSCommandPath
$Root = Split-Path -Parent $ScriptDir

$ReportFile = Join-Path $Root "complexity-report.md"

Write-Host "`nAIVibe Code Complexity Analyzer" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host "Root: $Root"
if ($Apply) { Write-Host "Mode: apply optimizations" } else { Write-Host "Mode: report only" }
Write-Host ""

function Count-Lines($f) {
    if (Test-Path $f) { (Get-Content $f | Measure-Object -Line).Lines } else { 0 }
}
function Count-Matches($f, $p) {
    if (Test-Path $f) { (Select-String -Path $f -Pattern $p -SimpleMatch).Count } else { 0 }
}

# 1 - Circuit Breaker duplication
Write-Host "[1] Circuit Breaker duplication..."
$cbSwift = Count-Matches (Join-Path $Root "AIVibe/Core/AI/CircuitBreaker.swift") "threshold"
$cbJs   = Count-Matches (Join-Path $Root "backend/index.js") "threshold"
Write-Host "    Swift=$cbSwift  JS=$cbJs"
if ($cbSwift -gt 0 -and $cbJs -gt 0) { Write-Host "    [WARN] Duplicate CB" -ForegroundColor Yellow }

# 2 - Multi-pass parsing
Write-Host "[2] Multi-pass parsing..."
$advice = Join-Path $Root "AIVibe/Features/DesignAdvice/DesignAdvice.swift"
$fiCount = Count-Matches $advice "firstIndex"
Write-Host "    firstIndex x $fiCount"
if ($fiCount -gt 3) { Write-Host "    [WARN] Multi-pass" -ForegroundColor Yellow }

# 3 - Dual backend
Write-Host "[3] Backend entry points..."
$mainJs = Join-Path $Root "backend/index.js"
$advJs  = Join-Path $Root "backend/functions/ai-advisor/index.js"
$mainL = Count-Lines $mainJs
$advL  = Count-Lines $advJs
Write-Host "    main=$mainL lines  advisor=$advL lines"
if ($mainL -gt 0 -and $advL -gt 0) { Write-Host "    [WARN] Dual entry points" -ForegroundColor Yellow }

# 4 - RAG indexer N+1
Write-Host "[4] RAG indexer serial N+1..."
$ragIdx = Join-Path $Root "backend/functions/rag-indexer/index.js"
$fc = 0; $ac = 0
if (Test-Path $ragIdx) {
    $txt = Get-Content $ragIdx -Raw
    $fc = ([regex]::Matches($txt, 'for\s*\(')).Count
    $ac = ([regex]::Matches($txt, 'await')).Count
}
Write-Host "    loops=$fc  awaits=$ac"
if ($fc -ge 3 -and $ac -ge 2) { Write-Host "    [WARN] Serial N+1 HTTP" -ForegroundColor Yellow }

# 5 - RAG search scan
Write-Host "[5] RAG search scan..."
$ragSrch = Join-Path $Root "backend/functions/rag-search/index.js"
$scan = 0
if (Test-Path $ragSrch) {
    $m = Select-String -Path $ragSrch -Pattern 'limit:\s*(\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }
    if ($m) { $scan = [int]$m }
}
Write-Host "    limit=$scan"
if ($scan -gt 100) { Write-Host "    [WARN] Full scan" -ForegroundColor Yellow }

# 6 - Analytics loss
Write-Host "[6] Analytics events..."
$analytics = Join-Path $Root "AIVibe/Core/Analytics/AppMetricaAnalytics.swift"
$aiSent = Count-Matches $analytics "aiRequestSent"
Write-Host "    aiRequestSent refs=$aiSent"
if ($aiSent -gt 1) { Write-Host "    [WARN] Event loss" -ForegroundColor Yellow }

# 7 - HTTP status handling
Write-Host "[7] HTTP status handling..."
$net = Join-Path $Root "AIVibe/Core/Network/NetworkClient.swift"
$hlp = Join-Path $Root "AIVibe/Core/AI/AIProviderHelpers.swift"
$n429 = Count-Matches $net "Retry-After"
$h429 = Count-Matches $hlp "Retry-After"
Write-Host "    Network=$n429  Helpers=$h429"
if ($n429 -eq 0 -and $h429 -gt 0) { Write-Host "    [WARN] NetworkClient missing Retry-After" -ForegroundColor Yellow }

# 8 - Largest files
Write-Host "[8] Largest files..."
Get-ChildItem -Path $Root -Recurse -Include *.swift,*.js |
    Where-Object { $_.FullName -notmatch 'node_modules|\.build|Godeps|vendor' } |
    Sort-Object Length -Descending |
    Select-Object -First 8 |
    ForEach-Object { Write-Host ("    {0,6:F1} KB  {1}" -f ($_.Length/1KB), $_.Name) }

# Generate report
$lines = @(
    "# Code Complexity Report",
    "Generated: $(Get-Date -Format 'o')",
    "",
    "## Summary",
    "",
    "| Check | Status |",
    "|---|---|"
)
if ($cbSwift -gt 0 -and $cbJs -gt 0)   { $lines += "| Circuit Breaker duplication | WARN |" }
else                                    { $lines += "| Circuit Breaker duplication | OK |" }
if ($fiCount -gt 3)                     { $lines += "| Multi-pass parsing | WARN |" }
else                                    { $lines += "| Multi-pass parsing | OK |" }
if ($fc -ge 3 -and $ac -ge 2)          { $lines += "| RAG indexer N+1 | WARN |" }
else                                    { $lines += "| RAG indexer N+1 | OK |" }
if ($scan -gt 100)                      { $lines += "| RAG search full scan | WARN |" }
else                                    { $lines += "| RAG search full scan | OK |" }
if ($aiSent -gt 1)                      { $lines += "| Analytics event loss | WARN |" }
else                                    { $lines += "| Analytics event loss | OK |" }
if ($n429 -eq 0 -and $h429 -gt 0)      { $lines += "| Retry-After handling | WARN |" }
else                                    { $lines += "| Retry-After handling | OK |" }

Set-Content -Path $ReportFile -Value ($lines -join "`r`n")

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Done! Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "Run with -Apply to auto-fix safe optimizations." -ForegroundColor Gray
Write-Host "=================================" -ForegroundColor Cyan
