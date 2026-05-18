// AIVibe/Core/AI/CircuitBreakerConfig.swift
// Единый источник констант Circuit Breaker для всех Swift-провайдеров.
// При изменении — синхронизировать с backend/shared/circuit-config.js

import Foundation

/// Конфигурация Circuit Breaker по умолчанию.
/// Вынесена в отдельный файл, чтобы избежать расхождения между iOS и backend.
public struct CircuitBreakerConfig: Sendable {

    /// Количество последовательных ошибок до размыкания цепи.
    public let threshold: Int

    /// Время (сек) в состоянии open, после которого делается пробный запрос (half-open).
    public let timeout: TimeInterval

    /// Единственный instance production-конфигурации.
    public static let shared = CircuitBreakerConfig(
        threshold: 3,
        timeout: 300  // 5 минут
    )

    public init(threshold: Int, timeout: TimeInterval) {
        self.threshold = threshold
        self.timeout = timeout
    }
}
