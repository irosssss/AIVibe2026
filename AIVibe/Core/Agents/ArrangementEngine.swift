// AIVibe/Core/Agents/ArrangementEngine.swift
// A2: детерминированный движок расстановки мебели — жадная минимизация стоимости.
//
// Метод: Kán & Kaufmann «Automatic Furniture Arrangement Using Greedy Cost
// Minimization» (IEEE VR 2018); парные правила (диван↔журнальный стол,
// кровать↔тумбочки, диван↔ТВ) — из Yu et al. «Make It Home» (SIGGRAPH 2011).
// Нормы проходов и зазоров — из DesignNorms (единый источник истины).
//
// Зачем: раньше координаты придумывала LLM (медленно, платно, недетерминированно,
// коллизии). Теперь LLM отдаёт только СПИСОК мебели, а позиции считает этот движок:
// мгновенно, бесплатно, одинаково при одинаковом входе.
//
// Система координат: позиция = ЦЕНТР предмета, метры, начало — угол комнаты
// (конвенция FurnitureItem / CollisionService). Никаких «углов предмета» —
// ловушка рассинхрона угол/центр из аудита A2.1 исключена by design.

import Foundation
import simd

// MARK: - Результат работы движка

public struct ArrangementEngineResult: Sendable, Equatable {
    /// Размещённые предметы (позиция-центр + поворот вокруг Y, градусы).
    public let placedItems: [FurnitureItem]
    /// Предметы, для которых не нашлось места (комната переполнена).
    public let unplacedItems: [FurnitureItem]
    /// Предупреждения для пользователя (рус.).
    public let warnings: [String]

    public init(placedItems: [FurnitureItem], unplacedItems: [FurnitureItem], warnings: [String]) {
        self.placedItems = placedItems
        self.unplacedItems = unplacedItems
        self.warnings = warnings
    }
}

// MARK: - Категории мебели (нормализация типов от LLM, RU/EN)

enum ArrangementCategory: Equatable {
    case sofa, armchair, chair, table, coffeeTable, tvStand
    case bed, nightstand, wardrobe, shelf, lamp, rug, decor, other

    /// Распознаёт категорию по itemType от LLM («диван», "sofa", «тумба под ТВ»...).
    /// Порядок проверок важен: частные случаи раньше общих («журнальный» раньше «стол»).
    static func from(_ itemType: String) -> ArrangementCategory {
        let t = itemType.lowercased()
        if t.contains("журнальн") || t.contains("кофейн") || t.contains("coffee") { return .coffeeTable }
        if t.contains("прикроват") || t.contains("тумбочк") || t.contains("nightstand") { return .nightstand }
        if t.contains("тв") || t.contains("tv") || t.contains("телевизор") { return .tvStand }
        if t.contains("кресло") || t.contains("armchair") { return .armchair }
        if t.contains("стул") || t.contains("chair") { return .chair }
        if t.contains("стол") || t.contains("table") || t.contains("desk") { return .table }
        if t.contains("диван") || t.contains("sofa") || t.contains("couch") { return .sofa }
        if t.contains("кровать") || t.contains("bed") { return .bed }
        if t.contains("шкаф") || t.contains("комод") || t.contains("wardrobe")
            || t.contains("cabinet") || t.contains("dresser") || t.contains("тумба") { return .wardrobe }
        if t.contains("полк") || t.contains("стеллаж") || t.contains("shelf") || t.contains("bookcase") { return .shelf }
        if t.contains("ламп") || t.contains("торшер") || t.contains("светильник") || t.contains("lamp") { return .lamp }
        if t.contains("ковёр") || t.contains("ковер") || t.contains("rug") || t.contains("carpet") { return .rug }
        if t.contains("декор") || t.contains("растени") || t.contains("картин")
            || t.contains("decor") || t.contains("plant") { return .decor }
        return .other
    }

    /// Тяготеет к стене (спинкой/задней стенкой к стене).
    var prefersWall: Bool {
        switch self {
        case .sofa, .bed, .wardrobe, .shelf, .tvStand, .nightstand: return true
        case .armchair, .chair, .table, .coffeeTable, .lamp, .rug, .decor, .other: return false
        }
    }

    /// Тяготеет к центру комнаты.
    var prefersCenter: Bool {
        switch self {
        case .table, .coffeeTable, .rug: return true
        default: return false
        }
    }

    /// Порядок расстановки: якоря (кровать, диван, шкаф) — первыми,
    /// зависимая мелочь (тумбочки, стулья, лампы) — после своих якорей.
    var placementPriority: Int {
        switch self {
        case .bed: return 0
        case .sofa: return 1
        case .wardrobe: return 2
        case .table: return 3
        case .tvStand: return 4
        case .shelf: return 5
        case .rug: return 6
        case .coffeeTable: return 7
        case .armchair: return 8
        case .nightstand: return 9
        case .chair: return 10
        case .lamp: return 11
        case .decor: return 12
        case .other: return 13
        }
    }
}

// MARK: - Границы пола комнаты

/// Прямоугольник пола в координатах сцены (по стенам скана; фолбэк — квадрат из площади).
public struct FloorBounds: Sendable, Equatable {
    public let minX: Float
    public let minZ: Float
    public let maxX: Float
    public let maxZ: Float

    public var width: Float { maxX - minX }
    public var depth: Float { maxZ - minZ }
    public var centerX: Float { (minX + maxX) / 2 }
    public var centerZ: Float { (minZ + maxZ) / 2 }
}

extension RoomGeometry {
    /// Границы пола: bbox по стенам скана; если стен нет (ручной ввод) —
    /// квадрат со стороной √площади от начала координат.
    public var floorBounds: FloorBounds {
        guard !walls.isEmpty else {
            let side = Float(area.squareRoot())
            return FloorBounds(minX: 0, minZ: 0, maxX: side, maxZ: side)
        }
        var minX = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for wall in walls {
            minX = min(minX, wall.start.x, wall.end.x)
            maxX = max(maxX, wall.start.x, wall.end.x)
            minZ = min(minZ, wall.start.z, wall.end.z)
            maxZ = max(maxZ, wall.start.z, wall.end.z)
        }
        return FloorBounds(minX: minX, minZ: minZ, maxX: maxX, maxZ: maxZ)
    }
}

// MARK: - Движок

public struct ArrangementEngine: Sendable {

    // Нормы (см → м) — только из DesignNorms, не хардкодить.
    private let wallGap = Float(DesignNorms.furnitureToWallCm) / 100
    private let minPassage = Float(DesignNorms.minPassageCm) / 100
    private let doorClearance = Float(DesignNorms.doorClearanceFrontCm) / 100
    /// Жёсткий минимальный зазор между предметами (синхронизирован с CollisionDetector.minGap).
    private let hardGap: Float = 0.05
    /// Шаг сетки кандидатов вдоль стен и по центру (м).
    private let gridStep: Float = 0.25

    public init() {}

    /// Расставляет предметы в комнате. Детерминированно: одинаковый вход → одинаковый выход.
    public func arrange(items: [FurnitureItem], room: RoomGeometry) -> ArrangementEngineResult {
        let bounds = room.floorBounds
        let doorCenters = room.doors.map { SIMD2<Float>($0.position.x, $0.position.z) }
        let windowZones = windowFrontZones(room: room)

        // Якоря первыми; при равенстве — крупные раньше; финальный тай-брейк
        // по исходному индексу (стабильность и детерминизм).
        let ordered = items.enumerated().sorted { a, b in
            let catA = ArrangementCategory.from(a.element.itemType)
            let catB = ArrangementCategory.from(b.element.itemType)
            if catA.placementPriority != catB.placementPriority {
                return catA.placementPriority < catB.placementPriority
            }
            let areaA = a.element.size.x * a.element.size.z
            let areaB = b.element.size.x * b.element.size.z
            if areaA != areaB { return areaA > areaB }
            return a.offset < b.offset
        }.map(\.element)

        var placed: [PlacedItem] = []
        var unplaced: [FurnitureItem] = []

        for item in ordered {
            let category = ArrangementCategory.from(item.itemType)
            if let best = bestPlacement(
                for: item, category: category, bounds: bounds,
                placed: placed, doorCenters: doorCenters, windowZones: windowZones
            ) {
                placed.append(best)
            } else {
                unplaced.append(item)
            }
        }

        // A2.5 — доводка отжигом (Metropolis, фиксированное зерно: детерминизм сохранён).
        // Гарантия: итог не хуже жадного решения — лучшее состояние отслеживается явно.
        var refined = anneal(initial: placed, bounds: bounds, doorCenters: doorCenters, windowZones: windowZones)

        // Повторная укладка непоместившегося: отжиг мог уплотнить расстановку и освободить место.
        let reseat = reseatUnplaced(unplaced, into: refined, bounds: bounds, doorCenters: doorCenters, windowZones: windowZones)
        refined = reseat.placed
        let finalUnplaced = reseat.unplaced

        // Выравнивание журнального стола и ТВ по оси взгляда дивана (эстетика «зоны отдыха»).
        refined = alignToSofaAxis(refined, bounds: bounds, doorCenters: doorCenters, windowZones: windowZones)

        var warnings: [String] = []
        for item in finalUnplaced {
            warnings.append("«\(item.itemType)» не поместился — комната переполнена")
        }
        if occupiedShare(placed: refined, bounds: bounds) > 0.6 {
            warnings.append("Мебель занимает более 60% пола — комната может казаться загромождённой")
        }
        return ArrangementEngineResult(
            placedItems: refined.map { $0.toFurnitureItem() },
            unplacedItems: finalUnplaced,
            warnings: warnings
        )
    }
}

// MARK: - Внутренние типы

/// Размещённый предмет: центр, поворот и фактический след на полу (с учётом поворота).
private struct PlacedItem {
    let item: FurnitureItem
    let category: ArrangementCategory
    let centerX: Float
    let centerZ: Float
    let rotation: Float
    /// След на полу после поворота: ширина по X и глубина по Z.
    let footW: Float
    let footD: Float

    func toFurnitureItem() -> FurnitureItem {
        FurnitureItem(
            id: item.id,
            itemType: item.itemType,
            brand: item.brand,
            article: item.article,
            position: SIMD3<Float>(centerX, item.position.y, centerZ),
            rotation: rotation,
            size: item.size,
            usdzURL: item.usdzURL,
            price: item.price
        )
    }
}

/// Прямоугольная зона на полу (центр + полуразмеры).
private struct FloorZone {
    let centerX: Float
    let centerZ: Float
    let halfW: Float
    let halfD: Float

    func overlaps(centerX cx: Float, centerZ cz: Float, halfW hw: Float, halfD hd: Float) -> Bool {
        abs(centerX - cx) < halfW + hw && abs(centerZ - cz) < halfD + hd
    }
}

/// Кандидат позиции: центр + поворот + след.
private struct Candidate {
    let centerX: Float
    let centerZ: Float
    let rotation: Float
    let footW: Float
    let footD: Float
}

// MARK: - Запретные зоны

extension ArrangementEngine {

    /// Зоны перед окнами: высокой мебели здесь не место (перекрывает свет).
    private func windowFrontZones(room: RoomGeometry) -> [(zone: FloorZone, sillHeight: Float)] {
        room.windows.map { window in
            let halfW = Float(window.width) / 2 + 0.15
            let zone = FloorZone(
                centerX: window.position.x,
                centerZ: window.position.z,
                halfW: halfW,
                halfD: halfW
            )
            return (zone, Float(window.sillHeight))
        }
    }
}

// MARK: - Поиск лучшей позиции (жадная минимизация стоимости)

extension ArrangementEngine {

    private func bestPlacement(
        for item: FurnitureItem,
        category: ArrangementCategory,
        bounds: FloorBounds,
        placed: [PlacedItem],
        doorCenters: [SIMD2<Float>],
        windowZones: [(zone: FloorZone, sillHeight: Float)]
    ) -> PlacedItem? {
        let candidates = generateCandidates(for: item, category: category, bounds: bounds)

        var best: Candidate?
        var bestCost = Float.greatestFiniteMagnitude

        for candidate in candidates {
            guard isFeasible(
                candidate, item: item, bounds: bounds, placed: placed,
                doorCenters: doorCenters, windowZones: windowZones
            ) else { continue }

            let cost = placementCost(candidate, item: item, category: category, bounds: bounds, placed: placed)
            // Строго «меньше» — при равенстве выигрывает первый кандидат (детерминизм).
            if cost < bestCost {
                bestCost = cost
                best = candidate
            }
        }

        guard let best else { return nil }
        return PlacedItem(
            item: item,
            category: category,
            centerX: best.centerX,
            centerZ: best.centerZ,
            rotation: best.rotation,
            footW: best.footW,
            footD: best.footD
        )
    }

    /// Кандидаты: у стен (4 стены, спинкой к стене, лицом в комнату) и/или
    /// сетка по внутренней области. Порядок генерации фиксирован — детерминизм.
    private func generateCandidates(
        for item: FurnitureItem,
        category: ArrangementCategory,
        bounds: FloorBounds
    ) -> [Candidate] {
        let w = item.size.x
        let d = item.size.z
        var result: [Candidate] = []

        if category.prefersWall || !category.prefersCenter {
            result += wallCandidates(footW: w, footD: d, bounds: bounds)
        }
        if category.prefersCenter || !category.prefersWall {
            result += interiorCandidates(footW: w, footD: d, bounds: bounds)
        }
        return result
    }

    /// Позиции вдоль четырёх стен. Поворот разворачивает предмет лицом в комнату;
    /// у боковых стен след предмета меняется местами (w↔d).
    private func wallCandidates(footW w: Float, footD d: Float, bounds: FloorBounds) -> [Candidate] {
        var result: [Candidate] = []

        // Дальняя стена (z = minZ), лицом на +Z: rotation 0.
        var x = bounds.minX + wallGap + w / 2
        while x + w / 2 <= bounds.maxX - wallGap {
            result.append(Candidate(
                centerX: x, centerZ: bounds.minZ + wallGap + d / 2,
                rotation: 0, footW: w, footD: d
            ))
            x += gridStep
        }
        // Ближняя стена (z = maxZ), лицом на −Z: rotation 180.
        x = bounds.minX + wallGap + w / 2
        while x + w / 2 <= bounds.maxX - wallGap {
            result.append(Candidate(
                centerX: x, centerZ: bounds.maxZ - wallGap - d / 2,
                rotation: 180, footW: w, footD: d
            ))
            x += gridStep
        }
        // Левая стена (x = minX), лицом на +X: rotation 90, след повёрнут.
        var z = bounds.minZ + wallGap + w / 2
        while z + w / 2 <= bounds.maxZ - wallGap {
            result.append(Candidate(
                centerX: bounds.minX + wallGap + d / 2, centerZ: z,
                rotation: 90, footW: d, footD: w
            ))
            z += gridStep
        }
        // Правая стена (x = maxX), лицом на −X: rotation 270.
        z = bounds.minZ + wallGap + w / 2
        while z + w / 2 <= bounds.maxZ - wallGap {
            result.append(Candidate(
                centerX: bounds.maxX - wallGap - d / 2, centerZ: z,
                rotation: 270, footW: d, footD: w
            ))
            z += gridStep
        }
        return result
    }

    /// Сетка по внутренней области (для столов, ковров и фолбэка), повороты 0/90.
    private func interiorCandidates(footW w: Float, footD d: Float, bounds: FloorBounds) -> [Candidate] {
        var result: [Candidate] = []
        for (fw, fd, rot) in [(w, d, Float(0)), (d, w, Float(90))] {
            var x = bounds.minX + wallGap + fw / 2
            while x + fw / 2 <= bounds.maxX - wallGap {
                var z = bounds.minZ + wallGap + fd / 2
                while z + fd / 2 <= bounds.maxZ - wallGap {
                    result.append(Candidate(centerX: x, centerZ: z, rotation: rot, footW: fw, footD: fd))
                    z += gridStep
                }
                x += gridStep
            }
        }
        return result
    }

    /// Жёсткие ограничения: границы, пересечения, зоны дверей, окна для высокой мебели.
    private func isFeasible(
        _ c: Candidate,
        item: FurnitureItem,
        bounds: FloorBounds,
        placed: [PlacedItem],
        doorCenters: [SIMD2<Float>],
        windowZones: [(zone: FloorZone, sillHeight: Float)]
    ) -> Bool {
        let hw = c.footW / 2
        let hd = c.footD / 2

        // Внутри комнаты (зазор от стены — норматив).
        if c.centerX - hw < bounds.minX + wallGap - 0.001 { return false }
        if c.centerX + hw > bounds.maxX - wallGap + 0.001 { return false }
        if c.centerZ - hd < bounds.minZ + wallGap - 0.001 { return false }
        if c.centerZ + hd > bounds.maxZ - wallGap + 0.001 { return false }

        // Пересечения с размещёнными (жёсткий зазор; ковёр — исключение, по нему ходят и ставят).
        let isRug = ArrangementCategory.from(item.itemType) == .rug
        if !isRug {
            for p in placed where p.category != .rug {
                let gapNeeded = hardGap
                if abs(c.centerX - p.centerX) < hw + p.footW / 2 + gapNeeded &&
                    abs(c.centerZ - p.centerZ) < hd + p.footD / 2 + gapNeeded {
                    return false
                }
            }
        }

        // Зоны дверей — всегда свободны (путь эвакуации). Радиальный критерий,
        // синхронизирован с CollisionDetector: радиус = норматив + полуразмер предмета.
        let doorRadius = doorClearance + max(c.footW, c.footD) / 2
        for door in doorCenters {
            let dx = c.centerX - door.x
            let dz = c.centerZ - door.y
            if (dx * dx + dz * dz).squareRoot() < doorRadius { return false }
        }

        // Перед окном — только мебель ниже подоконника.
        for (zone, sill) in windowZones where item.size.y > sill {
            if zone.overlaps(centerX: c.centerX, centerZ: c.centerZ, halfW: hw, halfD: hd) {
                return false
            }
        }
        return true
    }
}

// MARK: - Функция стоимости

extension ArrangementEngine {

    /// Суммарная стоимость кандидата: предпочтения категории + парные правила + проходы.
    /// Меньше — лучше. Веса подобраны по Kán & Kaufmann (§4.2) с упрощением.
    private func placementCost(
        _ c: Candidate,
        item: FurnitureItem,
        category: ArrangementCategory,
        bounds: FloorBounds,
        placed: [PlacedItem]
    ) -> Float {
        var cost: Float = 0

        // Предпочтение стены: расстояние до ближайшей стены.
        if category.prefersWall {
            let distToWall = min(
                c.centerX - c.footW / 2 - bounds.minX,
                bounds.maxX - (c.centerX + c.footW / 2),
                c.centerZ - c.footD / 2 - bounds.minZ,
                bounds.maxZ - (c.centerZ + c.footD / 2)
            )
            cost += distToWall * 2.0
        }

        // Предпочтение центра.
        if category.prefersCenter {
            let dx = c.centerX - bounds.centerX
            let dz = c.centerZ - bounds.centerZ
            cost += (dx * dx + dz * dz).squareRoot() * 1.0
        }

        cost += pairwiseCost(c, category: category, placed: placed)
        cost += passageCost(c, category: category, placed: placed)
        return cost
    }

    /// Парные правила (Make It Home): зависимый предмет тянется к своему якорю.
    private func pairwiseCost(_ c: Candidate, category: ArrangementCategory, placed: [PlacedItem]) -> Float {
        func distanceTo(_ anchor: ArrangementCategory) -> Float? {
            let anchors = placed.filter { $0.category == anchor }
            guard !anchors.isEmpty else { return nil }
            return anchors.map { p in
                let dx = c.centerX - p.centerX
                let dz = c.centerZ - p.centerZ
                return (dx * dx + dz * dz).squareRoot()
            }.min()
        }

        var cost: Float = 0
        switch category {
        case .coffeeTable:
            // Журнальный стол — перед диваном (~0.45 м между краями ≈ 1.2 м между центрами).
            if let d = distanceTo(.sofa) { cost += abs(d - 1.2) * 3.0 }
        case .tvStand:
            // ТВ — напротив дивана, комфортная дистанция просмотра ~2.7 м.
            if let d = distanceTo(.sofa) { cost += abs(d - 2.7) * 2.0 }
        case .nightstand:
            // Тумбочка — вплотную к кровати (~1.1 м между центрами для кровати 160 см).
            if let d = distanceTo(.bed) { cost += abs(d - 1.1) * 5.0 }
        case .chair, .armchair:
            // Стулья и кресла — у стола (дальше 0.9 м — штраф).
            if let d = distanceTo(.table) { cost += max(0, d - 0.9) * 2.0 }
        case .lamp:
            // Торшер — рядом с диваном или креслом.
            if let d = distanceTo(.sofa) ?? distanceTo(.armchair) { cost += abs(d - 0.8) * 1.0 }
        case .rug:
            // Ковёр — под зоной дивана.
            if let d = distanceTo(.sofa) { cost += abs(d - 1.0) * 1.0 }
        default:
            break
        }
        return cost
    }

    /// Штраф за тесноту: зазор до соседа меньше норматива прохода — мягкий штраф
    /// (жёсткий минимум hardGap уже гарантирован в isFeasible).
    private func passageCost(_ c: Candidate, category: ArrangementCategory, placed: [PlacedItem]) -> Float {
        guard category != .rug else { return 0 }
        var cost: Float = 0
        for p in placed where p.category != .rug {
            let gapX = abs(c.centerX - p.centerX) - (c.footW + p.footW) / 2
            let gapZ = abs(c.centerZ - p.centerZ) - (c.footD + p.footD) / 2
            let gap = max(gapX, gapZ)
            // Зависимая мелочь стоит вплотную к якорю осознанно — без штрафа.
            let isPair = (category == .nightstand && p.category == .bed)
                || (category == .coffeeTable && p.category == .sofa)
                || (category == .chair && p.category == .table)
                || (category == .armchair && p.category == .table)
            if !isPair && gap < minPassage {
                cost += (minPassage - gap) * 4.0
            }
        }
        return cost
    }

    /// Доля занятой площади пола (для предупреждения о загромождённости).
    private func occupiedShare(placed: [PlacedItem], bounds: FloorBounds) -> Float {
        let floorArea = bounds.width * bounds.depth
        guard floorArea > 0 else { return 0 }
        let occupied = placed
            .filter { $0.category != .rug }
            .reduce(Float(0)) { $0 + $1.footW * $1.footD }
        return occupied / floorArea
    }
}

// MARK: - Детерминированный ГПСЧ (SplitMix64)

/// Быстрый воспроизводимый генератор. Зерно фиксировано в движке → один вход даёт
/// один выход (требование детерминизма A2). Не для криптографии.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextU64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Равномерно в [0, 1).
    mutating func unit() -> Double {
        Double(nextU64() >> 11) * (1.0 / Double(1 << 53))
    }

    /// Равномерный индекс в [0, count).
    mutating func index(below count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(nextU64() % UInt64(count))
    }
}

// MARK: - Переходы между размещениями (для отжига и выравнивания)

extension PlacedItem {
    /// Тот же предмет на месте кандидата (центр + поворот + след).
    func moved(to c: Candidate) -> PlacedItem {
        PlacedItem(
            item: item, category: category,
            centerX: c.centerX, centerZ: c.centerZ, rotation: c.rotation,
            footW: c.footW, footD: c.footD
        )
    }

    /// Тот же предмет со смещённым центром (поворот и след без изменений).
    func withCenter(x: Float, z: Float) -> PlacedItem {
        PlacedItem(
            item: item, category: category,
            centerX: x, centerZ: z, rotation: rotation,
            footW: footW, footD: footD
        )
    }

    /// Представление текущего размещения как кандидата (для проверок и стоимости).
    var asCandidate: Candidate {
        Candidate(centerX: centerX, centerZ: centerZ, rotation: rotation, footW: footW, footD: footD)
    }
}

// MARK: - A2.5: отжиг, повторная укладка, выравнивание по дивану

extension ArrangementEngine {

    /// Суммарная «энергия» расстановки: стоимость каждого предмета относительно
    /// остальных. Минимум — самое гармоничное размещение. Та же функция стоимости,
    /// что и в жадной фазе → отжиг улучшает по той же метрике.
    private func totalEnergy(_ state: [PlacedItem], bounds: FloorBounds) -> Float {
        var energy: Float = 0
        for i in state.indices {
            var others = state
            let p = others.remove(at: i)
            energy += placementCost(
                p.asCandidate, item: p.item, category: p.category, bounds: bounds, placed: others
            )
        }
        return energy
    }

    /// Имитация отжига поверх жадного решения. Случайно переставляет один предмет
    /// в допустимую позицию, принимает ухудшения по критерию Метрополиса (чтобы
    /// выбираться из локальных тупиков жадности), но ВОЗВРАЩАЕТ лучшее найденное
    /// состояние — поэтому результат гарантированно не хуже входного.
    private func anneal(
        initial: [PlacedItem],
        bounds: FloorBounds,
        doorCenters: [SIMD2<Float>],
        windowZones: [(zone: FloorZone, sillHeight: Float)]
    ) -> [PlacedItem] {
        // Меньше двух предметов — переставлять нечего (жадная фаза уже оптимальна).
        guard initial.count >= 2 else { return initial }

        var rng = SplitMix64(seed: 0xA1B2_C3D4_E5F6_0717)
        var current = initial
        var currentEnergy = totalEnergy(current, bounds: bounds)
        var best = current
        var bestEnergy = currentEnergy

        let iterations = min(1200, max(200, current.count * 80))
        var temperature = 1.5
        // Геометрическое охлаждение: к концу прогона T ≈ 0.02 от старта.
        let cooling = pow(0.02, 1.0 / Double(iterations))

        for _ in 0..<iterations {
            defer { temperature *= cooling }

            let i = rng.index(below: current.count)
            let subject = current[i]
            // Ковры не перемешиваем отжигом: они зонируют под мебелью, у них своя логика.
            if subject.category == .rug { continue }

            let candidates = generateCandidates(for: subject.item, category: subject.category, bounds: bounds)
            guard !candidates.isEmpty else { continue }
            let candidate = candidates[rng.index(below: candidates.count)]

            var others = current
            others.remove(at: i)
            guard isFeasible(
                candidate, item: subject.item, bounds: bounds, placed: others,
                doorCenters: doorCenters, windowZones: windowZones
            ) else { continue }

            var trial = current
            trial[i] = subject.moved(to: candidate)
            let trialEnergy = totalEnergy(trial, bounds: bounds)
            let delta = Double(trialEnergy - currentEnergy)

            // Метрополис: улучшение принимаем всегда, ухудшение — с вероятностью exp(−Δ/T).
            if delta <= 0 || rng.unit() < exp(-delta / max(temperature, 1e-6)) {
                current = trial
                currentEnergy = trialEnergy
                if trialEnergy < bestEnergy {
                    best = trial
                    bestEnergy = trialEnergy
                }
            }
        }
        return best
    }

    /// Повторная попытка разместить непоместившиеся предметы в уплотнённой отжигом
    /// расстановке. Порядок входа сохранён → детерминизм.
    private func reseatUnplaced(
        _ unplaced: [FurnitureItem],
        into state: [PlacedItem],
        bounds: FloorBounds,
        doorCenters: [SIMD2<Float>],
        windowZones: [(zone: FloorZone, sillHeight: Float)]
    ) -> (placed: [PlacedItem], unplaced: [FurnitureItem]) {
        var placed = state
        var stillUnplaced: [FurnitureItem] = []
        for item in unplaced {
            let category = ArrangementCategory.from(item.itemType)
            if let best = bestPlacement(
                for: item, category: category, bounds: bounds,
                placed: placed, doorCenters: doorCenters, windowZones: windowZones
            ) {
                placed.append(best)
            } else {
                stillUnplaced.append(item)
            }
        }
        return (placed, stillUnplaced)
    }

    /// Журнальный стол и ТВ-тумбу подравнивает по оси взгляда дивана: их боковую
    /// координату подтягивает к центру дивана, чтобы «зона отдыха» смотрелась по оси.
    /// Снап применяется только если позиция остаётся допустимой.
    private func alignToSofaAxis(
        _ state: [PlacedItem],
        bounds: FloorBounds,
        doorCenters: [SIMD2<Float>],
        windowZones: [(zone: FloorZone, sillHeight: Float)]
    ) -> [PlacedItem] {
        guard let sofa = state.first(where: { $0.category == .sofa }) else { return state }
        var result = state
        for idx in result.indices {
            let p = result[idx]
            guard p.category == .coffeeTable || p.category == .tvStand else { continue }

            // Диван у дальней/ближней стены (поворот 0/180) смотрит вдоль Z → ровняем X;
            // у боковой стены (90/270) смотрит вдоль X → ровняем Z.
            let facesAlongZ = (sofa.rotation == 0 || sofa.rotation == 180)
            let snapped = facesAlongZ
                ? p.withCenter(x: sofa.centerX, z: p.centerZ)
                : p.withCenter(x: p.centerX, z: sofa.centerZ)

            var others = result
            others.remove(at: idx)
            guard isFeasible(
                snapped.asCandidate, item: snapped.item, bounds: bounds, placed: others,
                doorCenters: doorCenters, windowZones: windowZones
            ) else { continue }
            result[idx] = snapped
        }
        return result
    }
}
