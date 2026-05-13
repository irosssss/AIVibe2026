// AIVibe/Core/AI/CircuitBreaker.swift
// Модуль: Core/AI
// Circuit Breaker паттерн для AI-провайдеров.
// Один экземпляр = один провайдер.
// Если провайдер падает threshold раз подряд — отключается на timeout секунд.

import Foundation
import Logging

// MARK: - CircuitBreaker

/// Thread-safe Circuit Breaker для одного AI-провайдера.
/// Хранит одно состояние: closed → open(until) → halfOpen → closed.
public actor CircuitBreaker {

    // MARK: - State

    /// Состояние Circuit Breaker.
    public enum State: Sendable {
        /// Всё исправно, запросы разрешены.
        case closed
        /// Провайдер отключён до указанного времени.
        case open(until: Date)
        /// Пробный запрос для проверки после cooldown.
        case halfOpen
    }

    // MARK: - Properties

    private var state: State = .closed
    private var failureCount: Int = 0
    private let threshold: Int
    private let timeout: TimeInterval
    private let logger = Logger(label: "ai.circuit-breaker")

    // MARK: - Init

    public init(
        threshold: Int = 3,
        timeout: TimeInterval = 300 // 5 минут
    ) {
        self.threshold = threshold
        self.timeout = timeout
    }

    // MARK: - Public API

    /// Проверяет разрешён ли запрос.
    /// - Returns: `true` — можно делать запрос; `false` — Circuit Breaker открыт.
    public func canRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .halfOpen:
            return true
        case .open(let until):
            if Date() > until {
                // Переходим в halfOpen — пробуем один запрос
                state = .halfOpen
                logger.info("⚡ Circuit Breaker → halfOpen")
                return true
            }
            let remaining = until.timeIntervalSinceNow
            logger.debug("🔴 Circuit Breaker открыт ещё \(Int(remaining))с")
            return false
        }
    }

    /// Записывает успешный запрос — сбрасывает счётчик провалов.
    public func recordSuccess() {
        state = .closed
        failureCount = 0
        logger.info("✅ Circuit Breaker сброшен (success)")
    }

    /// Записывает провал — увеличивает счётчик, при достижении порога — открывает прерыватель.
    public func recordFailure() {
        failureCount += 1

        if failureCount >= threshold {
            let reopenAt = Date().addingTimeInterval(timeout)
            state = .open(until: reopenAt)
            logger.warning(
                "🔴 Circuit Breaker ОТКРЫТ на \(Int(timeout))с " +
                "(провалов подряд: \(failureCount))"
            )
        } else {
            logger.warning(
                "⚠️ провал \(failureCount)/\(threshold)"
            )
        }
    }

    /// Оставшееся время cooldown (0 если closed/halfOpen).
    public var cooldownRemaining: TimeInterval {
        guard case .open(let until) = state else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    /// Принудительно сбрасывает состояние (для тестов и ручного управления).
    public func reset() {
        state = .closed
        failureCount = 0
        logger.info("🔄 Circuit Breaker сброшен вручную")
    }
}