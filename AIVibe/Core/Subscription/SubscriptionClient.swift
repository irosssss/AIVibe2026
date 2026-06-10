// AIVibe/Core/Subscription/SubscriptionClient.swift
// TCA-клиент подписки: статус с backend (functions/payments) + ссылка на оплату.
// Конфигурация — Info.plist: AIVibePaymentsURL (gateway /payments), AIVibeAppToken.
// Офлайн/ошибки сети: возвращается последний закешированный статус (или .free) —
// деградация в сторону FREE, никогда не «дарим» PRO без подтверждения backend.
//
// ⚠️ App Store anti-steering (3.1.1): confirmationUrl ведёт на внешнюю оплату.
// Показывать его из iOS-UI напрямую — риск ревью; решение об UX-подаче — на
// уровне пейволла (A3.3), клиент только возвращает данные.
// См. docs/UPGRADE_PLAN.md — Фаза 1, A3.2.

import ComposableArchitecture
import Foundation

// MARK: - Клиент

public struct SubscriptionClient: Sendable {
    /// Текущий статус подписки (backend → кеш → .free).
    public var fetchStatus: @Sendable () async -> SubscriptionStatus
    /// Создать платёж за тариф; возвращает ссылку подтверждения ЮKassa.
    public var createPayment: @Sendable (SubscriptionTier) async throws -> SubscriptionPaymentLink

    public init(
        fetchStatus: @escaping @Sendable () async -> SubscriptionStatus,
        createPayment: @escaping @Sendable (SubscriptionTier) async throws -> SubscriptionPaymentLink
    ) {
        self.fetchStatus = fetchStatus
        self.createPayment = createPayment
    }
}

/// Ссылка на оплату, возвращаемая backend'ом (создание платежа ЮKassa).
public struct SubscriptionPaymentLink: Sendable, Equatable {
    public let paymentId: String
    public let confirmationUrl: URL
    public let amountRub: Int

    public init(paymentId: String, confirmationUrl: URL, amountRub: Int) {
        self.paymentId = paymentId
        self.confirmationUrl = confirmationUrl
        self.amountRub = amountRub
    }
}

// MARK: - Ошибки

public enum SubscriptionError: LocalizedError, Sendable, Equatable {
    case notConfigured
    case invalidResponse
    case freeTierHasNoPayment

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Оплата не настроена (AIVibePaymentsURL отсутствует в Info.plist)"
        case .invalidResponse:
            return "Некорректный ответ сервера оплаты"
        case .freeTierHasNoPayment:
            return "Для бесплатного тарифа оплата не требуется"
        }
    }
}

// MARK: - DTO backend-контракта (functions/payments)

private struct StatusRequestBody: Encodable {
    let action = "status"
    let userId: String
}

private struct StatusResponseBody: Decodable {
    let plan: String
    let isActive: Bool
    let expiresAt: String?
}

private struct CreateRequestBody: Encodable {
    let action = "create"
    let userId: String
    let plan: String
}

private struct CreateResponseBody: Decodable {
    let paymentId: String
    let confirmationUrl: String?
    let amountRub: Int
}

// MARK: - Live-реализация

private enum SubscriptionBackend {
    static let cacheKey = "subscription_status_v1"

    static var url: URL? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "AIVibePaymentsURL") as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    static var headers: [String: String] {
        var headers: [String: String] = [:]
        if let appToken = Bundle.main.object(forInfoDictionaryKey: "AIVibeAppToken") as? String,
           !appToken.isEmpty {
            headers["X-App-Token"] = appToken
        }
        return headers
    }
}

extension SubscriptionClient: DependencyKey {
    public static let liveValue = SubscriptionClient(
        fetchStatus: {
            let storage = StorageClient()

            guard let url = SubscriptionBackend.url else {
                // Backend не сконфигурирован — кеш или free.
                return (try? storage.load(forKey: SubscriptionBackend.cacheKey)) ?? .free
            }

            do {
                let networkClient = NetworkClient()
                let response: StatusResponseBody = try await networkClient.post(
                    url: url,
                    body: StatusRequestBody(userId: AnonymousUserID.current),
                    headers: SubscriptionBackend.headers
                )
                let status = SubscriptionStatus.fromBackend(
                    plan: response.plan,
                    isActive: response.isActive,
                    expiresAt: response.expiresAt
                )
                try? storage.save(status, forKey: SubscriptionBackend.cacheKey)
                return status
            } catch {
                // Сеть упала — последний известный статус или free (не дарим PRO).
                return (try? storage.load(forKey: SubscriptionBackend.cacheKey)) ?? .free
            }
        },
        createPayment: { tier in
            guard tier != .free else { throw SubscriptionError.freeTierHasNoPayment }
            guard let url = SubscriptionBackend.url else { throw SubscriptionError.notConfigured }

            let networkClient = NetworkClient()
            let response: CreateResponseBody = try await networkClient.post(
                url: url,
                body: CreateRequestBody(userId: AnonymousUserID.current, plan: tier.rawValue),
                headers: SubscriptionBackend.headers
            )
            guard let urlString = response.confirmationUrl,
                  let confirmationUrl = URL(string: urlString) else {
                throw SubscriptionError.invalidResponse
            }
            return SubscriptionPaymentLink(
                paymentId: response.paymentId,
                confirmationUrl: confirmationUrl,
                amountRub: response.amountRub
            )
        }
    )

    public static let testValue = SubscriptionClient(
        fetchStatus: { .free },
        createPayment: { _ in throw SubscriptionError.notConfigured }
    )
}

extension DependencyValues {
    public var subscriptionClient: SubscriptionClient {
        get { self[SubscriptionClient.self] }
        set { self[SubscriptionClient.self] = newValue }
    }
}
