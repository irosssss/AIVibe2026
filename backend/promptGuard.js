/**
 * Prompt Guard — детектор промпт-инъекций для AIVibe Backend
 *
 * 3 уровня защиты:
 * 1. Regex-правила        — известные паттерны атак
 * 2. Эвристики            — длина, base64, escape, обфускация
 * 3. Скоринг (severity)   — 1..5, определяет реакцию системы
 *
 * Severity:
 *   5 — Критично (кража ключей, явный jailbreak) → block_immediate
 *   4 — Высоко   (system leak, role abuse)        → block_immediate
 *   3 — Средне   (harmful, exfiltration)          → strike (3 strikes = 24h ban)
 *   2 — Низко    (markup, обфускация)             → log only
 *   1 — Инфо     (длина, форматирование)          → log only
 *   0 — Чисто
 */

'use strict';

// ============================================================================
// 1. Regex-правила (severity-based)
// ============================================================================
const INJECTION_RULES = [
  // ── Severity 5 — Критичные (мгновенный бан) ──────────────────────────────
  {
    id: 'api_key_theft',
    severity: 5,
    name: 'API Key / Secret Theft',
    patterns: [
      /(?:output|print|show|give|send|reveal|dump|list).*?(?:api[_\s-]?key|apikey|token|secret|credential|password|iam[_\s-]?token|client[_\s-]?secret|env(?:ironment)?[_\s]?(?:var|variable)|private[_\s-]?key)/i,
      /(?:export|echo|console\.log|print)\s*\(?\s*['"]?(?:token|secret|key|password)/i,
      /process\.env\s*\[?\s*['"]/i,
      /Authorization:\s*Bearer\s+[a-zA-Z0-9_-]+/i,
      /sk-[a-zA-Z0-9]{20,}/i, // OpenAI-like key pattern
      /AQVN[a-zA-Z0-9+/=]{10,}/i, // Yandex IAM-like
    ],
  },
  {
    id: 'system_prompt_leak',
    severity: 5,
    name: 'System Prompt Extraction',
    patterns: [
      /ignore\s+(?:all\s+)?(?:previous|above|prior|earlier)\s+(?:instructions?|commands?|prompt|directive)/i,
      /ignore\s+(?:your\s+)?(?:system\s+)?(?:instructions?|prompt)/i,
      /(?:repeate?d?\s+(?:word|text|previous|back)|repeat\s+after\s+me):\s*["']?[^"']{3,}["']?/i,
      /read\s+(?:back|aloud|out)\s+(?:your\s+)?(?:system\s+)?(?:prompt|instructions|directive)/i,
      /tell\s+me\s+(?:your|the)\s+(?:system\s+)?(?:instructions?|prompt|directive|context)/i,
      /what\s+(?:are|were)\s+(?:your|the)\s+(?:system\s+)?(?:instructions?|prompt|directive)/i,
      /above\s+is\s+the\s+instruction/i,
      /end\s+(?:of|previous)\s+(?:instruction|prompt)/i,
      /\{system\}/i,
      /new\s+(?:system\s+)?instruction:\s*[\s\S]{10,}/i,
    ],
  },
  {
    id: 'jailbreak_known',
    severity: 5,
    name: 'Known Jailbreak Pattern',
    patterns: [
      /\bDAN\b.*(?:do\s+anything\s+now|jailbreak|mode|unfiltered)/i,
      /(?:you\s+are\s+now|enter|switch\s+to|activate)\s+(?:DAN|developer|admin|root|god|unrestricted)\s*mode/i,
      /(?:ignore|bypass|disable|turn\s+off)\s+(?:safety|filter|restriction|guideline|policy|guardrail)/i,
      /(?:ethical|safety)\s+(?:hacker|hacking)/i,
      /(?:simulate|pretend|roleplay|act\s+as)\s+(?:an?\s+)?(?:unethical|unrestricted|immoral|dangerous|evil|sinister)/i,
      /(?:no\s+limits|without\s+restriction|unfiltered\s+mode)/i,
    ],
  },

  // ── Severity 4 — Высокие ─────────────────────────────────────────────────
  {
    id: 'role_abuse',
    severity: 4,
    name: 'Role Abuse / Privilege Escalation',
    patterns: [
      /(?:you\s+are\s+now|you\s+are\s+an?\s+|act\s+as\s+an?\s+|pretend\s+to\s+be)\s+(?:an?\s+)?(?:admin|administrator|root|owner|system|superuser)/i,
      /(?:reset|change|bypass|disable|remove)\s+(?:password|auth|authentication|login|credential|2fa|mfa)/i,
      /(?:delete|drop|remove)\s+(?:all|database|table|user|account|data|record)/i,
      /(?:grant|give\s+me|provide)\s+(?:admin|root|full|all|elevated)\s+(?:access|permission|right|role)/i,
      /impersonate\s+(?:admin|user|system)/i,
    ],
  },
  {
    id: 'backend_discovery',
    severity: 4,
    name: 'Backend / Infrastructure Discovery',
    patterns: [
      /(?:what\s+is|show\s+me|reveal|print|dump)\s+(?:your\s+)?(?:backend|server|base\s*url|endpoint|host|ip|port|infra|architecture)/i,
      /(?:what\s+headers|how\s+do\s+you\s+call|what\s+is\s+your)\s+(?:internal|backend|api|upstream)/i,
      /(?:curl|wget|fetch|axios|http\.get|urllib)\s+.*?(?:localhost|127\.0\.0\.1|0\.0\.0\.0|::1)/i,
      /(?:list|show|cat|ls|dir)\s+(?:files?|directory|folder|env|config|\.env|package\.json)/i,
      /(?:exec|spawn|child_process|eval|Function)\s*\(/i,
    ],
  },

  // ── Severity 3 — Средние (strike) ────────────────────────────────────────
  {
    id: 'harmful_generation',
    severity: 3,
    name: 'Harmful Content Generation',
    patterns: [
      /(?:write|create|generate|build|code)\s+(?:a?\s+)?(?:script|code|program|query|tool)\s+(?:to\s+)?(?:steal|hack|exploit|phish|inject|bypass|crack|dump|scrape|attack)/i,
      /(?:sql\s+injection|xss|csrf|ssrf|xxe|path\s+traversal|directory\s+traversal|remote\s+code|command\s+injection|ldap\s+injection|nosql\s+injection)/i,
      /(?:how\s+to|steps\s+to|guide\s+for|tutorial\s+on)\s+(?:steal|hack|crack|phish|exploit|spoof|impersonate|forge)/i,
      /(?:malware|ransomware|trojan|keylogger|rootkit|spyware|botnet|backdoor)/i,
      /(?:create\s+(?:a?\s+)?(?:virus|worm))/i,
    ],
  },
  {
    id: 'data_exfiltration',
    severity: 3,
    name: 'Data Exfiltration / Callback',
    patterns: [
      /(?:send|post|exfiltrate|leak|transmit|forward|redirect)\s+(?:data|info|result|output|response|log)\s+(?:to|at|into)/i,
      /https?:\/\/[^\s]+(?:webhook|callback|pastebin|requestbin|ngrok|hook\.site)/i,
      /(?:base64|hex|rot13|url\s*encode|escape)\s*(?:encode\s*)?(?:the\s+)?(?:output|result|response|text)/i,
      /(?:pipedream|webhook\.site|requestbin\.com|ngrok\.io)/i,
    ],
  },
  {
    id: 'obfuscation',
    severity: 3,
    name: 'Obfuscated / Encoded Payload',
    patterns: [
      /[\x00-\x08\x0b\x0c\x0e-\x1f]/,                    // Control characters (C0)
      /\\x[0-9a-fA-F]{2}/,                                  // Hex escapes \x41
      /\\u[0-9a-fA-F]{4}/,                                  // Unicode escapes \u0041
      /Base64[:\s]+[A-Za-z0-9+/]{40,}={0,2}/i,              // Marked base64 block
      /`[^`]{200,}`/,                                       // Huge template literal
    ],
  },

  // ── Severity 2 — Низкие (лог) ────────────────────────────────────────────
  {
    id: 'markup_injection',
    severity: 2,
    name: 'Markup / Template Injection',
    patterns: [
      /<script\b[^>]*>/i,
      /<iframe\b[^>]*>/i,
      /\{\{\s*.*?\s*\}\}/,                                 // Handlebars, Jinja2-like
      /\{%\s*.*?\s*%\}/,                                    // Django/Jinja
      /\$\{\s*.*?\s*\}/,                                    // JS template literal injection
      /javascript:/i,
      /on\w+\s*=\s*["']?[^"'>\s]+/i,                        // Event handlers
    ],
  },

  // ── Severity 1 — Информационные (лог) ────────────────────────────────────
  {
    id: 'excessive_formatting',
    severity: 1,
    name: 'Excessive Formatting',
    patterns: [
      /([*\-_\|])\1{9,}/,                                   // Repeated special chars
      /\n{15,}/,                                            // Excessive newlines
      /\x1b\[[0-9;]*m/,                                     // ANSI escape codes
    ],
  },
];


// ============================================================================
// 2. Эвристические проверки
// ============================================================================
function runHeuristics(prompt) {
  const findings = [];
  const len = prompt.length;

  // ── Длина ────────────────────────────────────────────────────────────────
  if (len > 6000) {
    findings.push({
      severity: 3,
      reason: `Prompt length ${len} exceeds 6000 chars (possible DoS / hidden payload)`,
      id: 'heur_length_critical',
    });
  } else if (len > 4000) {
    findings.push({
      severity: 2,
      reason: `Prompt length ${len} exceeds 4000 chars`,
      id: 'heur_length_high',
    });
  } else if (len > 2500) {
    findings.push({
      severity: 1,
      reason: `Prompt length ${len} exceeds 2500 chars`,
      id: 'heur_length_warn',
    });
  }

  // ── Новые строки ─────────────────────────────────────────────────────────
  const newlineCount = (prompt.match(/\n/g) || []).length;
  if (newlineCount > 30) {
    findings.push({
      severity: 2,
      reason: `Excessive newlines (${newlineCount}) — possible system prompt separator`,
      id: 'heur_newlines',
    });
  }

  // ── Base64-кандидаты ─────────────────────────────────────────────────────
  const base64Candidates = prompt.match(/[A-Za-z0-9+/]{40,}={0,2}/g);
  if (base64Candidates) {
    // Проверяем, что это действительно похоже на base64 (длина кратна 4)
    const validBase64 = base64Candidates.filter((s) => s.length % 4 === 0 && s.length >= 44);
    if (validBase64.length > 0) {
      findings.push({
        severity: 3,
        reason: `Potential base64 obfuscation (${validBase64.length} segments)`,
        id: 'heur_base64',
      });
    }
  }

  // ── Null bytes ───────────────────────────────────────────────────────────
  if (prompt.includes('\x00')) {
    findings.push({
      severity: 3,
      reason: 'Null bytes detected — possible C-string terminator abuse',
      id: 'heur_nullbytes',
    });
  }

  // ── Обфускация (соотношение спец-символов) ───────────────────────────────
  const nonAlphanumeric = prompt.replace(/[\s\wа-яА-ЯёЁ]/g, '').length;
  const ratio = len > 0 ? nonAlphanumeric / len : 0;
  if (ratio > 0.6 && len > 80) {
    findings.push({
      severity: 2,
      reason: `High special-character ratio (${(ratio * 100).toFixed(1)}%) — possible obfuscation`,
      id: 'heur_obfuscation',
    });
  }

  // ── Token flooding (повторы слов) ────────────────────────────────────────
  const words = prompt.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length > 60) {
    const uniqueWords = new Set(words);
    const uniqueness = uniqueWords.size / words.length;
    if (uniqueness < 0.25) {
      findings.push({
        severity: 2,
        reason: 'Repetitive word pattern (token flooding / buffer overflow attempt)',
        id: 'heur_repetition',
      });
    }
  }

  // ─— Unicode homoglyphs / visual spoofing ─────────────────────────────────
  const homoglyphPattern = /[ΑΒΕΖΗΙΚΜΝΟΡΤΧ]|[𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗]/u; // Greek-like, mathematical digits
  if (homoglyphPattern.test(prompt)) {
    findings.push({
      severity: 2,
      reason: 'Unicode homoglyph characters detected — possible visual spoofing',
      id: 'heur_homoglyphs',
    });
  }

  return findings;
}


// ============================================================================
// 3. Основной анализ
// ============================================================================
function analyze(prompt) {
  if (typeof prompt !== 'string') {
    return {
      safe: false,
      severity: 5,
      reason: 'Prompt must be a string',
      rule: 'type_check',
      id: 'type_check',
      action: 'block_immediate',
    };
  }

  const trimmed = prompt.trim();
  if (!trimmed) {
    return {
      safe: false,
      severity: 1,
      reason: 'Empty prompt',
      rule: 'empty_check',
      id: 'empty_check',
      action: 'log',
    };
  }

  let maxSeverity = 0;
  const reasons = [];
  const ruleIds = [];
  const triggeredRules = [];

  // ── Правила regex ────────────────────────────────────────────────────────
  for (const rule of INJECTION_RULES) {
    let matched = false;
    for (const pattern of rule.patterns) {
      if (pattern.test(trimmed)) {
        matched = true;
        break;
      }
    }
    if (matched) {
      if (rule.severity > maxSeverity) {
        maxSeverity = rule.severity;
      }
      reasons.push(rule.name);
      ruleIds.push(rule.id);
      triggeredRules.push({ id: rule.id, name: rule.name, severity: rule.severity });
    }
  }

  // ── Эвристики ────────────────────────────────────────────────────────────
  const heuristicFindings = runHeuristics(trimmed);
  for (const finding of heuristicFindings) {
    if (finding.severity > maxSeverity) {
      maxSeverity = finding.severity;
    }
    reasons.push(finding.reason);
    ruleIds.push(finding.id);
    triggeredRules.push({ id: finding.id, name: finding.reason, severity: finding.severity, heuristic: true });
  }

  // ── Принятие решения ─────────────────────────────────────────────────────
  if (maxSeverity >= 4) {
    return {
      safe: false,
      severity: maxSeverity,
      reason: `[BLOCKED] ${reasons.join('; ')}`,
      rule: ruleIds.join(', '),
      id: ruleIds[0] || 'heuristic',
      action: 'block_immediate',
      details: triggeredRules,
    };
  }

  if (maxSeverity === 3) {
    return {
      safe: false,
      severity: 3,
      reason: `[STRIKE] ${reasons.join('; ')}`,
      rule: ruleIds.join(', '),
      id: ruleIds[0] || 'heuristic',
      action: 'strike',
      details: triggeredRules,
    };
  }

  if (maxSeverity >= 1) {
    return {
      safe: true,
      severity: maxSeverity,
      reason: `[WARN] ${reasons.join('; ')}`,
      rule: ruleIds.join(', '),
      id: ruleIds[0] || 'heuristic',
      action: 'log',
      details: triggeredRules,
    };
  }

  return {
    safe: true,
    severity: 0,
    reason: 'Clean',
    rule: null,
    id: 'clean',
    action: 'allow',
    details: [],
  };
}

// ============================================================================
// 4. Вспомогательные функции
// ============================================================================

/**
 * Является ли результат strike (засчитывается в счётчик перед баном)?
 */
function isStrike(result) {
  return result.severity === 3;
}

/**
 * Требует ли результат немедленной блокировки?
 */
function isImmediateBlock(result) {
  return result.severity >= 4;
}

/**
 * Требует ли результат хотя бы логирования?
 */
function isSuspicious(result) {
  return result.severity >= 1;
}

/**
 * Возвращает human-readable summary для логов
 */
function formatResult(result, userId) {
  const timestamp = new Date().toISOString();
  const safeStr = result.safe ? 'SAFE' : 'UNSAFE';
  return {
    ts: timestamp,
    userId: userId || 'unknown',
    verdict: safeStr,
    severity: result.severity,
    action: result.action,
    rule: result.rule,
    reason: result.reason,
  };
}

module.exports = {
  analyze,
  isStrike,
  isImmediateBlock,
  isSuspicious,
  formatResult,
  INJECTION_RULES,
};
