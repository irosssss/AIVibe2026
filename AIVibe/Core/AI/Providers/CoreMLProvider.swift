// AIVibe/Core/AI/Providers/CoreMLProvider.swift
// Модуль: Core/AI
// Оффлайн-провайдер на основе Core ML модели (Triplex fallback).
// Модель загружается lazy при первом обращении.
// Поддерживает только базовые запросы: стиль интерьера, палитры, советы.

import Foundation
import CoreML
import Logging

// MARK: - CoreML Model Protocol

/// Протокол оберхи ML-модели для тестируемости.
public protocol CoreMLModelProviding: Sendable {
    func predict(input: String, maxTokens: Int) async throws -> String
}

// MARK: - CoreMLProvider

/// Оффлайн AI-провайдер через Core ML.
/// Все ответы помечаются isOffline: true.
public actor CoreMLProvider: AIProviderProtocol {

    // MARK: - Конфигурация

    public struct Configuration: Sendable {
        /// Имя .mlmodelc файла в Bundle
        let modelFileName: String
        /// Максимальная длина промпта для локальной модели
        let maxInputLength: Int

        public init(
            modelFileName: String = "AIVibeOffline",
            maxInputLength: Int   = 512
        ) {
            self.modelFileName = modelFileName
            self.maxInputLength = maxInputLength
        }
    }

    // MARK: - Properties

    nonisolated public let name = "CoreML (Оффлайн)"

    private let config: Configuration
    private let logger = Logger(label: "ai.coreml")

    /// Lazy-загруженная модель. nil — ещё не загружена или не доступна.
    private var model: (any CoreMLModelProviding)?
    private var isModelLoaded = false
    private var modelLoadError: AIError?

    // MARK: - Init

    public init(config: Configuration = .init()) {
        self.config = config
    }

    // MARK: - AIProviderProtocol

    public var isAvailable: Bool {
        get async {
            // Доступен если модель загружена или можно попробовать загрузить
            if isModelLoaded { return model != nil }
            await loadModelIfNeeded()
            return model != nil
        }
    }

    public func complete(prompt: AIPrompt) async throws -> AIResponse {
        await loadModelIfNeeded()

        guard let loadedModel = model else {
            throw modelLoadError ?? AIError.modelLoadingFailed(config.modelFileName)
        }

        // Ограничиваем длину для локальной модели
        let inputText = buildInput(from: prompt)
        let truncated = String(inputText.prefix(config.maxInputLength))

        logger.info("CoreML обрабатывает запрос (\(truncated.count) символов)")

        let result = try await loadedModel.predict(
            input: truncated,
            maxTokens: min(prompt.maxTokens, 256) // Локальная модель — меньший лимит
        )

        return AIResponse(
            text: result,
            providerName: name,
            isOffline: true,
            tokensUsed: 0 // Core ML не считает токены
        )
    }

    public func analyzeImage(_ imageData: Data, prompt: String) async throws -> AIResponse {
        // Core ML Vision pipeline — заглушка для будущей реализации
        throw AIError.providerUnavailable(
            provider: "\(name): analyzeImage в разработке"
        )
    }

    // MARK: - Private

    /// Загружает модель из Bundle асинхронно (lazy, только один раз).
    private func loadModelIfNeeded() async {
        guard !isModelLoaded else { return }
        isModelLoaded = true // Устанавливаем флаг до загрузки чтобы избежать двойной загрузки

        do {
            guard let modelURL = Bundle.main.url(
                forResource: config.modelFileName,
                withExtension: "mlmodelc"
            ) else {
                logger.warning("CoreML модель '\(config.modelFileName).mlmodelc' не найдена в Bundle")
                modelLoadError = .modelLoadingFailed(
                    "\(config.modelFileName).mlmodelc не найден в Bundle"
                )
                return
            }

            // iOS 18: MLModel.load(contentsOf:configuration:) — async нативно
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = .cpuAndNeuralEngine // Используем Neural Engine на Apple Silicon
            let loadedMLModel = try await MLModel.load(contentsOf: modelURL, configuration: mlConfig)

            model = AIVibeMLModelWrapper(mlModel: loadedMLModel)
            logger.info("CoreML модель '\(config.modelFileName)' загружена успешно")
        } catch {
            logger.error("CoreML не удалось загрузить модель: \(error)")
            modelLoadError = .modelLoadingFailed(error.localizedDescription)
        }
    }

    /// Собирает текстовый промпт из структурированного AIPrompt.
    private func buildInput(from prompt: AIPrompt) -> String {
        prompt.messages
            .filter { $0.role != .system }
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
    }
}

// MARK: - MLModel Wrapper

/// Обёртка над MLModel для реализации протокола CoreMLModelProviding.
private final class AIVibeMLModelWrapper: CoreMLModelProviding, @unchecked Sendable {
    private let mlModel: MLModel

    init(mlModel: MLModel) {
        self.mlModel = mlModel
    }

    func predict(input: String, maxTokens: Int) async throws -> String {
        // Универсальная реализация через MLFeatureProvider
        // Конкретные ключи зависят от используемой модели
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_text": MLFeatureValue(string: input)
        ])

        let output = try mlModel.prediction(from: inputFeatures)

        // Извлекаем текстовый выход — ключ зависит от модели
        if let text = output.featureValue(for: "output_text")?.stringValue {
            return text
        }

        // Fallback: первый строковый feature
        for featureName in output.featureNames {
            if let text = output.featureValue(for: featureName)?.stringValue {
                return text
            }
        }

        throw AIError.invalidResponse(
            provider: "CoreML",
            details: "Модель не вернула текстовый output"
        )
    }
}
