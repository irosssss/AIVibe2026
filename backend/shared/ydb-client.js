// backend/shared/ydb-client.js
// Yandex Database клиент для работы с Document API
// Заглушка — заменяется на реальную YDB SDK при деплое

export const ydbClient = {
    async scan(tableName, opts = {}) {
        console.log(`[ydb] scan ${tableName} (limit: ${opts.limit ?? 'all'}) — stub`);
        return [];
    },
    async upsert(tableName, item) {
        console.log(`[ydb] upsert ${tableName} — stub:`, item?.id);
        return { ok: true };
    }
};

export { ydbClient };
