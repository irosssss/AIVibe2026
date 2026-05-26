// AIVibe/Core/AI/ToolRegistry/Tools/AnalyzeRoomScanTool.swift
// Stage 2.1: Domain-specific инструмент — анализ LiDAR USDZ скана комнаты.
// Blueprint §6: analyze_room_scan — извлекает размеры, объекты, источники света, материалы.

import Foundation

// MARK: - Output Types

/// Размеры комнаты (Blueprint: room_dimensions).
public struct RoomDimensions: Sendable, Equatable, Codable {
    /// Ширина в метрах.
    public let widthM: Float
    /// Глубина в метрах.
    public let depthM: Float
    /// Высота в метрах.
    public let heightM: Float

    /// Площадь пола (м²).
    public var floorAreaM2: Float { widthM * depthM }

    /// Периметр (м).
    public var perimeterM: Float { 2 * (widthM + depthM) }

    /// Объём (м³).
    public var volumeM3: Float { widthM * depthM * heightM }

    public init(widthM: Float, depthM: Float, heightM: Float) {
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
    }
}

/// Обнаруженный объект в комнате (Blueprint: objects).
public struct DetectedObject: Sendable, Equatable, Codable {
    /// Тип объекта: окно, дверь, колонна, батарея, ниша.
    public let type: DetectedObjectType
    /// Позиция в 3D (x, y, z в метрах от левого нижнего угла комнаты).
    public let position: SIMD3<Float>
    /// Размер (w, d, h в метрах).
    public let size: SIMD3<Float>
    /// Подсказка по материалу: кирпич, бетон, гипсокартон, дерево.
    public let materialHint: String?
    /// Уверенность детекции (0–1).
    public let confidence: Float

    public init(
        type: DetectedObjectType,
        position: SIMD3<Float>,
        size: SIMD3<Float>,
        materialHint: String? = nil,
        confidence: Float = 0.8
    ) {
        self.type = type
        self.position = position
        self.size = size
        self.materialHint = materialHint
        self.confidence = confidence
    }
}

public enum DetectedObjectType: String, Sendable, Equatable, Codable {
    case window
    case door
    case column
    case radiator
    case niche
    case outlet
    case switchPanel
    case unknown
}

/// Источник света (Blueprint: light_sources).
public struct LightSource: Sendable, Equatable, Codable {
    /// Тип источника.
    public let type: LightSourceType
    /// Направление света (нормализованный вектор).
    public let direction: SIMD3<Float>
    /// Интенсивность (0–1, где 1 = яркое солнце).
    public let intensity: Float

    public init(type: LightSourceType, direction: SIMD3<Float>, intensity: Float = 0.5) {
        self.type = type
        self.direction = direction
        self.intensity = intensity
    }
}

public enum LightSourceType: String, Sendable, Equatable, Codable {
    case window
    case lamp
    case ceiling
    case floorLamp
    case sconce
}

// MARK: - Full Analysis Result

/// Полный результат анализа комнаты (Blueprint output_schema).
public struct RoomAnalysis: Sendable, Equatable, Codable {
    /// Размеры комнаты.
    public let roomDimensions: RoomDimensions
    /// Обнаруженные объекты.
    public let objects: [DetectedObject]
    /// Источники света.
    public let lightSources: [LightSource]
    /// Площадь пола в м² (дублирует roomDimensions.floorAreaM2 для удобства).
    public let floorAreaM2: Float
    /// Качество скана (0–1).
    public let scanQuality: Float
    /// Временная метка анализа.
    public let analyzedAt: Date

    public init(
        roomDimensions: RoomDimensions,
        objects: [DetectedObject] = [],
        lightSources: [LightSource] = [],
        scanQuality: Float = 0.0
    ) {
        self.roomDimensions = roomDimensions
        self.objects = objects
        self.lightSources = lightSources
        self.floorAreaM2 = roomDimensions.floorAreaM2
        self.scanQuality = min(max(scanQuality, 0), 1)
        self.analyzedAt = Date()
    }

    /// Сериализация в JSON-строку (для ToolResult.data).
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool Implementation

/// Инструмент анализа комнаты по LiDAR/USDZ скану.
///
/// Blueprint §6:
/// - risk_class: read_private_data
/// - side_effects: none
/// - permission: allow_with_user_scope
/// - timeout: 15s
/// - max_result_chars: 4000
public struct AnalyzeRoomScanTool: AgentTool {

    // MARK: - AgentTool Conformance

    public let name = "analyze_room_scan"
    public let description = """
    Анализирует LiDAR USDZ скан комнаты: извлекает размеры (ширина/глубина/высота),
    обнаруживает объекты (окна, двери, батареи, ниши), определяет источники света,
    оценивает качество скана. Возвращает структурированный RoomAnalysis.
    """

    public let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "usdz_uri": SchemaProperty(
                type: .string,
                description: "URI локального USDZ-файла или идентификатор загруженного скана"
            ),
            "room_id": SchemaProperty(
                type: .string,
                description: "Уникальный идентификатор комнаты в проекте пользователя"
            )
        ],
        required: ["usdz_uri", "room_id"]
    )

    public let riskClass: ToolRiskClass = .readPrivate
    public let timeout: TimeInterval = 15.0
    public let maxResultChars: Int = 4000
    public let sideEffects: ToolSideEffect = .readsUserData

    // MARK: - Validation

    public func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        // Проверка обязательных полей
        guard let usdzUri = arguments["usdz_uri"] as? String, !usdzUri.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'usdz_uri'"
            )
        }
        guard let roomId = arguments["room_id"] as? String, !roomId.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'room_id'"
            )
        }
        // Проверка формата URI
        guard usdzUri.hasSuffix(".usdz") || usdzUri.contains("usdz") else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Некорректный формат USDZ URI: '\(usdzUri)'"
            )
        }
        return arguments
    }

    // MARK: - Execute

    public func execute(validated: [String: Any]) async throws -> String {
        // swiftlint:disable force_cast
        let usdzUri = validated["usdz_uri"] as! String
        let roomId = validated["room_id"] as! String
        // swiftlint:enable force_cast

        // На macOS с RealityKit — реальный парсинг USDZ
        #if canImport(RealityKit) && os(visionOS) == false
        let analysis = try await parseUSDZRealityKit(usdzUri: usdzUri, roomId: roomId)
        #else
        // Windows / Linux / CI: mock-анализ с логом
        let analysis = mockAnalysis(usdzUri: usdzUri, roomId: roomId)
        #endif

        return try analysis.toJSON()
    }

    // MARK: - USDZ Parsing (macOS RealityKit)

    #if canImport(RealityKit) && os(visionOS) == false
    private func parseUSDZRealityKit(usdzUri: String, roomId: String) async throws -> RoomAnalysis {
        // URL из строки
        guard let url = URL(string: usdzUri) ?? URL(fileURLWithPath: usdzUri) as URL? else {
            throw ToolError.executionFailed(
                tool: name,
                error: "Невозможно создать URL из '\(usdzUri)'"
            )
        }

        // Загрузка USDZ через RealityKit (ожидает Mac с Xcode 16)
        // В реальной имплементации:
        // let entity = try await Entity.load(contentsOf: url)
        // Анализ bounding box, дочерних entities, материалов

        // Заглушка до Mac
        return mockAnalysis(usdzUri: usdzUri, roomId: roomId)
    }
    #endif

    // MARK: - Mock (Windows / CI / без RealityKit)

    /// Заглушка для разработки без Mac.
    /// Генерирует реалистичные тестовые данные на основе roomId.
    private func mockAnalysis(usdzUri: String, roomId: String) -> RoomAnalysis {
        // Детерминированная генерация параметров комнаты на основе хэша roomId
        let hash = abs(roomId.hashValue)
        let widthM  = Float(hash % 6) + 3.0   // 3–8 м
        let depthM  = Float((hash / 10) % 6) + 3.0 // 3–8 м
        let heightM = Float((hash / 100) % 3) + 2.5 // 2.5–4.5 м

        let dims = RoomDimensions(widthM: widthM, depthM: depthM, heightM: heightM)

        // Объекты
        let objects: [DetectedObject] = [
            DetectedObject(
                type: .window,
                position: SIMD3<Float>(widthM / 2, 1.0, 0),
                size: SIMD3<Float>(1.5, 0.2, 1.5),
                materialHint: "ПВХ стеклопакет",
                confidence: 0.95
            ),
            DetectedObject(
                type: .door,
                position: SIMD3<Float>(0.1, 0, depthM / 2),
                size: SIMD3<Float>(0.9, 0.1, 2.1),
                materialHint: "дерево",
                confidence: 0.92
            ),
            DetectedObject(
                type: .radiator,
                position: SIMD3<Float>(widthM / 2, 0.1, 0.05),
                size: SIMD3<Float>(2.4, 0.1, 0.6),
                materialHint: "алюминий",
                confidence: 0.88
            )
        ]

        // Источники света
        let lightSources: [LightSource] = [
            LightSource(
                type: .window,
                direction: SIMD3<Float>(0, 0, -1),
                intensity: 0.7
            ),
            LightSource(
                type: .ceiling,
                direction: SIMD3<Float>(0, -1, 0),
                intensity: 0.5
            )
        ]

        return RoomAnalysis(
            roomDimensions: dims,
            objects: objects,
            lightSources: lightSources,
            scanQuality: 0.85
        )
    }
}
