// backend/shared/secrets.js
// Управление секретами из Yandex Lockbox (Yandex Cloud)
// ESM — загружает REQUIRED_SECRETS один раз при старте функции.

// NB: YANDEX_IAM_TOKEN намеренно НЕ здесь — IAM-токен берётся из metadata service
// через getIamToken() (yandexgpt.js), а process.env.YANDEX_IAM_TOKEN используется
// им только как локальный fallback. Держать его в REQUIRED_SECRETS = ложное
// предупреждение "missing" в проде, где токен и не должен быть задан.
const REQUIRED_SECRETS = {
    YANDEXGPT_FOLDER_ID: process.env.YANDEXGPT_FOLDER_ID,
    GIGACHAT_CLIENT_ID: process.env.GIGACHAT_CLIENT_ID,
    GIGACHAT_CLIENT_SECRET: process.env.GIGACHAT_CLIENT_SECRET,
    APP_TOKEN: process.env.APP_TOKEN,
    APIFY_API_TOKEN: process.env.APIFY_API_TOKEN,
    YDB_DOCUMENT_API_ENDPOINT: process.env.YDB_DOCUMENT_API_ENDPOINT,
    YDB_DATABASE: process.env.YDB_DATABASE,
};

/**
 * Загружает все секреты.
 * В Yandex Cloud Function секреты автоматически injected через Lockbox.
 * В локальной разработке — через .env или process.env.
 */
export async function getSecrets() {
    const missing = Object.entries(REQUIRED_SECRETS)
        .filter(([, value]) => !value)
        .map(([key]) => key);

    if (missing.length > 0) {
        console.warn('[secrets] Missing environment variables:', missing.join(', '));
    }

    return REQUIRED_SECRETS;
}

export { REQUIRED_SECRETS };