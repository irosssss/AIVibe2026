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

    // ── Русскоязычные паттерны (целевой рынок — РФ) ──────────────────────────
    // Англоязычные правила выше не ловят атаки на русском. Каждое правило ниже
    // требует И глагол-действие, И мишень (инструкции / промпт / ключ / роль),
    // чтобы НЕ блокировать обычные дизайн-запросы: «игнорируй старый диван»,
    // «бюджет без ограничений», «секретер» (мебель), «ключевой элемент».
    // \w в JS не покрывает кириллицу — используем явные классы [а-яё] + флаг /i.
    { id: 'ru_ignore_instructions', re: /(?:игнорир[а-яё]*|проигнорир[а-яё]*|забудь|забуд[а-яё]+|не\s+обращай\s+внимани[а-яё]+\s+на)\s+(?:[а-яё]+\s+){0,3}(?:инструкци|указани|команд|директив|промпт|предписани)[а-яё]*/i },
    { id: 'ru_forget_above', re: /(?:игнорир[а-яё]*|забудь|забуд[а-яё]+)\s+(?:вс[её]\s+)?(?:,?\s*что\s+)?(?:написан[а-яё]+\s+|сказан[а-яё]+\s+|был[а-яё]+\s+)?(?:выше|ранее|до\s+этого|вначале)/i },
    { id: 'ru_system_prompt_leak', re: /(?:покажи|раскрой|выведи|повтори|процитируй|назови|распечатай|напиши)\s+(?:мне\s+)?(?:сво[иейя][а-яё]*|тво[иейя][а-яё]*|ваш[а-яё]*|весь|полн[а-яё]+|исходн[а-яё]+|первоначальн[а-яё]+)\s+(?:систем[а-яё]+\s+)?(?:промпт|инструкци|настройк|директив)[а-яё]*/i },
    { id: 'ru_system_prompt_mention', re: /систем[а-яё]+\s+промпт[а-яё]*/i },
    { id: 'ru_role_abuse', re: /(?:ты\s+(?:теперь|отныне|больше\s+не)|веди\s+себя\s+как|представь[,\s]+что\s+ты|притворись[,\s]+что\s+ты|с\s+этого\s+момента\s+ты)\s+(?:[а-яё]+\s+){0,2}(?:администратор|админ|root|рут|разработчик|суперпользовател|хозяин|владелец)[а-яё]*/i },
    { id: 'ru_disable_filters', re: /(?:отключи|обойди|сними|убери|выключи|деактивируй|игнорир[а-яё]*)\s+(?:[а-яё]+\s+){0,2}(?:фильтр|цензур|ограничени|защит|модерац|безопасн)[а-яё]*/i },
    { id: 'ru_dev_mode', re: /режим[а-яё]*\s+(?:разработчик|без\s+цензур|без\s+ограничени|бога|dan)[а-яё]*/i },
    { id: 'ru_no_censorship', re: /без\s+(?:цензур|фильтр)[а-яё]*/i },
    { id: 'ru_key_theft', re: /(?:покажи|выведи|раскрой|дай|назови|распечатай|сообщи|пришли)\s+(?:мне\s+)?(?:[а-яё]+\s+){0,2}(?:api[\s-]?ключ|ключ\s+(?:api|доступа|шифровани)|токен|пароль|секрет(?!ер)|переменн[а-яё]+\s+окружени)[а-яё]*/i },
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
