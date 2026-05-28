// backend/shared/promptGuard.js
// Лёгкий Prompt Guard для Yandex Cloud Functions (ai-advisor и др.).
// Цель: блокировать известные prompt-injection паттерны и cost-amplification
// атаки до вызова AI-провайдера (YandexGPT/GigaChat).
//
// API:
//   guardPrompt(prompt: string) -> { allowed: boolean, reason?: string }
//
// Внутри reason содержит технический id правила (для логов).
// Наружу (клиенту) reason раскрывать НЕ нужно — отдавать обобщённое сообщение.

export const MAX_PROMPT_LENGTH = 4000;

// Unicode tag block (U+E0000..U+E007F) — невидимые для человека символы,
// видимые модели. Классический ASCII-smuggling канал.
// eslint-disable-next-line no-misleading-character-class
const UNICODE_TAG_BLOCK = /[\u{E0000}-\u{E007F}]/u;

// Известные injection-паттерны (case-insensitive).
const INJECTION_PATTERNS = [
    { id: 'ignore_previous', re: /ignore\s+(?:all\s+)?(?:previous|above|prior|earlier)\s+(?:instructions?|prompts?|commands?|directives?)/i },
    { id: 'ignore_above', re: /ignore\s+(?:everything\s+)?above/i },
    { id: 'system_prompt_leak', re: /(?:reveal|show|print|repeat|output|tell\s+me)\s+(?:your\s+|the\s+)?system\s+prompt/i },
    { id: 'system_prompt_mention', re: /\bsystem\s+prompt\b/i },
    { id: 'chatml_im_start', re: /<\|im_start\|>/i },
    { id: 'chatml_im_end', re: /<\|im_end\|>/i },
    { id: 'gpt_endoftext', re: /<\|endoftext\|>/i },
    { id: 'llama_inst', re: /\[\/?INST\]/i },
    { id: 'llama_sys', re: /<<SYS>>|<<\/SYS>>/i },
    { id: 'unicode_tag_smuggling', re: UNICODE_TAG_BLOCK },
];

/**
 * Проверяет пользовательский prompt на инъекции и cost-amplification.
 *
 * @param {unknown} prompt
 * @returns {{ allowed: boolean, reason?: string }}
 */
export function guardPrompt(prompt) {
    if (typeof prompt !== 'string') {
        return { allowed: false, reason: 'type_not_string' };
    }

    const trimmed = prompt.trim();
    if (trimmed.length === 0) {
        return { allowed: false, reason: 'empty' };
    }

    if (prompt.length > MAX_PROMPT_LENGTH) {
        return { allowed: false, reason: 'length_exceeded' };
    }

    for (const { id, re } of INJECTION_PATTERNS) {
        if (re.test(prompt)) {
            return { allowed: false, reason: id };
        }
    }

    return { allowed: true };
}
