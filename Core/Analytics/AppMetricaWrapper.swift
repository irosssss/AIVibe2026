// Core/Analytics
// Модуль: Core
// Singleton-обёртка над Yandex AppMetrica. Единственный разрешённый Singleton.

import Foundation

/// Обёртка над AppMetrica для отправки аналитики.
@MainActor
public final class AppMetricaWrapper {
    
    /// Единственный экземпляр обёртки.
    public static let shared = AppMetricaWrapper()
    
    /// Флаг инициализации SDK.
    private var isActivated = false
    
    /// Частичные ключи для отслеживания в AppMetrica.
    private var customKey: String?
    
    private init() {
        // SDK инициализируется через активацию в приложении.
    }
    
    /// Активирует SDK AppMetrica.
    /// Вызывается один раз при запуске приложения.
    public func activate() {
        #if DEBUG
        // В режиме отладки не отправляем данные.
        isActivated = true
        return
        #endif
        
        // TODO: Вызвать AppMetrica.activate(config: ...)
        // Активация будет реализована при подключении бинарного SDK.
        isActivated = true
    }
    
    /// Отправляет событие в AppMetrica.
    /// - Parameters:
    ///   - eventName: Имя события.
    ///   - parameters: Словарь параметров события.
    public func reportEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        guard isActivated else { return }
        
        // TODO: Вызвать AppMetrica.reportEvent(eventName:parameters:)
        #if DEBUG
        #endif
    }
    
    /// Отправляет ошибку в AppMetrica.
    /// - Parameters:
    ///   - error: Ошибка для отслеживания.
    ///   - context: Дополнительный контекст ошибки.
    public func reportError(_ error: Error, context: [String: Any]? = nil) {
        guard isActivated else { return }
        
        // TODO: Вызвать AppMetrica.reportError(error, context)
        #if DEBUG
        #endif
    }
    
    /// Устанавливает ключ пользователя для персонализации.
    /// - Parameter key: Пользовательский ключ.
    public func setCustomKey(_ key: String?) {
        self.customKey = key
        
        // TODO: Вызвать AppMetrica.setCustomKey(customKey:)
    }
}
