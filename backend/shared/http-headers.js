// backend/shared/http-headers.js
// Регистронезависимое чтение HTTP-заголовков события Cloud Function.
//
// Yandex Cloud приводит имена заголовков к каноническому виду (X-App-Token),
// клиенты могут слать в любом регистре — прямой доступ по фиксированной строке
// ловит не все варианты (вскрылось на первом реальном деплое: 403 при верном токене).

/**
 * @param {object} event — событие Cloud Function (event.headers)
 * @param {string} name — имя заголовка в любом регистре
 * @returns {string|undefined}
 */
export function getHeader(event, name) {
    const headers = event?.headers;
    if (!headers || typeof headers !== 'object') return undefined;
    if (headers[name] !== undefined) return headers[name];
    const lower = String(name).toLowerCase();
    for (const [key, value] of Object.entries(headers)) {
        if (key.toLowerCase() === lower) return value;
    }
    return undefined;
}
