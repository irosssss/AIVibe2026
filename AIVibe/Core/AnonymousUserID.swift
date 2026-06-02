// AIVibe/Core/AnonymousUserID.swift
// Анонимный стабильный идентификатор устройства/установки (без Auth).
//
// Нужен, чтобы backend складывал запросы в корректное rate-limit-ведро (#17/L4):
// до появления Sign-in захардкоженный 'current_user_id' означал бы один общий
// бакет на всех пользователей (cross-user DoS). Генерим UUID при первом запуске
// и переиспользуем из UserDefaults. Формат подходит под backend-регэксп
// userId: /^[a-zA-Z0-9_.-]+$/.

import Foundation

public enum AnonymousUserID {
    private static let storageKey = "aivibe.anonymousUserId.v1"

    /// Стабильный per-install идентификатор. Создаётся лениво при первом доступе.
    public static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }
}
