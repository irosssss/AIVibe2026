// backend/shared/secrets.js
// Управление секретами из Yandex Lockbox (Yandex Cloud)
// ESM — загружает REQUIRED_SECRETS один раз при старте функции.

const REQUIRED_SECRETS = {
    YANDEX_IAM_TOKEN: process.env.YANDEX_IAM_TOKEN,
    YANDEXGPT_FOLDER_ID: process.env.YANDEXGPT_FOLDER_ID,
    GIGACHAT_CLIENT_ID: process.env.GIGACHAT_CLIENT_ID,
    GIGACHAT_CLIENT_SECRET: process.env.GIGACHAT_CLIENT_SECRET,
    APP_TOKEN: process.env.APP_TOKEN,
    APIFY_API_TOKEN: process.env.APIFY_API_TOKEN,
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