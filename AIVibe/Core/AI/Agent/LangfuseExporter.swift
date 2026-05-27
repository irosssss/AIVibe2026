// AIVibe/Core/AI/Agent/LangfuseExporter.swift
// Blueprint §13: Опциональный экспорт трейсов в Langfuse для глубокой аналитики промптов.
// Langfuse — open-source LLM observability (https://langfuse.com).
// Активируется только при наличии LANGFUSE_PUBLIC_KEY и LANGFUSE_SECRET_KEY в LockBox.

import Foundation
import Logging

// MARK: - Langfuse Exporter

/// Асинхронный экспортёр трейсов в Langfuse API.
///
/// Буферизует события и отправляет батчами (до 10 событий или раз в 5 секунд).
/// При недоступности Langfuse — молча пропускает (не блокирует агент).
public actor LangfuseExporter {

    // MARK: - Configuration

    public struct Config: Sendable {
        public let publicKey: String
        public let secretKey: String
        public let baseURL: String
        public let batchSize: Int
        public let flushIntervalSeconds: Double
        public let enabled: Bool

        public init(
            publicKey: String,
            secretKey: String,
            baseURL: String = "https://cloud.langfuse.com",
            batchSize: Int = 10,
            flushIntervalSeconds: Double = 5.0,
            enabled: Bool = true
        ) {
            self.publicKey = publicKey
            self.secretKey = secretKey
            self.baseURL = baseURL
            self.batchSize = batchSize
            self.flushIntervalSeconds = flushIntervalSeconds
            self.enabled = enabled
        }
    }

    // MARK: - State

    private let config: Config
    private var buffer: [LangfuseEvent] = []
    private var flushTask: Task<Void, Never>?
    private let logger = Logger(label: "ai.langfuse")
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 5

    // MARK: - Init

    public init(config: Config) {
        self.config = config
        if config.enabled {
            logger.info("Langfuse экспортёр активирован (\(config.baseURL))")
        }
    }

    /// Создаёт экспортёр из LockBox (возвращает nil если ключи отсутствуют).
    public static func fromSecrets(
        publicKey: String?,
        secretKey: String?,
        baseURL: String = "https://cloud.langfuse.com"
    ) -> LangfuseExporter? {
        guard let pub = publicKey, let sec = secretKey,
              !pub.isEmpty, !sec.isEmpty else {
            return nil
        }
        return LangfuseExporter(config: Config(
            publicKey: pub,
            secretKey: sec,
            baseURL: baseURL
        ))
    }

    // MARK: - Public API

    /// Экспортирует TraceRecord как Langfuse trace/span.
    public func export(_ record: TraceRecord, sessionId: String? = nil) {
        guard config.enabled, consecutiveFailures < maxConsecutiveFailures else { return }

        let event = mapToLangfuseEvent(record, sessionId: sessionId)
        buffer.append(event)

        if buffer.count >= config.batchSize {
            Task { await flush() }
        } else {
            scheduleFlush()
        }
    }

    /// Экспортирует промпт и ответ как Langfuse generation (ключевая фича — трейсинг LLM-вызовов).
    public func exportGeneration(
        traceId: String,
        name: String,
        model: String,
        input: String,
        output: String,
        durationMs: Double,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        guard config.enabled, consecutiveFailures < maxConsecutiveFailures else { return }

        let event = LangfuseEvent(
            type: .generation,
            id: UUID().uuidString,
            traceId: traceId,
            name: name,
            startTime: ISO8601DateFormatter().string(from: Date()),
            metadata: metadata.merging([
                "model": model,
                "duration_ms": String(format: "%.2f", durationMs)
            ]) { _, new in new },
            input: input,
            output: output,
            model: model,
            usage: LangfuseUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: (promptTokens ?? 0) + (completionTokens ?? 0)
            )
        )

        buffer.append(event)

        if buffer.count >= config.batchSize {
            Task { await flush() }
        } else {
            scheduleFlush()
        }
    }

    /// Принудительно отправляет все буферизованные события.
    public func flush() async {
        guard !buffer.isEmpty else { return }

        let batch = buffer
        buffer.removeAll()

        do {
            try await sendBatch(batch)
            consecutiveFailures = 0
        } catch {
            logger.warning("Langfuse flush ошибка: \(error.localizedDescription)")
            consecutiveFailures += 1
            if consecutiveFailures >= maxConsecutiveFailures {
                logger.error("Langfuse: \(maxConsecutiveFailures) ошибок подряд — экспорт приостановлен")
            }
        }
    }

    /// Сбрасывает счётчик ошибок (например, после восстановления сети).
    public func resetFailures() {
        consecutiveFailures = 0
        logger.info("Langfuse: счётчик ошибок сброшен")
    }

    // MARK: - Private

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(config.flushIntervalSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private func mapToLangfuseEvent(_ record: TraceRecord, sessionId: String?) -> LangfuseEvent {
        let eventType: LangfuseEvent.EventType = switch record.eventType {
        case .toolCall, .toolResult:
            .span
        case .sessionStart, .sessionEnd:
            .trace
        case .providerSwitch, .compaction:
            .span
        case .providerHealthCheck:
            .span
        case .approvalRequest, .approvalDecision:
            .span
        case .evalProbeStarted, .evalProbeCompleted, .evalProbeFailed:
            .span
        }

        return LangfuseEvent(
            type: eventType,
            id: record.id,
            traceId: record.sessionId ?? record.id,
            name: record.eventType.rawValue,
            startTime: ISO8601DateFormatter().string(from: record.timestamp),
            metadata: record.metadata,
            input: record.toolName,
            output: record.resultSize.map { String($0) },
            model: record.providerName,
            usage: nil
        )
    }

    private func sendBatch(_ events: [LangfuseEvent]) async throws {
        let url = URL(string: "\(config.baseURL)/api/public/ingestion")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Basic auth: publicKey:secretKey
        let credentials = "\(config.publicKey):\(config.secretKey)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let payload = LangfuseBatchPayload(
            batch: events.map { event in
                LangfuseIngestionEvent(
                    id: event.id,
                    type: event.type.ingestionType,
                    timestamp: event.startTime,
                    body: event
                )
            }
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LangfuseError.httpError(statusCode: code)
        }

        logger.debug("Langfuse: отправлено \(events.count) событий")
    }
}

// MARK: - Langfuse Models

struct LangfuseEvent: Sendable, Codable {
    enum EventType: String, Sendable, Codable {
        case trace
        case span
        case generation

        var ingestionType: String {
            switch self {
            case .trace: "trace-create"
            case .span: "span-create"
            case .generation: "generation-create"
            }
        }
    }

    let type: EventType
    let id: String
    let traceId: String
    let name: String
    let startTime: String
    let metadata: [String: String]
    let input: String?
    let output: String?
    let model: String?
    let usage: LangfuseUsage?
}

struct LangfuseUsage: Sendable, Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct LangfuseIngestionEvent: Sendable, Codable {
    let id: String
    let type: String
    let timestamp: String
    let body: LangfuseEvent
}

struct LangfuseBatchPayload: Sendable, Codable {
    let batch: [LangfuseIngestionEvent]
}

// MARK: - Langfuse Error

enum LangfuseError: LocalizedError, Sendable {
    case httpError(statusCode: Int)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Langfuse HTTP ошибка: \(code)"
        case .notConfigured: "Langfuse не настроен (отсутствуют ключи)"
        }
    }
}
