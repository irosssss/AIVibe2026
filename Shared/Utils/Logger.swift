// Shared/Utils
// Модуль: Shared
// Глобальный логгер на основе swift-log.

import Foundation
import Logging

/// Глобальный логгер проекта AIVibe.
/// Использует apple/swift-log как рекомендовано в правилах.
public enum AIVibeLogger {
    
    /// Основной логгер приложения.
    public static let main: Logger = {
        var logger = Logger(label: "ru.aivibe.app")
        logger.logLevel = ProcessInfo.isDebug ? .debug : .info
        return logger
    }()
    
    /// Логгер для сетевого слоя.
    public static let network: Logger = {
        var logger = Logger(label: "ru.aivibe.app.network")
        logger.logLevel = ProcessInfo.isDebug ? .debug : .info
        return logger
    }()
    
    /// Логгер для AI-провайдеров.
    public static let ai: Logger = {
        var logger = Logger(label: "ru.aivibe.app.ai")
        logger.logLevel = ProcessInfo.isDebug ? .debug : .info
        return logger
    }()
    
    /// Логгер для хранения данных.
    public static let storage: Logger = {
        var logger = Logger(label: "ru.aivibe.app.storage")
        logger.logLevel = ProcessInfo.isDebug ? .debug : .info
        return logger
    }()
    
    /// Логгер для аналитики.
    public static let analytics: Logger = {
        var logger = Logger(label: "ru.aivibe.app.analytics")
        logger.logLevel = ProcessInfo.isDebug ? .debug : .info
        return logger
    }()
}

extension ProcessInfo {
    /// Флаг отладочного режима.
    public static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
