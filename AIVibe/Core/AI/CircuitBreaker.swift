// AIVibe/Core/AI/CircuitBreaker.swift
// Модуль: Core/AI
// Circuit Breaker паттерн для AI-провайдеров.
// Если провайдер падает failureThreshold раз подряд — отключается на cooldownDuration.

import Foundation
import Logging

// MARK: - Circuit Breaker State

/// Состояние Circuit Breaker для одного провайдера.
private struct BreakerState: Sendable {
    enum Status: Sendable {
        case closed              // Всё работает
        case open(until: Date)   // Провайдер отключён до указанного времени
        case halfOpen            // Пробуем один запрос для проверки
    }

    var status: Status = .closed
    var failureCount: Int = 0
    var lastFailureAt: Date?
}

// MARK: - CircuitBreaker

/// Thread-safe Circuit Breaker для пула AI-провайдеров.
/// Использует actor для изоляции состоян��я.
public actor CircuitBreaker {

    // MARK: - Конфигурация

    public struct Configuration: Sendable {
        /// Сколько подряд провалов открывают прерыватель
        let failureThreshold: Int
        /// Сколько секунд провайдер «отдыхает» после открытия
        let cooldownDuration: TimeInterval
        /// Через сколько секунд переходим из open → halfOpen для проверки
        let halfOpenTimeout: TimeInterval

        public init(
            failureThreshold: Int    = 3,
            cooldownDuration: TimeInterval  = 300, // 5 минут
            halfOpenTimeout: TimeInterval   = 60   // 1 минута
        ) {
            self.failureThreshold = failureThreshold
            self.cooldownDuration = cooldownDuration
            self.halfOpenTimeout  = halfOpenTimeout
        }
    }

    // MARK: - Properties

    private var states: [String: BreakerState] = [:]
    private let config: Configuration
    private let logger = Logger(label: "ai.circuit-breaker")

    // MARK: - Init

    public init(config: Configuration = .init()) {
        self.config = config
    }

    // MARK: - Public API

    /// Проверяет разрешён ли запрос к провайдеру.
    /// - Returns: `true` — можно делать запрос; `false` — Circuit Breaker открыт.
    public func isAllowed(provider: String) -> Bool {
        let state = states[provider] ?? BreakerState()

        switch state.status {
        case .closed:
            return true
        case .halfOpen:
            return true
        case .open(let until):
            if Date() > until {
                // Переходим в halfOpen — пробуем один запрос
                states[provider]?.status = .halfOpen
                logger.info("⚡ \(provider): Circuit Breaker → halfOpen")
                return true
            }
            let remaining = until.timeIntervalSinceNow
            logger.debug("🔴 \(provider): Circuit Breaker открыт ещё \(Int(remaining))с")
            return false
        }
    }

    /// Записывает успешный запрос — сбрасывает счётчик провалов.
    public func recordSuccess(provider: String) {
        guard states[provider] != nil else { return }
        states[provider] = BreakerState() // Полный сброс
        logger.info("✅ \(provider): Circuit Breaker сброшен (success)")
    }

    /// Записывает провал — увеличивает счётчик, при достижении порога — открывает прерыватель.
    public func recordFailure(provider: String) {
        var state = states[provider] ?? BreakerState()
        state.failureCount  += 1
        state.lastFailureAt  = Date()

        if state.failureCount >= config.failureThreshold {
            let reopenAt = Date().addingTimeInterval(config.cooldownDuration)
            state.status = .open(until: reopenAt)
            logger.warning(
                "🔴 \(provider): Circuit Breaker ОТКРЫТ на \(Int(config.cooldownDuration))с " +
                "(провалов подряд: \(state.failureCount))"
            )
        } else {
            logger.warning(
                "⚠️ \(provider): провал \(state.failureCount)/\(config.failureThreshold)"
            )
        }

        states[provider] = state
    }

    /// Оставшееся время cooldown для провайдера (0 если closed/halfOpen).
    public func cooldownRemaining(provider: String) -> TimeInterval {
        guard case .open(let until) = states[provider]?.status else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    /// Принудительно сбрасывает состояние провайдера (для тестов и ручного управления).
    public func reset(provider: String) {
        states[provider] = BreakerState()
        logger.info("🔄 \(provider): Circuit Breaker сброшен вручную")
    }
}
