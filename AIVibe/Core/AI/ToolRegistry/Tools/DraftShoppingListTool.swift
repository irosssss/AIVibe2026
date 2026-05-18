// AIVibe/Core/AI/ToolRegistry/Tools/DraftShoppingListTool.swift
// Stage 2.5: Domain-specific инструмент — формирование списка покупок.
// Blueprint §6: draft_shopping_list — список покупок со ссылками и итоговой ценой.
// Risk class: draft, no side effects, approval-gated split (confirm_purchase_order — DENY в MVP).

import Foundation

// MARK: - Output Types

/// Одна позиция в списке покупок (Blueprint: items).
public struct ShoppingListItem: Sendable, Equatable, Codable {
    /// Название товара.
    public let name: String
    /// URL товара в маркетплейсе.
    public let url: String
    /// Цена в рублях.
    public let priceRub: Int
    /// Маркетплейс.
    public let marketplace: String
    /// Количество.
    public let quantity: Int
    /// ID товара из поиска.
    public let furnitureId: String
    /// Категория.
    public let category: String

    public init(
        name: String,
        url: String,
        priceRub: Int,
        marketplace: String,
        quantity: Int = 1,
        furnitureId: String,
        category: String
    ) {
        self.name = name
        self.url = url
        self.priceRub = priceRub
        self.marketplace = marketplace
        self.quantity = quantity
        self.furnitureId = furnitureId
        self.category = category
    }

    /// Полная стоимость позиции (цена × количество).
    public var totalPrice: Int {
        priceRub * quantity
    }
}

// MARK: - Budget Warning

/// Предупреждение о бюджете.
public enum BudgetWarning: String, Sendable, Equatable, Codable {
    /// Бюджет превышен.
    case overBudget = "over_budget"
    /// Мало товаров — бюджет недоиспользован (> 50% свободно).
    case underutilized = "underutilized"
    /// Бюджет почти исчерпан (< 5% осталось).
    case tight = "tight"
    /// Всё в порядке.
    case ok = "ok"
}

// MARK: - Shopping List Response

/// Полный список покупок (Blueprint output_schema).
public struct ShoppingListResponse: Sendable, Equatable, Codable {
    /// Позиции списка.
    public let items: [ShoppingListItem]
    /// Итоговая цена всех позиций.
    public let totalPriceRub: Int
    /// Остаток бюджета (может быть отрицательным при переборе).
    public let budgetRemaining: Int
    /// Исходный бюджет.
    public let budgetMax: Int
    /// Предупреждение о бюджете.
    public let budgetWarning: BudgetWarning
    /// Рекомендации по оптимизации (если бюджет превышен).
    public let optimizationTips: [String]
    /// Время формирования списка (мс).
    public let latencyMs: Double
    /// Количество уникальных товаров.
    public let uniqueItems: Int

    public init(
        items: [ShoppingListItem],
        totalPriceRub: Int,
        budgetRemaining: Int,
        budgetMax: Int,
        budgetWarning: BudgetWarning = .ok,
        optimizationTips: [String] = [],
        latencyMs: Double = 0,
        uniqueItems: Int? = nil
    ) {
        self.items = items
        self.totalPriceRub = totalPriceRub
        self.budgetRemaining = budgetRemaining
        self.budgetMax = budgetMax
        self.budgetWarning = budgetWarning
        self.optimizationTips = optimizationTips
        self.latencyMs = latencyMs
        self.uniqueItems = uniqueItems ?? items.count
    }

    /// Сериализация в JSON-строку (для ToolResult.data).
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Draft Shopping List Input

/// Входные данные для формирования списка покупок (Blueprint input_schema).
public struct DraftShoppingListInput: Sendable, Equatable, Codable {
    /// Выбранные товары: ID + marketplace.
    public struct Selection: Sendable, Equatable, Codable {
        public let furnitureId: String
        public let marketplace: String
        public let quantity: Int

        public init(furnitureId: String, marketplace: String, quantity: Int = 1) {
            self.furnitureId = furnitureId
            self.marketplace = marketplace
            self.quantity = quantity
        }
    }

    /// Выбранные позиции.
    public let selections: [Selection]
    /// Максимальный бюджет в рублях.
    public let budgetMaxRub: Int
    /// Название комнаты / проекта.
    public let projectName: String?

    public init(
        selections: [Selection],
        budgetMaxRub: Int,
        projectName: String? = nil
    ) {
        self.selections = selections
        self.budgetMaxRub = budgetMaxRub
        self.projectName = projectName
    }
}

// MARK: - Tool Implementation

/// Инструмент формирования списка покупок.
///
/// Blueprint §6:
/// - risk_class: draft
/// - side_effects: none
/// - permission: allow
/// - timeout: 5s
/// - draft-commit split: draft_shopping_list → confirm_purchase_order (DENY в MVP v1)
///
/// Принимает выбранные позиции мебели (ID товаров из search_marketplace_furniture),
/// агрегирует цены, проверяет бюджет, формирует итоговый список с рекомендациями.
///
/// Использует `FurnitureSearchResult` из `SearchMarketplaceFurnitureTool` для
/// получения детальной информации о товарах.
public struct DraftShoppingListTool: AgentTool {

    // MARK: - AgentTool Conformance

    public let name = "draft_shopping_list"
    public let description = """
    Формирует итоговый список покупок на основе выбранной мебели.
    Принимает массив ID товаров с маркетплейсами, агрегирует цены,
    проверяет бюджет и выдаёт рекомендации по оптимизации.
    НЕ совершает покупки — только формирует черновик списка.
    """

    public let inputSchema = ToolInputSchema(
        type: "object",
        properties: [
            "furniture_selection": SchemaProperty(
                type: .array,
                description: "Массив [{furniture_id: String, marketplace: String, quantity: Int?}] выбранных товаров"
            ),
            "budget_max_rub": SchemaProperty(
                type: .integer,
                description: "Максимальный бюджет на проект (в рублях)"
            ),
            "project_name": SchemaProperty(
                type: .string,
                description: "Название проекта/комнаты (опционально)"
            )
        ],
        required: ["furniture_selection", "budget_max_rub"]
    )

    public let riskClass: ToolRiskClass = .draft
    public let timeout: TimeInterval = 5.0
    public let maxResultChars: Int = 4000
    public let sideEffects: ToolSideEffect = .none

    // MARK: - Validation

    public func validate(_ arguments: [String: Any]) throws -> [String: Any] {
        // furniture_selection — массив словарей
        guard let selectionsArray = arguments["furniture_selection"] as? [[String: Any]] else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует или некорректен 'furniture_selection' (ожидается массив [{furniture_id, marketplace, quantity?}])"
            )
        }

        guard !selectionsArray.isEmpty else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "'furniture_selection' не может быть пустым"
            )
        }

        // Валидация каждого элемента
        for (index, item) in selectionsArray.enumerated() {
            guard let furnitureId = item["furniture_id"] as? String, !furnitureId.isEmpty else {
                throw ToolError.validationFailed(
                    tool: name,
                    reason: "Элемент \(index): отсутствует или пуст 'furniture_id'"
                )
            }
            guard let marketplace = item["marketplace"] as? String,
                  ["wildberries", "ozon"].contains(marketplace) else {
                throw ToolError.validationFailed(
                    tool: name,
                    reason: "Элемент \(index): 'marketplace' должен быть 'wildberries' или 'ozon'"
                )
            }
        }

        guard arguments["budget_max_rub"] != nil else {
            throw ToolError.validationFailed(
                tool: name,
                reason: "Отсутствует 'budget_max_rub'"
            )
        }

        return arguments
    }

    // MARK: - Execute

    public func execute(validated: [String: Any]) async throws -> String {
        let selectionsArray = validated["furniture_selection"] as! [[String: Any]]
        let budgetMaxRub = validated["budget_max_rub"] as? Int ?? 500_000
        let projectName = validated["project_name"] as? String

        let startTime = CFAbsoluteTimeGetCurrent()

        // Парсим selections
        let selections: [DraftShoppingListInput.Selection] = selectionsArray.compactMap { item in
            guard let fid = item["furniture_id"] as? String,
                  let mp = item["marketplace"] as? String else {
                return nil
            }
            let qty = item["quantity"] as? Int ?? 1
            return DraftShoppingListInput.Selection(
                furnitureId: fid,
                marketplace: mp,
                quantity: max(1, qty)
            )
        }

        let input = DraftShoppingListInput(
            selections: selections,
            budgetMaxRub: budgetMaxRub,
            projectName: projectName
        )

        let response = buildShoppingList(from: input, startTime: startTime)
        return try response.toJSON()
    }

    // MARK: - Shopping List Builder

    /// Формирует список покупок на основе выбранных товаров.
    ///
    /// В реальной реализации:
    /// - Берёт детальную информацию о товарах из кэша результатов `search_marketplace_furniture`.
    /// - Проверяет актуальность цен (могли измениться с момента поиска).
    /// - Группирует по категориям.
    ///
    /// Сейчас (Windows / mock):
    /// - Генерирует реалистичные данные на основе ID товаров.
    /// - Проверяет бюджет и даёт рекомендации.
    private func buildShoppingList(
        from input: DraftShoppingListInput,
        startTime: CFAbsoluteTime
    ) -> ShoppingListResponse {
        var items: [ShoppingListItem] = []
        var totalPrice = 0

        for selection in input.selections {
            // Детерминированная цена на основе furnitureId
            let price = deterministicPrice(for: selection.furnitureId)

            // Детерминированное имя на основе furnitureId
            let name = deterministicName(for: selection.furnitureId, marketplace: selection.marketplace)

            // Детерминированная категория
            let category = deterministicCategory(for: selection.furnitureId)

            let item = ShoppingListItem(
                name: name,
                url: "https://www.\(selection.marketplace == "wildberries" ? "wildberries.ru" : "ozon.ru")/product/\(selection.furnitureId)",
                priceRub: price,
                marketplace: selection.marketplace,
                quantity: selection.quantity,
                furnitureId: selection.furnitureId,
                category: category
            )

            items.append(item)
            totalPrice += item.totalPrice
        }

        let budgetRemaining = input.budgetMaxRub - totalPrice

        // Оценка бюджета
        let budgetWarning: BudgetWarning
        var optimizationTips: [String] = []

        if budgetRemaining < 0 {
            budgetWarning = .overBudget
            let overPercent = abs(budgetRemaining) * 100 / input.budgetMaxRub

            optimizationTips = [
                "Превышение бюджета на \(abs(budgetRemaining)) ₽ (\(overPercent)% сверх лимита)",
                "💡 Рассмотрите альтернативы подешевле в категориях: \(topCategories(items).joined(separator: ", "))",
                "💡 Попробуйте уменьшить количество декоративных элементов",
                "💡 Проверьте Ozon — там могут быть аналоги дешевле на 10-20%"
            ]
        } else if budgetRemaining > input.budgetMaxRub * 50 / 100 {
            budgetWarning = .underutilized
            optimizationTips = [
                "Остаток бюджета: \(budgetRemaining) ₽ (\(budgetRemaining * 100 / max(input.budgetMaxRub, 1))%)",
                "💡 Можно добавить декор, текстиль или растения",
                "💡 Рассмотрите more premium версии выбранной мебели",
                "💡 Инвестируйте в качественное освещение"
            ]
        } else if budgetRemaining < input.budgetMaxRub * 5 / 100 {
            budgetWarning = .tight
            optimizationTips = [
                "Бюджет почти исчерпан: осталось \(budgetRemaining) ₽",
                "💡 Отложите часть декора на следующий месяц",
                "💡 Проверьте сезонные скидки на Wildberries"
            ]
        } else {
            budgetWarning = .ok
        }

        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return ShoppingListResponse(
            items: items,
            totalPriceRub: totalPrice,
            budgetRemaining: budgetRemaining,
            budgetMax: input.budgetMaxRub,
            budgetWarning: budgetWarning,
            optimizationTips: optimizationTips,
            latencyMs: latency,
            uniqueItems: Set(items.map(\.furnitureId)).count
        )
    }

    // MARK: - Helpers

    /// Детерминированная цена на основе ID товара.
    private func deterministicPrice(for furnitureId: String) -> Int {
        let hash = abs(furnitureId.hashValue)
        let basePrices: [Int] = [
            4_500,   // декор, мелкие предметы
            8_900,   // стулья, светильники
            12_900,  // столы, кресла
            18_500,  // комоды, тумбы
            24_900,  // диваны прямые
            35_000,  // шкафы, стеллажи
            49_900,  // диваны угловые
            65_000,  // кухонные гарнитуры
            89_000,  // крупная мебель
            120_000  // премиум-сегмент
        ]
        // Небольшая вариация ±10%
        let baseIndex = hash % basePrices.count
        let basePrice = basePrices[baseIndex]
        let variation = (hash % 21) - 10 // -10..+10
        return basePrice + (basePrice * variation / 100)
    }

    /// Детерминированное имя товара.
    private func deterministicName(for furnitureId: String, marketplace: String) -> String {
        let hash = abs(furnitureId.hashValue)
        let prefix = marketplace == "wildberries" ? "WB" : "OZN"

        let names = [
            "Диван угловой «Комфорт»",
            "Диван прямой 3-местный",
            "Стол обеденный раскладной",
            "Журнальный столик стеклянный",
            "Кресло-реклайнер",
            "Стул обеденный (комплект 4 шт)",
            "Шкаф-купе 3-дверный",
            "Комод с ящиками",
            "Торшер напольный",
            "Подвесной светильник",
            "Ковёр шерстяной 200×300",
            "Зеркало настенное",
            "Тумба прикроватная",
            "Стеллаж открытый",
            "Пуф мягкий",
            "Картина модульная",
            "Ваза напольная керамическая",
            "LED-подсветка (комплект)",
            "Бра настенное",
            "Кушетка раскладная"
        ]

        let nameIndex = hash % names.count
        return "\(prefix)-\(furnitureId.suffix(6)) \(names[nameIndex])"
    }

    /// Детерминированная категория.
    private func deterministicCategory(for furnitureId: String) -> String {
        let hash = abs(furnitureId.hashValue)
        let categories = [
            "sofa", "table", "chair", "lamp", "cabinet",
            "decor", "rug", "bed", "shelf", "other"
        ]
        return categories[hash % categories.count]
    }

    /// Топ-3 категории по стоимости (для рекомендаций по оптимизации).
    private func topCategories(_ items: [ShoppingListItem]) -> [String] {
        var categoryTotals: [String: Int] = [:]
        for item in items {
            categoryTotals[item.category, default: 0] += item.totalPrice
        }
        return categoryTotals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }
}

// MARK: - Preview Helpers

#if DEBUG
public extension DraftShoppingListTool {
    /// Создаёт тестовый список покупок для preview/SwiftUI.
    static func previewList(budget: Int = 350_000) -> ShoppingListResponse {
        let selections: [[String: Any]] = [
            ["furniture_id": "WB-123456", "marketplace": "wildberries", "quantity": 1],
            ["furniture_id": "OZN-789012", "marketplace": "ozon", "quantity": 1],
            ["furniture_id": "WB-345678", "marketplace": "wildberries", "quantity": 4],
            ["furniture_id": "OZN-901234", "marketplace": "ozon", "quantity": 1],
            ["furniture_id": "WB-567890", "marketplace": "wildberries", "quantity": 2]
        ]

        let input = DraftShoppingListInput(
            selections: selections.compactMap { item in
                guard let fid = item["furniture_id"] as? String,
                      let mp = item["marketplace"] as? String else {
                    return nil
                }
                let qty = item["quantity"] as? Int ?? 1
                return DraftShoppingListInput.Selection(
                    furnitureId: fid,
                    marketplace: mp,
                    quantity: qty
                )
            },
            budgetMaxRub: budget,
            projectName: "Гостиная — Preview"
        )

        let tool = DraftShoppingListTool()
        return tool.buildShoppingList(from: input, startTime: 0)
    }
}
#endif