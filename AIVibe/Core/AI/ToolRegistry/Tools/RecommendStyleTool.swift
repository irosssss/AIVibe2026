// AIVibe/Core/AI/ToolRegistry/Tools/RecommendStyleTool.swift
// Stage 2.3: Domain-specific инструмент — рекомендация стиля интерьера.
// Blueprint §6: recommend_style — анализирует комнату и рекомендует стиль.

import Foundation

// MARK: - Output Types

/// Профиль стиля интерьера.
public struct StyleProfile: Sendable, Equatable, Codable {
    /// Название стиля.
    public let style: InteriorStyle
    /// Уверенность рекомендации (0–1).
    public let confidence: Float
    /// Причина выбора (почему этот стиль подходит).
    public let reasoning: String
    /// Ключевые черты стиля.
    public let traits: [String]
    /// Рекомендуемая цветовая палитра.
    public let colorPalette: ColorPalette
    /// Рекомендуемые материалы.
    public let materials: [String]
    /// Совместимость с ограничениями комнаты (0–1).
    public let roomCompatibilityScore: Float

    public init(
        style: InteriorStyle,
        confidence: Float,
        reasoning: String,
        traits: [String] = [],
        colorPalette: ColorPalette = .neutral,
        materials: [String] = [],
        roomCompatibilityScore: Float = 0.5
    ) {
        self.style = style
        self.confidence = confidence
        self.reasoning = reasoning
        self.traits = traits
        self.colorPalette = colorPalette
        self.materials = materials
        self.roomCompatibilityScore = roomCompatibilityScore
    }
}

public enum InteriorStyle: String, Sendable, Equatable, Codable, CaseIterable {
    case scandinavian
    case modern
    case loft
    case classic
    case minimal
    case japandi
    case boho
    case artDeco = "art_deco"
    case provence
    case eclectic
}

/// Цветовая палитра.
public struct ColorPalette: Sendable, Equatable, Codable {
    /// Основной цвет (HEX).
    public let primary: String
    /// Вторичный цвет (HEX).
    public let secondary: String
    /// Акцентный цвет (HEX).
    public let accent: String
    /// Цвет стен (HEX).
    public let wall: String
    /// Цвет пола (HEX).
    public let floor: String

    public init(primary: String, secondary: String, accent: String, wall: String, floor: String) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.wall = wall
        self.floor = floor
    }

    /// Нейтральная палитра по умолчанию.
    public static let neutral = ColorPalette(
        primary: "#F5F5F0",
        secondary: "#E8E4D9",
        accent: "#A8C4A2",
        wall: "#FAFAFA",
        floor: "#C4A882"
    )
}

/// Ограничения комнаты, влияющие на выбор стиля.
public struct RoomConstraints: Sendable, Equatable, Codable {
    /// Тип освещения.
    public let lighting: LightingType
    /// Форма комнаты.
    public let shape: RoomShape
    /// Назначение комнаты (спальня, гостиная, кухня...).
    public let function: RoomFunction
    /// Площадь (м²).
    public let areaM2: Float
    /// Высота потолков (м).
    public let ceilingHeightM: Float
    /// Есть ли архитектурные особенности (ниши, балки, эркеры).
    public let hasArchitecturalFeatures: Bool

    public init(
        lighting: LightingType = .mixed,
        shape: RoomShape = .rectangle,
        function: RoomFunction = .living,
        areaM2: Float = 20,
        ceilingHeightM: Float = 2.7,
        hasArchitecturalFeatures: Bool = false
    ) {
        self.lighting = lighting
        self.shape = shape
        self.function = function
        self.areaM2 = areaM2
        self.ceilingHeightM = ceilingHeightM
        self.hasArchitecturalFeatures = hasArchitecturalFeatures
    }
}

public enum LightingType: String, Sendable, Equatable, Codable {
    /// Много естественного света (большие окна, южная сторона).
    case bright
    /// Мало естественного света (маленькие окна, северная сторона).
    case dim
    /// Смешанное освещение.
    case mixed
}

public enum RoomShape: String, Sendable, Equatable, Codable {
    case rectangle
    case square
    case lShaped = "l_shaped"
    case openPlan = "open_plan"
    case narrow
}

public enum RoomFunction: String, Sendable, Equatable, Codable {
    case living
    case bedroom
    case kitchen
    case bathroom
    case hallway
    case office
    case children = "children_room"
    case studio
}

// MARK: - Full Recommendation

/// Полный результат рекомендации стиля (Blueprint output_schema).
public struct StyleRecommendation: Sendable, Equatable, Codable {
    /// Основной рекомендованный стиль.
    public let primaryStyle: StyleProfile
    /// Альтернативные стили (отсортированы по confidence).
    public let alternatives: [StyleProfile]
    /// Ограничения комнаты, использованные при анализе.
    public let roomConstraints: RoomConstraints
    /// Ссылки на mood board изображения.
    public let moodBoardRefs: [String]
    /// Временная метка.
    public let recommendedAt: Date

    public init(
        primaryStyle: StyleProfile,
        alternatives: [StyleProfile] = [],
        roomConstraints: RoomConstraints = RoomConstraints(),
        moodBoardRefs: [String] = [],
        recommendedAt: Date = Date()
    ) {
        self.primaryStyle = primaryStyle
        self.alternatives = alternatives
        self.roomConstraints = roomConstraints
        self.moodBoardRefs = moodBoardRefs
        self.recommendedAt = recommendedAt
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

/// Инструмент рекомендации стиля интерьера.
///
/// Blueprint §6:
/// - risk_class: draft
/// - side_effects: none
/// - permission: allow
/// - timeout: 20s
/// - max_result_chars: 3000
public struct RecommendStyleTool: AgentTool {

    // MARK: - AgentTool Conformance

    public let name = "recommend_style"
    public let description = """
    Анализирует параметры комнаты (размеры, освещение, форма, назначение) и
    рекомендует стиль интерьера. Возвращает основной стиль с confidence score,
    альтернативные стили, цветовую палитру, рекомендуемые материалы и ссылки
    на mood board изображения.
    """

    public let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "room_analysis": SchemaProperty(
                type: .string,
                description: "JSON-строка результата analyze_room_scan (RoomAnalysis.toJSON())"
            ),
            "user_preferences": SchemaProperty(
                type: .string,
                description: "Текстовое описание предпочтений пользователя (опционально)"
            ),
            "room_function": SchemaProperty(
                type: .string,
                description: "Назначение комнаты",
                enumValues: RoomFunction.allCases.map(\.rawValue)
            ),
            "budget_range": SchemaProperty(
                type: .object,
                description: "Диапазон бюджета {min: Int, max: Int} (опционально)"
            )
        ],
        required: ["room_analysis"]
    )

    public let riskClass: ToolRiskClass = .draft
    public let timeout: TimeInterval = 20.0
    public let maxResultChars: Int = 3000
    public let sideEffects: ToolSideEffect = .none

    // MARK: - Validation

    public func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        guard let roomAnalysis = arguments["room_analysis"] as? String, !roomAnalysis.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или пуст 'room_analysis' (ожидается JSON строка от analyze_room_scan)"
            )
        }
        return arguments
    }

    // MARK: - Execute

    public func execute(validated: [String: Any]) async throws -> String {
        let roomAnalysisJSON = validated["room_analysis"] as! String
        let userPrefs = validated["user_preferences"] as? String
        let roomFunctionStr = validated["room_function"] as? String

        // Парсим RoomAnalysis из JSON
        let roomAnalysis: RoomAnalysis
        do {
            let data = roomAnalysisJSON.data(using: .utf8)!
            let decoder = JSONDecoder()
            // roomDimensions.decoder не нужен — Codable синтезирован
            roomAnalysis = try decoder.decode(RoomAnalysis.self, from: data)
        } catch {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Некорректный JSON room_analysis: \(error.localizedDescription)"
            )
        }

        // Извлекаем ограничения
        let constraints = extractConstraints(from: roomAnalysis, functionStr: roomFunctionStr)

        // Анализируем и рекомендуем
        let recommendation = recommend(roomAnalysis: roomAnalysis, constraints: constraints, userPrefs: userPrefs)

        return try recommendation.toJSON()
    }

    // MARK: - Constraint Extraction

    private func extractConstraints(from analysis: RoomAnalysis, functionStr: String?) -> RoomConstraints {
        // Определяем освещение по источникам света
        let lighting: LightingType
        let naturalLightCount = analysis.lightSources.filter { $0.type == .window }.count
        let naturalIntensity = analysis.lightSources
            .filter { $0.type == .window }
            .map(\.intensity)
            .reduce(0, +)

        if naturalLightCount >= 2 || naturalIntensity > 1.0 {
            lighting = .bright
        } else if naturalLightCount == 0 {
            lighting = .dim
        } else {
            lighting = .mixed
        }

        // Определяем форму
        let dims = analysis.roomDimensions
        let ratio = dims.widthM / dims.depthM
        let shape: RoomShape
        if ratio > 2.5 || ratio < 0.4 {
            shape = .narrow
        } else if ratio > 0.85 && ratio < 1.15 {
            shape = .square
        } else if analysis.objects.contains(where: { $0.type == .niche }) {
            shape = .lShaped
        } else {
            shape = .rectangle
        }

        // Назначение
        let function = functionStr.flatMap { RoomFunction(rawValue: $0) } ?? .living

        // Архитектурные особенности
        let hasFeatures = analysis.objects.contains {
            $0.type == .niche || $0.type == .column
        }

        return RoomConstraints(
            lighting: lighting,
            shape: shape,
            function: function,
            areaM2: dims.floorAreaM2,
            ceilingHeightM: dims.heightM,
            hasArchitecturalFeatures: hasFeatures
        )
    }

    // MARK: - Recommendation Engine

    private func recommend(
        roomAnalysis: RoomAnalysis,
        constraints: RoomConstraints,
        userPrefs: String?
    ) -> StyleRecommendation {
        // Ранжируем стили по совместимости
        let ranked = InteriorStyle.allCases
            .map { style -> (style: InteriorStyle, score: Float, reasons: [String]) in
                let (score, reasons) = evaluateStyle(style, constraints: constraints, userPrefs: userPrefs)
                return (style, score, reasons)
            }
            .sorted { $0.score > $1.score }

        let primary = ranked.first!
        let primaryProfile = buildStyleProfile(
            style: primary.style,
            confidence: primary.score,
            reasons: primary.reasons,
            constraints: constraints
        )

        let alternatives = ranked.dropFirst().prefix(3).map {
            buildStyleProfile(
                style: $0.style,
                confidence: $0.score,
                reasons: $0.reasons,
                constraints: constraints
            )
        }

        let moodBoardRefs = generateMoodBoardRefs(
            primary: primary.style,
            alternatives: alternatives.map(\.style.style)
        )

        return StyleRecommendation(
            primaryStyle: primaryProfile,
            alternatives: alternatives,
            roomConstraints: constraints,
            moodBoardRefs: moodBoardRefs
        )
    }

    // MARK: - Style Scoring

    /// Оценивает совместимость стиля с ограничениями комнаты.
    /// - Returns: (score 0–1, reasons).
    private func evaluateStyle(
        _ style: InteriorStyle,
        constraints: RoomConstraints,
        userPrefs: String?
    ) -> (Float, [String]) {
        var score: Float = 0.5
        var reasons: [String] = []

        // --- Площадь ---
        switch style {
        case .minimal, .scandinavian, .japandi:
            if constraints.areaM2 < 25 {
                score += 0.15
                reasons.append("Хорошо подходит для небольших пространств (\(Int(constraints.areaM2))м²)")
            } else if constraints.areaM2 > 40 {
                score += 0.05
            }
        case .loft:
            if constraints.areaM2 > 30 && constraints.ceilingHeightM > 2.8 {
                score += 0.20
                reasons.append("Идеален для просторных помещений с высокими потолками")
            } else {
                score -= 0.10
            }
        case .classic:
            if constraints.areaM2 > 25 && constraints.ceilingHeightM > 2.7 {
                score += 0.15
                reasons.append("Классика требует пространства и высоты потолков")
            } else {
                score -= 0.05
            }
        case .artDeco:
            if constraints.areaM2 > 30 {
                score += 0.10
                reasons.append("Ар-деко раскрывается в просторных комнатах")
            } else {
                score -= 0.05
            }
        default:
            break
        }

        // --- Освещение ---
        switch constraints.lighting {
        case .bright:
            switch style {
            case .scandinavian, .japandi:
                score += 0.15
                reasons.append("Скандинавский/японди стиль максимально использует естественный свет")
            case .loft:
                score += 0.10
                reasons.append("Большие окна — характерная черта лофта")
            default:
                break
            }
        case .dim:
            switch style {
            case .minimal, .modern:
                score += 0.10
                reasons.append("Минимализм/модерн хорошо работает с искусственным освещением")
            case .scandinavian:
                score -= 0.10
                reasons.append("Скандинавский стиль предпочитает естественное освещение")
            default:
                break
            }
        case .mixed:
            // neutral
            break
        }

        // --- Форма ---
        switch constraints.shape {
        case .narrow:
            switch style {
            case .minimal, .modern:
                score += 0.10
                reasons.append("Минимализм/модерн визуально расширяет узкие пространства")
            case .classic:
                score -= 0.10
                reasons.append("Классическая симметрия сложна в узких комнатах")
            default:
                break
            }
        case .lShaped:
            switch style {
            case .modern, .loft:
                score += 0.10
                reasons.append("Зонирование — сильная сторона модерна/лофта")
            default:
                break
            }
        case .openPlan:
            switch style {
            case .loft, .modern:
                score += 0.15
                reasons.append("Идеально для открытой планировки")
            default:
                break
            }
        default:
            break
        }

        // --- Назначение ---
        switch (style, constraints.function) {
        case (.scandinavian, .living), (.scandinavian, .bedroom), (.scandinavian, .children):
            score += 0.10
            reasons.append("Скандинавский стиль универсален для жилых комнат")
        case (.minimal, .office), (.minimal, .studio):
            score += 0.15
            reasons.append("Минимализм способствует концентрации")
        case (.loft, .living), (.loft, .studio):
            score += 0.10
            reasons.append("Лофт отлично подходит для гостиных и студий")
        case (.classic, .living), (.classic, .bedroom):
            score += 0.10
            reasons.append("Классика создаёт уют в гостиной/спальне")
        case (.provence, .kitchen), (.provence, .bedroom):
            score += 0.10
            reasons.append("Прованс идеален для кухонь и спален")
        default:
            break
        }

        // --- Пользовательские предпочтения ---
        if let prefs = userPrefs?.lowercased() {
            for keyword in styleKeywords(style) {
                if prefs.contains(keyword.lowercased()) {
                    score += 0.15
                    reasons.append("Соответствует вашим предпочтениям: '\(keyword)'")
                    break
                }
            }
            // Негативные предпочтения
            let negativeWords = ["тёмный", "мрачный", "холодный", "скучный", "старый"]
            for neg in negativeWords {
                if prefs.contains(neg) {
                    // Не штрафуем — просто не добавляем баллы
                    break
                }
            }
        }

        // --- Архитектурные особенности ---
        if constraints.hasArchitecturalFeatures {
            switch style {
            case .loft:
                score += 0.10
                reasons.append("Архитектурные особенности (ниши, балки) — изюминка лофта")
            case .minimal:
                score -= 0.05
                reasons.append("Ниши и балки усложняют минималистичный дизайн")
            default:
                break
            }
        }

        // Нормализация
        score = min(max(score, 0.0), 1.0)

        return (score, reasons)
    }

    // MARK: - Style Profile Builder

    private func buildStyleProfile(
        style: InteriorStyle,
        confidence: Float,
        reasons: [String],
        constraints: RoomConstraints
    ) -> StyleProfile {
        let traits = styleTraits(style)
        let palette = paletteForStyle(style, lighting: constraints.lighting)
        let materials = materialsForStyle(style)

        return StyleProfile(
            style: style,
            confidence: confidence,
            reasoning: reasons.joined(separator: "; "),
            traits: traits,
            colorPalette: palette,
            materials: materials,
            roomCompatibilityScore: confidence
        )
    }

    // MARK: - Style Data

    private func styleTraits(_ style: InteriorStyle) -> [String] {
        switch style {
        case .scandinavian:
            return ["светлые тона", "натуральные материалы", "функциональность", "минимализм", "уют (хюгге)"]
        case .modern:
            return ["чистые линии", "нейтральная палитра", "стекло и металл", "открытое пространство", "технологичность"]
        case .loft:
            return ["открытая планировка", "кирпич/бетон", "индустриальные элементы", "высокие потолки", "металлические акценты"]
        case .classic:
            return ["симметрия", "натуральное дерево", "лепнина", "тёплые тона", "текстиль"]
        case .minimal:
            return ["монохромность", "пустое пространство", "скрытое хранение", "геометрия", "отсутствие декора"]
        case .japandi:
            return ["японский минимализм", "природные текстуры", "низкая мебель", "асимметрия", "тёплый минимализм"]
        case .boho:
            return ["яркие акценты", "растения", "смешение текстур", "этнические мотивы", "уютный беспорядок"]
        case .artDeco:
            return ["геометрические узоры", "латунь/золото", "бархат", "тёмные тона", "роскошь"]
        case .provence:
            return ["пастельные тона", "состаренное дерево", "цветочные мотивы", "лён", "деревенский шарм"]
        case .eclectic:
            return ["смешение стилей", "винтаж + современность", "индивидуальность", "коллекционирование", "неожиданные сочетания"]
        }
    }

    private func paletteForStyle(_ style: InteriorStyle, lighting: LightingType) -> ColorPalette {
        let brightness: Float = lighting == .dim ? 1.15 : 1.0

        switch style {
        case .scandinavian:
            return ColorPalette(
                primary: "#F5F5F0", secondary: "#E8E4D9", accent: "#A8C4A2",
                wall: "#FAFAFA", floor: "#E6D5B8"
            )
        case .modern:
            return ColorPalette(
                primary: "#E0E0E0", secondary: "#9E9E9E", accent: "#424242",
                wall: "#F5F5F5", floor: "#8D6E63"
            )
        case .loft:
            return ColorPalette(
                primary: "#B0B0B0", secondary: "#8B4513", accent: "#2C2C2C",
                wall: "#D3D3D3", floor: "#4A3728"
            )
        case .classic:
            return ColorPalette(
                primary: "#F5E6D3", secondary: "#C8A96E", accent: "#8B6914",
                wall: "#FFF8DC", floor: "#6B4226"
            )
        case .minimal:
            return ColorPalette(
                primary: "#FFFFFF", secondary: "#E0E0E0", accent: "#333333",
                wall: "#FAFAFA", floor: "#9E9E9E"
            )
        case .japandi:
            return ColorPalette(
                primary: "#D4C5B9", secondary: "#8B7D6B", accent: "#556B2F",
                wall: "#F5F0EB", floor: "#A0896E"
            )
        case .boho:
            return ColorPalette(
                primary: "#FFF8E7", secondary: "#E8A87C", accent: "#6B8E6B",
                wall: "#FFF5E1", floor: "#C4A882"
            )
        case .artDeco:
            return ColorPalette(
                primary: "#2C2C2C", secondary: "#D4AF37", accent: "#1A1A2E",
                wall: "#E8E0D5", floor: "#2C1810"
            )
        case .provence:
            return ColorPalette(
                primary: "#E8D5C4", secondary: "#C8B8A8", accent: "#B8C8D8",
                wall: "#F5EBE0", floor: "#C4A882"
            )
        case .eclectic:
            return ColorPalette(
                primary: "#F0E6D3", secondary: "#A8C8A8", accent: "#C84040",
                wall: "#F5F0E8", floor: "#8B7355"
            )
        }
    }

    private func materialsForStyle(_ style: InteriorStyle) -> [String] {
        switch style {
        case .scandinavian:
            return ["светлое дерево (бук, берёза)", "лён", "шерсть", "керамика", "стекло"]
        case .modern:
            return ["стекло", "хромированный металл", "лакированное дерево", "кожа", "бетон"]
        case .loft:
            return ["необработанный кирпич", "бетон", "металл", "состаренное дерево", "стекло"]
        case .classic:
            return ["массив дерева", "мрамор", "бархат", "латунь", "хрусталь"]
        case .minimal:
            return ["бетон", "стекло", "матовый пластик", "микроцемент", "нержавеющая сталь"]
        case .japandi:
            return ["тёмное дерево", "бумага васи", "керамика ручной работы", "ротанг", "камень"]
        case .boho:
            return ["макраме", "ротанг", "хлопок", "дерево", "керамика ручной работы"]
        case .artDeco:
            return ["бархат", "латунь", "мрамор", "лакированное дерево", "зеркала"]
        case .provence:
            return ["состаренное дерево", "лён", "кованое железо", "керамика", "хлопок"]
        case .eclectic:
            return ["смешанные текстуры", "винтажное дерево", "ковры ручной работы", "латунь", "стекло"]
        }
    }

    private func styleKeywords(_ style: InteriorStyle) -> [String] {
        switch style {
        case .scandinavian: return ["светлый", "уютный", "hygge", "хюгге", "сканди", "скандинавский", "природный"]
        case .modern:       return ["современный", "технологичный", "модерн", "городской", "стильный"]
        case .loft:         return ["лофт", "индустриальный", "кирпич", "бетон", "просторный"]
        case .classic:      return ["классический", "элегантный", "традиционный", "роскошный", "изысканный"]
        case .minimal:      return ["минимализм", "простой", "чистый", "японский", "пустой"]
        case .japandi:      return ["японди", "японский", "дзен", "тёплый", "аскетичный"]
        case .boho:         return ["бохо", "богемный", "яркий", "творческий", "растения"]
        case .artDeco:      return ["ар-деко", "арт-деко", "роскошный", "золото", "геометрия"]
        case .provence:     return ["прованс", "деревенский", "французский", "уютный", "пастельный"]
        case .eclectic:     return ["эклектика", "смешанный", "винтаж", "коллекция", "индивидуальный"]
        }
    }

    private func generateMoodBoardRefs(primary: InteriorStyle, alternatives: [InteriorStyle]) -> [String] {
        var refs: [String] = []
        refs.append("style://moodboard/\(primary.rawValue)/01")
        refs.append("style://moodboard/\(primary.rawValue)/02")
        for alt in alternatives.prefix(2) {
            refs.append("style://moodboard/\(alt.rawValue)/01")
        }
        return refs
    }
}

// MARK: - RoomFunction AllCases

extension RoomFunction: CaseIterable {}