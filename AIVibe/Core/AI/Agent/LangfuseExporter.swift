// AIVibe/Core/AI/Agent/LangfuseExporter.swift
// Blueprint §13: Опциональный экспорт трейсов в Langfuse для глубокой аналитики промптов.
// Langfuse — open-source LLM observability (https://langfuse.com).
// Активируется только при наличии LANGFUSE_PUBLIC_KEY и LANGFUSE_SECRET_KEY в LockBox.

import Foundation
import CryptoKit
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
            metadata: redactPII(metadata.merging([
                "model": model,
                "duration_ms": String(format: "%.2f", durationMs)
            ]) { _, new in new }),
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

    /// Ключи метаданных, чьи значения содержат идентификатор пользователя (PII).
    /// Перед экспортом наружу (Langfuse) заменяем их на стабильный необратимый хеш.
    private static let piiMetadataKeys: Set<String> = ["user_id", "userId", "userID"]

    /// Псевдонимизирует PII-значения в метаданных перед отправкой в Langfuse.
    private func redactPII(_ metadata: [String: String]) -> [String: String] {
        guard metadata.contains(where: { Self.piiMetadataKeys.contains($0.key) }) else { return metadata }
        var out = metadata
        for key in metadata.keys where Self.piiMetadataKeys.contains(key) {
            out[key] = Self.pseudonymize(out[key] ?? "")
        }
        return out
    }

    /// Стабильный псевдоним: "u_" + 12 hex символов SHA-256. Необратим, но один и
    /// тот же userId всегда даёт один хеш — корреляция в аналитике сохраняется.
    private static func pseudonymize(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "u_\(hex)"
    }

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

        // Langfuse: для trace-create body.id ЯВЛЯЕТСЯ trace id.
        // Для span/generation body.id — уникальный id события, traceId ссылается на родительский trace.
        // Чтобы lifecycle-события (sessionStart/End) попадали в тот же trace, что и spans —
        // используем sessionId как body.id для .trace, и record.id для .span/.generation.
        let traceId = record.sessionId ?? record.id
        let bodyId: String
        switch eventType {
        case .trace:
            bodyId = traceId
        case .span, .generation:
            bodyId = record.id
        }

        return LangfuseEvent(
            type: eventType,
            id: bodyId,
            traceId: traceId,
            name: record.eventType.rawValue,
            startTime: ISO8601DateFormatter().string(from: record.timestamp),
            metadata: redactPII(record.metadata),
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LangfuseError.httpError(statusCode: -1)
        }

        let status = httpResponse.statusCode

        // Langfuse ingestion возвращает 207 Multi-Status с per-event ошибками в body
        // (валидация схемы, неверный type, и т.п.). Парсим тело и логируем отказы;
        // если ВСЕ события отклонены — бросаем ошибку и засчитываем как провал.
        if status == 207 {
            let report = (try? JSONDecoder().decode(LangfuseIngestionResponse.self, from: data))
            let rejected = report?.errors?.count ?? 0
            let accepted = report?.successes?.count ?? max(0, events.count - rejected)

            if rejected > 0 {
                let preview = report?.errors?.prefix(3)
                    .map { "[\($0.id ?? "?") status=\($0.status ?? -1) \($0.message ?? $0.error ?? "")]" }
                    .joined(separator: " ") ?? ""
                logger.warning(
                    "Langfuse 207: отклонено \(rejected)/\(events.count) событий — \(preview)"
                )
                // Если ни одно событие не принято — это полный провал, тригерим circuit breaker
                if accepted == 0 {
                    throw LangfuseError.partialFailure(rejected: rejected, accepted: 0)
                }
            }
            logger.debug("Langfuse: отправлено \(accepted)/\(events.count) событий (HTTP 207)")
            return
        }

        guard (200...299).contains(status) else {
            // Логируем тело ответа для диагностики (ограничиваем размер)
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                logger.warning("Langfuse HTTP \(status): \(body.prefix(500))")
            }
            throw LangfuseError.httpError(statusCode: status)
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

/// Ответ Langfuse `/api/public/ingestion` (HTTP 207 Multi-Status).
/// Содержит списки принятых и отклонённых событий.
struct LangfuseIngestionResponse: Sendable, Decodable {
    let successes: [Success]?
    let errors: [IngestionError]?

    struct Success: Sendable, Decodable {
        let id: String?
        let status: Int?
    }

    struct IngestionError: Sendable, Decodable {
        let id: String?
        let status: Int?
        let message: String?
        let error: String?
    }
}

// MARK: - Langfuse Error

enum LangfuseError: LocalizedError, Sendable {
    case httpError(statusCode: Int)
    case partialFailure(rejected: Int, accepted: Int)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Langfuse HTTP ошибка: \(code)"
        case .partialFailure(let rejected, let accepted):
            "Langfuse частичный отказ: отклонено \(rejected), принято \(accepted)"
        case .notConfigured: "Langfuse не настроен (отсутствуют ключи)"
        }
    }
}
