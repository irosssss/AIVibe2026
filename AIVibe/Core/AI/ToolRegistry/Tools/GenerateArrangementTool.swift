// AIVibe/Core/AI/ToolRegistry/Tools/GenerateArrangementTool.swift
// Stage 2.4: Domain-specific инструмент — генерация плана расстановки мебели с AR-координатами.
// Blueprint §6: generate_arrangement_plan — placement, walk path, visual balance, warnings.

import Foundation

// MARK: - Input Types

/// Позиция в 3D-пространстве комнаты (метры).
public struct ARPosition: Sendable, Equatable, Codable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Нулевая позиция (начало координат).
    public static let zero = ARPosition(x: 0, y: 0, z: 0)
}

/// Вращение в градусах Эйлера (pitch, yaw, roll).
public struct ARRotation: Sendable, Equatable, Codable {
    public let pitch: Float   // вокруг X
    public let yaw: Float     // вокруг Y
    public let roll: Float    // вокруг Z

    public init(pitch: Float, yaw: Float, roll: Float) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
    }

    /// Без вращения.
    public static let identity = ARRotation(pitch: 0, yaw: 0, roll: 0)
}

/// Один элемент расстановки: мебель с координатами для AR.
public struct FurniturePlacement: Sendable, Equatable, Codable {
    /// ID товара из результатов поиска (SearchMarketplaceFurniture).
    public let furnitureId: String
    /// Название предмета для отображения.
    public let displayName: String
    /// Позиция в 3D (метры от левого нижнего угла комнаты).
    public let position: ARPosition
    /// Вращение (градусы Эйлера).
    public let rotation: ARRotation
    /// Масштаб (1.0 = оригинальный размер).
    public let scale: Float
    /// Размеры предмета в метрах (из dimensionsCm / 100).
    public let sizeM: FurnitureDimensionsM

    public init(
        furnitureId: String,
        displayName: String,
        position: ARPosition,
        rotation: ARRotation = .identity,
        scale: Float = 1.0,
        sizeM: FurnitureDimensionsM
    ) {
        self.furnitureId = furnitureId
        self.displayName = displayName
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.sizeM = sizeM
    }
}

/// Размеры в метрах (для расчёта коллизий и walk path).
public struct FurnitureDimensionsM: Sendable, Equatable, Codable {
    public let width: Float
    public let depth: Float
    public let height: Float

    public init(width: Float, depth: Float, height: Float) {
        self.width = width
        self.depth = depth
        self.height = height
    }
}

/// Запрос на расстановку: один предмет мебели с опциональной подсказкой позиции.
public struct FurnitureSelectionItem: Sendable, Equatable, Codable {
    /// ID товара.
    public let id: String
    /// Название для отображения.
    public let name: String
    /// Категория (для эвристик расстановки).
    public let category: String
    /// Размеры в метрах.
    public let sizeM: FurnitureDimensionsM
    /// Опциональная подсказка позиции (пользователь сказал «диван у окна»).
    public let positionHint: ARPosition?

    public init(
        id: String,
        name: String,
        category: String,
        sizeM: FurnitureDimensionsM,
        positionHint: ARPosition? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.sizeM = sizeM
        self.positionHint = positionHint
    }
}

// MARK: - Output Types

/// Полный план расстановки (Blueprint output_schema).
public struct ArrangementPlan: Sendable, Equatable, Codable {
    /// Расстановка мебели (каждый предмет с координатами).
    public let placements: [FurniturePlacement]
    /// Оценка удобства прохода (0–1, где 1 = идеально).
    public let walkPathScore: Float
    /// Оценка визуального баланса (0–1, где 1 = идеально).
    public let visualBalanceScore: Float
    /// Предупреждения (коллизии, перекрытие окон, неудобный проход).
    public let warnings: [String]
    /// Свободная площадь после расстановки (м²).
    public let freeFloorAreaM2: Float
    /// Использованная площадь (м²).
    public let occupiedFloorAreaM2: Float
    /// Рекомендации по улучшению.
    public let suggestions: [String]
    /// Временная метка.
    public let generatedAt: Date

    public init(
        placements: [FurniturePlacement],
        walkPathScore: Float,
        visualBalanceScore: Float,
        warnings: [String] = [],
        freeFloorAreaM2: Float = 0,
        occupiedFloorAreaM2: Float = 0,
        suggestions: [String] = [],
        generatedAt: Date = Date()
    ) {
        self.placements = placements
        self.walkPathScore = walkPathScore
        self.visualBalanceScore = visualBalanceScore
        self.warnings = warnings
        self.freeFloorAreaM2 = freeFloorAreaM2
        self.occupiedFloorAreaM2 = occupiedFloorAreaM2
        self.suggestions = suggestions
        self.generatedAt = generatedAt
    }

    /// Сериализация в JSON-строку.
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Tool Implementation

/// Инструмент генерации плана расстановки мебели с AR-координатами.
///
/// Blueprint §6:
/// - risk_class: draft
/// - side_effects: none
/// - permission: allow
/// - timeout: 15s
/// - max_items: 30
// swiftlint:disable:next type_body_length
public struct GenerateArrangementTool: AgentTool {

    // MARK: - AgentTool Conformance

    public let name = "generate_arrangement_plan"
    public let description = """
    Создаёт план расстановки мебели с точными 3D-координатами для AR-отображения.
    Принимает размеры комнаты (RoomAnalysis) и список выбранной мебели,
    размещает предметы с учётом проходов, окон, дверей и визуального баланса.
    Возвращает placements (позиция + вращение + масштаб), walk_path_score,
    visual_balance_score и предупреждения о коллизиях.
    Максимум 30 предметов.
    """

    public let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "room_analysis": SchemaProperty(
                type: .string,
                description: "JSON-строка результата analyze_room_scan (RoomAnalysis.toJSON())"
            ),
            "furniture_selection": SchemaProperty(
                type: .array,
                description: "Массив выбранной мебели: [{id, name, category, sizeM: {width, depth, height}, positionHint?}]"
            ),
            "style": SchemaProperty(
                type: .string,
                description: "Стиль интерьера для правил расстановки",
                enumValues: InteriorStyle.allCases.map(\.rawValue)
            )
        ],
        required: ["room_analysis", "furniture_selection"]
    )

    public let riskClass: ToolRiskClass = .draft
    public let timeout: TimeInterval = 15.0
    public let maxResultChars: Int = 8000
    public let sideEffects: ToolSideEffect = .none

    /// Максимальное количество предметов (Blueprint: max_items: 30).
    private let maxItems = 30

    // MARK: - Constants for arrangement

    /// Минимальная ширина прохода (м).
    private let minWalkwayWidth: Float = 0.7
    /// Отступ от стен по умолчанию (м).
    private let wallMargin: Float = 0.05
    /// Отступ от окна (м).
    private let windowMargin: Float = 0.15
    /// Отступ от двери (м) — зона открывания.
    private let doorClearance: Float = 1.0

    // MARK: - Validation

    public func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let roomAnalysis = arguments["room_analysis"] as? String, !roomAnalysis.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'room_analysis'"
            )
        }
        guard arguments["furniture_selection"] != nil else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует 'furniture_selection'"
            )
        }
        return arguments
    }

    // MARK: - Execute

    public func execute(validated: [String: Any]) async throws -> String {
        // Парсим комнату
        // swiftlint:disable force_cast
        let roomJSON = validated["room_analysis"] as! String
        // swiftlint:enable force_cast
        let room: RoomAnalysis
        do {
            let data = roomJSON.data(using: .utf8)!
            room = try JSONDecoder().decode(RoomAnalysis.self, from: data)
        } catch {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Некорректный JSON room_analysis: \(error.localizedDescription)"
            )
        }

        // Парсим мебель
        let furniture: [FurnitureSelectionItem]
        if let array = validated["furniture_selection"] as? [[String: Any]] {
            furniture = try parseFurnitureSelection(array)
        } else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "'furniture_selection' должен быть массивом объектов"
            )
        }

        guard furniture.count <= maxItems else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Слишком много предметов: \(furniture.count) > \(maxItems)"
            )
        }

        let styleStr = validated["style"] as? String

        // Генерируем расстановку
        let plan = generateArrangement(room: room, furniture: furniture, style: styleStr)

        return try plan.toJSON()
    }

    // MARK: - Parsing

    private func parseFurnitureSelection(_ array: [[String: Any]]) throws -> [FurnitureSelectionItem] {
        var items: [FurnitureSelectionItem] = []
        for (index, dict) in array.enumerated() {
            guard let id = dict["id"] as? String, !id.isEmpty else {
                throw ToolError.validationFailed(tool: name, reason: "Элемент \(index): отсутствует 'id'")
            }
            guard let name = dict["name"] as? String else {
                throw ToolError.validationFailed(tool: name, reason: "Элемент \(index): отсутствует 'name'")
            }
            let category = dict["category"] as? String ?? "other"

            let sizeM: FurnitureDimensionsM
            if let sizeDict = dict["sizeM"] as? [String: Any],
               let w = sizeDict["width"] as? Float,
               let d = sizeDict["depth"] as? Float,
               let h = sizeDict["height"] as? Float {
                sizeM = FurnitureDimensionsM(width: w, depth: d, height: h)
            } else {
                // Размеры по умолчанию для категории
                sizeM = defaultSizeForCategory(category)
            }

            var positionHint: ARPosition?
            if let hintDict = dict["positionHint"] as? [String: Any],
               let x = hintDict["x"] as? Float,
               let y = hintDict["y"] as? Float,
               let z = hintDict["z"] as? Float {
                positionHint = ARPosition(x: x, y: y, z: z)
            }

            items.append(FurnitureSelectionItem(
                id: id,
                name: name,
                category: category,
                sizeM: sizeM,
                positionHint: positionHint
            ))
        }
        return items
    }

    private func defaultSizeForCategory(_ category: String) -> FurnitureDimensionsM {
        switch category {
        case "sofa":   return FurnitureDimensionsM(width: 2.20, depth: 0.95, height: 0.85)
        case "table":  return FurnitureDimensionsM(width: 1.40, depth: 0.80, height: 0.75)
        case "chair":  return FurnitureDimensionsM(width: 0.55, depth: 0.50, height: 0.85)
        case "lamp":   return FurnitureDimensionsM(width: 0.30, depth: 0.30, height: 1.60)
        case "cabinet": return FurnitureDimensionsM(width: 2.00, depth: 0.60, height: 2.40)
        case "decor":  return FurnitureDimensionsM(width: 0.40, depth: 0.15, height: 0.60)
        case "rug":    return FurnitureDimensionsM(width: 2.00, depth: 3.00, height: 0.01)
        case "bed":    return FurnitureDimensionsM(width: 1.60, depth: 2.00, height: 0.90)
        case "shelf":  return FurnitureDimensionsM(width: 1.20, depth: 0.35, height: 1.80)
        default:       return FurnitureDimensionsM(width: 1.00, depth: 0.50, height: 1.00)
        }
    }

    // MARK: - Arrangement Engine

    private func generateArrangement(
        room: RoomAnalysis,
        furniture: [FurnitureSelectionItem],
        style: String?
    ) -> ArrangementPlan {
        let dims = room.roomDimensions
        var placements: [FurniturePlacement] = []
        var occupiedRects: [(x: Float, z: Float, w: Float, d: Float)] = []
        var warnings: [String] = []
        var suggestions: [String] = []

        // Определяем запретные зоны: окна, двери, батареи
        let forbiddenZones = extractForbiddenZones(from: room)

        // Приоритет расстановки: крупная мебель → средняя → мелкая
        let sortedFurniture = furniture.sorted { a, b in
            let areaA = a.sizeM.width * a.sizeM.depth
            let areaB = b.sizeM.width * b.sizeM.depth
            return areaA > areaB
        }

        for item in sortedFurniture {
            let placement = arrangeItem(
                item: item,
                roomDims: dims,
                occupiedRects: &occupiedRects,
                forbiddenZones: forbiddenZones,
                warnings: &warnings
            )
            placements.append(placement)
        }

        // Оценки
        let totalFloorArea = dims.floorAreaM2
        let occupiedArea = occupiedRects.reduce(0) { $0 + $1.w * $1.d }
        let freeFloorArea = max(0, totalFloorArea - occupiedArea)

        let walkPathScore = calculateWalkPathScore(
            roomDims: dims,
            placements: placements,
            forbiddenZones: forbiddenZones
        )
        let visualBalanceScore = calculateVisualBalanceScore(
            roomDims: dims,
            placements: placements
        )

        // Дополнительные предупреждения
        if occupiedArea > totalFloorArea * 0.6 {
            warnings.append("Занято более 60% площади (\(Int(occupiedArea/totalFloorArea*100))%) — комната может казаться загромождённой")
        }
        if freeFloorArea < 4.0 {
            warnings.append("Свободной площади менее 4м² — ограниченное пространство для передвижения")
        }

        // Предложения
        if walkPathScore < 0.5 {
            suggestions.append("Увеличьте расстояние между крупными предметами для улучшения проходимости")
        }
        if visualBalanceScore < 0.5 {
            suggestions.append("Распределите крупные предметы равномернее по комнате для визуального баланса")
        }
        if !warnings.contains(where: { $0.contains("окн") }) && hasWindowBlockage(placements, room: room) {
            warnings.append("Некоторые предметы перекрывают доступ к окну")
        }

        return ArrangementPlan(
            placements: placements,
            walkPathScore: walkPathScore,
            visualBalanceScore: visualBalanceScore,
            warnings: warnings,
            freeFloorAreaM2: freeFloorArea,
            occupiedFloorAreaM2: occupiedArea,
            suggestions: suggestions
        )
    }

    // MARK: - Item Placement

    private func arrangeItem(
        item: FurnitureSelectionItem,
        roomDims: RoomDimensions,
        occupiedRects: inout [(x: Float, z: Float, w: Float, d: Float)],
        forbiddenZones: [(x: Float, z: Float, w: Float, d: Float)],
        warnings: inout [String]
    ) -> FurniturePlacement {
        let itemW = item.sizeM.width
        let itemD = item.sizeM.depth

        // 1. Если есть positionHint — пробуем использовать его
        if let hint = item.positionHint {
            let (canPlace, adjustedPos) = tryPlaceAt(
                x: hint.x, z: hint.z,
                width: itemW, depth: itemD,
                roomDims: roomDims,
                occupiedRects: occupiedRects,
                forbiddenZones: forbiddenZones
            )
            if canPlace {
                let rotation = bestRotationForCategory(item.category, roomDims: roomDims)
                occupiedRects.append((adjustedPos.x, adjustedPos.z, itemW, itemD))
                return FurniturePlacement(
                    furnitureId: item.id,
                    displayName: item.name,
                    position: adjustedPos,
                    rotation: rotation,
                    scale: 1.0,
                    sizeM: item.sizeM
                )
            }
        }

        // 2. Эвристика по категории
        let (bestX, bestZ, rotation) = findBestPosition(
            category: item.category,
            width: itemW,
            depth: itemD,
            roomDims: roomDims,
            occupiedRects: occupiedRects,
            forbiddenZones: forbiddenZones
        )

        if bestX < 0 {
            // Не удалось разместить
            warnings.append("Не удалось разместить '\(item.name)' — недостаточно свободного места")
            // Размещаем в углу как last resort
            let fallbackX = wallMargin
            let fallbackZ = wallMargin
            occupiedRects.append((fallbackX, fallbackZ, itemW, itemD))
            return FurniturePlacement(
                furnitureId: item.id,
                displayName: item.name,
                position: ARPosition(x: fallbackX, y: 0, z: fallbackZ),
                rotation: .identity,
                scale: 1.0,
                sizeM: item.sizeM
            )
        }

        occupiedRects.append((bestX, bestZ, itemW, itemD))
        return FurniturePlacement(
            furnitureId: item.id,
            displayName: item.name,
            position: ARPosition(x: bestX, y: 0, z: bestZ),
            rotation: rotation,
            scale: 1.0,
            sizeM: item.sizeM
        )
    }

    // MARK: - Position Finding

    /// Пытается разместить предмет по указанным координатам с проверкой коллизий.
    private func tryPlaceAt(
        x: Float, z: Float,
        width: Float, depth: Float,
        roomDims: RoomDimensions,
        occupiedRects: [(x: Float, z: Float, w: Float, d: Float)],
        forbiddenZones: [(x: Float, z: Float, w: Float, d: Float)]
    ) -> (Bool, ARPosition) {
        // Корректируем, чтобы не вылезать за стены
        let clampedX = max(wallMargin, min(x, roomDims.widthM - width - wallMargin))
        let clampedZ = max(wallMargin, min(z, roomDims.depthM - depth - wallMargin))

        // Проверка коллизий с занятыми зонами
        for rect in occupiedRects {
            if rectsOverlap(
                x1: clampedX, z1: clampedZ, w1: width, d1: depth,
                x2: rect.x, z2: rect.z, w2: rect.w, d2: rect.d
            ) {
                return (false, ARPosition(x: clampedX, y: 0, z: clampedZ))
            }
        }

        // Проверка запретных зон
        for zone in forbiddenZones {
            if rectsOverlap(
                x1: clampedX, z1: clampedZ, w1: width, d1: depth,
                x2: zone.x, z2: zone.z, w2: zone.w, d2: zone.d
            ) {
                return (false, ARPosition(x: clampedX, y: 0, z: clampedZ))
            }
        }

        return (true, ARPosition(x: clampedX, y: 0, z: clampedZ))
    }

    /// Находит лучшую позицию для предмета по эвристикам категории.
    /// Возвращает (x, z, rotation) или (-1, -1, identity) если не найдено.
    private func findBestPosition(
        category: String,
        width: Float,
        depth: Float,
        roomDims: RoomDimensions,
        occupiedRects: [(x: Float, z: Float, w: Float, d: Float)],
        forbiddenZones: [(x: Float, z: Float, w: Float, d: Float)]
    ) -> (Float, Float, ARRotation) {
        let candidates: [(Float, Float, ARRotation)]

        switch category {
        case "sofa":
            // Диван: вдоль длинной стены, напротив окна если есть
            candidates = wallAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims,
                preferredWall: .longest,
                offsetFromWall: 0.10
            )
        case "table":
            // Стол: центр комнаты или смещён к центру
            candidates = centerAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims
            )
        case "chair":
            // Стулья: вокруг стола или вдоль стен
            candidates = perimeterPositions(
                width: width, depth: depth,
                roomDims: roomDims,
                offsetFromWall: 0.25
            )
        case "cabinet", "shelf":
            // Шкафы: вдоль стен без окон
            candidates = wallAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims,
                preferredWall: .withoutWindows,
                offsetFromWall: 0.05
            )
        case "lamp":
            // Лампы: углы или рядом с диваном
            candidates = cornerPositions(
                width: width, depth: depth,
                roomDims: roomDims
            )
        case "rug":
            // Ковёр: центр комнаты
            candidates = centerAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims
            )
        case "bed":
            // Кровать: изголовье к стене, центр спальни
            candidates = wallAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims,
                preferredWall: .longest,
                offsetFromWall: 0.05
            )
        default:
            // Универсально: пробуем сначала вдоль стен, потом центр
            candidates = wallAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims,
                preferredWall: .any,
                offsetFromWall: 0.15
            ) + centerAlignedPositions(
                width: width, depth: depth,
                roomDims: roomDims
            )
        }

        // Пробуем кандидатов по порядку
        for (x, z, rot) in candidates {
            let (fits, pos) = tryPlaceAt(
                x: x, z: z,
                width: width, depth: depth,
                roomDims: roomDims,
                occupiedRects: occupiedRects,
                forbiddenZones: forbiddenZones
            )
            if fits {
                return (pos.x, pos.z, rot)
            }
        }

        return (-1, -1, .identity)
    }

    // MARK: - Position Generators

    private enum PreferredWall {
        case longest, withoutWindows, any
    }

    /// Генерирует позиции вдоль стен.
    private func wallAlignedPositions(
        width: Float, depth: Float,
        roomDims: RoomDimensions,
        preferredWall: PreferredWall,
        offsetFromWall: Float
    ) -> [(Float, Float, ARRotation)] {
        var positions: [(Float, Float, ARRotation)] = []
        let rw = roomDims.widthM
        let rd = roomDims.depthM
        let margin = wallMargin + offsetFromWall

        // Стена 1: z = margin (дальняя)
        if rd - margin - depth >= margin {
            let step: Float = 0.5
            var x: Float = margin
            while x + width <= rw - margin {
                positions.append((x, margin, .identity))
                x += step
            }
        }

        // Стена 2: z = rd - margin - depth
        if rd - margin - depth >= margin {
            let step: Float = 0.5
            var x: Float = margin
            while x + width <= rw - margin {
                positions.append((x, rd - margin - depth, ARRotation(pitch: 0, yaw: 180, roll: 0)))
                x += step
            }
        }

        // Стена 3: x = margin (левая)
        if rw - margin - width >= margin {
            let step: Float = 0.5
            var z: Float = margin
            while z + depth <= rd - margin {
                positions.append((margin, z, ARRotation(pitch: 0, yaw: 90, roll: 0)))
                z += step
            }
        }

        // Стена 4: x = rw - margin - width (правая)
        if rw - margin - width >= margin {
            let step: Float = 0.5
            var z: Float = margin
            while z + depth <= rd - margin {
                positions.append((rw - margin - width, z, ARRotation(pitch: 0, yaw: -90, roll: 0)))
                z += step
            }
        }

        return positions
    }

    /// Генерирует позиции в центре комнаты.
    private func centerAlignedPositions(
        width: Float, depth: Float,
        roomDims: RoomDimensions
    ) -> [(Float, Float, ARRotation)] {
        let centerX = (roomDims.widthM - width) / 2
        let centerZ = (roomDims.depthM - depth) / 2

        guard centerX >= wallMargin, centerZ >= wallMargin else { return [] }

        var positions: [(Float, Float, ARRotation)] = []
        positions.append((centerX, centerZ, .identity))

        // Варианты со смещением
        let offset: Float = 0.3
        if centerX - offset >= wallMargin {
            positions.append((centerX - offset, centerZ, .identity))
        }
        if centerZ - offset >= wallMargin {
            positions.append((centerX, centerZ - offset, .identity))
        }

        return positions
    }

    /// Генерирует позиции по периметру (мелкая мебель).
    private func perimeterPositions(
        width: Float, depth: Float,
        roomDims: RoomDimensions,
        offsetFromWall: Float
    ) -> [(Float, Float, ARRotation)] {
        wallAlignedPositions(
            width: width, depth: depth,
            roomDims: roomDims,
            preferredWall: .any,
            offsetFromWall: offsetFromWall
        )
    }

    /// Генерирует угловые позиции.
    private func cornerPositions(
        width: Float, depth: Float,
        roomDims: RoomDimensions,
        offsetFromWall: Float = 0.3
    ) -> [(Float, Float, ARRotation)] {
        let margin = wallMargin + offsetFromWall
        let rw = roomDims.widthM
        let rd = roomDims.depthM

        return [
            (margin, margin, .identity),
            (rw - margin - width, margin, .identity),
            (margin, rd - margin - depth, .identity),
            (rw - margin - width, rd - margin - depth, .identity)
        ]
    }

    // MARK: - Collision Detection

    // swiftlint:disable:next function_parameter_count
    private func rectsOverlap(
        x1: Float, z1: Float, w1: Float, d1: Float,
        x2: Float, z2: Float, w2: Float, d2: Float
    ) -> Bool {
        let margin: Float = minWalkwayWidth / 2 // зазор между предметами

        let overlapX = (x1 - margin) < (x2 + w2 + margin) && (x1 + w1 + margin) > (x2 - margin)
        let overlapZ = (z1 - margin) < (z2 + d2 + margin) && (z1 + d1 + margin) > (z2 - margin)

        return overlapX && overlapZ
    }

    // MARK: - Forbidden Zones

    private func extractForbiddenZones(from room: RoomAnalysis) -> [(x: Float, z: Float, w: Float, d: Float)] {
        var zones: [(x: Float, z: Float, w: Float, d: Float)] = []

        for obj in room.objects {
            let objX = obj.position.x - obj.size.x / 2
            let objZ = obj.position.z - obj.size.z / 2

            switch obj.type {
            case .window:
                // Зона перед окном (не загораживать)
                zones.append((
                    x: objX - windowMargin,
                    z: objZ - windowMargin,
                    w: obj.size.x + 2 * windowMargin,
                    d: obj.size.z + 0.6  // 60см перед окном
                ))
            case .door:
                // Зона открывания двери
                zones.append((
                    x: objX - doorClearance / 2,
                    z: objZ - doorClearance / 2,
                    w: obj.size.x + doorClearance,
                    d: obj.size.z + doorClearance
                ))
            case .radiator:
                // Не ставить вплотную к батарее
                zones.append((
                    x: objX - 0.15,
                    z: objZ - 0.15,
                    w: obj.size.x + 0.3,
                    d: obj.size.z + 0.3
                ))
            default:
                break
            }
        }

        return zones
    }

    // MARK: - Rotation

    private func bestRotationForCategory(_ category: String, roomDims: RoomDimensions) -> ARRotation {
        // Предметы-фасады (диваны, шкафы) разворачиваем лицом в комнату
        switch category {
        case "sofa", "cabinet", "shelf", "bed":
            // Будет определено при размещении
            return .identity
        default:
            return .identity
        }
    }

    // MARK: - Scoring

    /// Оценивает удобство прохода: есть ли свободный путь через комнату.
    private func calculateWalkPathScore(
        roomDims: RoomDimensions,
        placements: [FurniturePlacement],
        forbiddenZones: [(x: Float, z: Float, w: Float, d: Float)]
    ) -> Float {
        // Упрощённая оценка: считаем свободную ширину в середине комнаты
        let midZ = roomDims.depthM / 2
        var occupiedXIntervals: [(Float, Float)] = []

        for p in placements {
            let pX = p.position.x
            let pZ = p.position.z
            let pW = p.sizeM.width
            let pD = p.sizeM.depth

            // Если предмет пересекает среднюю линию по Z
            if pZ <= midZ && (pZ + pD) >= midZ {
                occupiedXIntervals.append((pX, pX + pW))
            }
        }

        // Сортируем интервалы и считаем занятую ширину
        guard !occupiedXIntervals.isEmpty else { return 1.0 }

        occupiedXIntervals.sort { $0.0 < $1.0 }
        var totalOccupiedWidth: Float = 0
        var currentStart = occupiedXIntervals[0].0
        var currentEnd = occupiedXIntervals[0].1

        for interval in occupiedXIntervals.dropFirst() {
            if interval.0 <= currentEnd + minWalkwayWidth {
                currentEnd = max(currentEnd, interval.1)
            } else {
                totalOccupiedWidth += currentEnd - currentStart
                currentStart = interval.0
                currentEnd = interval.1
            }
        }
        totalOccupiedWidth += currentEnd - currentStart

        let freeWidth = roomDims.widthM - totalOccupiedWidth
        let walkPathRatio = freeWidth / roomDims.widthM
        let hasMinWalkway = freeWidth >= minWalkwayWidth

        return hasMinWalkway ? max(0.3, walkPathRatio) : walkPathRatio * 0.5
    }

    /// Оценивает визуальный баланс: равномерность распределения мебели.
    private func calculateVisualBalanceScore(
        roomDims: RoomDimensions,
        placements: [FurniturePlacement]
    ) -> Float {
        guard !placements.isEmpty else { return 1.0 }

        let centerX = roomDims.widthM / 2
        let centerZ = roomDims.depthM / 2

        // Считаем «центр масс» всей расстановки
        var totalWeight: Float = 0
        var weightedX: Float = 0
        var weightedZ: Float = 0

        for p in placements {
            let area = p.sizeM.width * p.sizeM.depth
            let itemCenterX = p.position.x + p.sizeM.width / 2
            let itemCenterZ = p.position.z + p.sizeM.depth / 2

            weightedX += itemCenterX * area
            weightedZ += itemCenterZ * area
            totalWeight += area
        }

        guard totalWeight > 0 else { return 1.0 }

        let massCenterX = weightedX / totalWeight
        let massCenterZ = weightedZ / totalWeight

        // Отклонение центра масс от геометрического центра
        let deviationX = abs(massCenterX - centerX) / (roomDims.widthM / 2)
        let deviationZ = abs(massCenterZ - centerZ) / (roomDims.depthM / 2)
        let avgDeviation = (deviationX + deviationZ) / 2

        return max(0.0, 1.0 - avgDeviation)
    }

    /// Проверяет, перекрывают ли расставленные предметы окна.
    private func hasWindowBlockage(_ placements: [FurniturePlacement], room: RoomAnalysis) -> Bool {
        let windowObjects = room.objects.filter { $0.type == .window }
        for window in windowObjects {
            let wx = window.position.x - window.size.x / 2
            let wz = window.position.z - window.size.z / 2
            let ww = window.size.x
            let wd = window.size.z + 0.4 // небольшая зона перед окном

            // swiftlint:disable:next for_where
            for p in placements {
                if rectsOverlap(
                    x1: p.position.x, z1: p.position.z,
                    w1: p.sizeM.width, d1: p.sizeM.depth,
                    x2: wx, z2: wz, w2: ww, d2: wd
                ) {
                    return true
                }
            }
        }
        return false
    }
}
