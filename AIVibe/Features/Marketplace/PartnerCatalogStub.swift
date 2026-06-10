// AIVibe/Features/Marketplace/PartnerCatalogStub.swift
// Демо-каталог фабрик-партнёров (заглушка до Фазы 2 / B4).
//
// Артикулы зеркалят backend-сид (backend/scripts/seed-test-catalog.mjs):
// когда B4 подключит живой каталог YDB, артикулы совпадут и заглушка
// заменится сетевыми данными без переделки UI.
//
// 3D-модели в бандле приложения — CC0 (Poly Haven), сконвертированы
// в USDZ локальным конвейером (прототип B1: usdcat → fix → usdzip).

import Foundation

// MARK: - Позиция каталога

/// Товар демо-каталога фабрики-партнёра.
public struct PartnerCatalogItem: Identifiable, Equatable, Sendable {
    /// Артикул — совпадает с backend-сидом (TEST-SOFA-001 и т.д.).
    public let article: String
    public let name: String
    /// Вымышленная фабрика-партнёр (реальные появятся в Фазе 2).
    public let factory: String
    /// Категория канона каталога: sofa/bed/armchair/chair/table/wardrobe/shelf/cabinet/lamp.
    public let category: String
    public let style: String
    public let priceRub: Int
    public let widthCm: Int
    public let depthCm: Int
    public let heightCm: Int
    /// Имя USDZ-файла в бандле приложения (Tier 2 в USDZLoader).
    public let usdzFile: String
    /// Тон фолбэк-плашки, пока миниатюра модели рендерится.
    public let tone: AIPhotoTone

    public var id: String { article }

    public init(
        article: String,
        name: String,
        factory: String,
        category: String,
        style: String,
        priceRub: Int,
        widthCm: Int,
        depthCm: Int,
        heightCm: Int,
        usdzFile: String,
        tone: AIPhotoTone
    ) {
        self.article = article
        self.name = name
        self.factory = factory
        self.category = category
        self.style = style
        self.priceRub = priceRub
        self.widthCm = widthCm
        self.depthCm = depthCm
        self.heightCm = heightCm
        self.usdzFile = usdzFile
        self.tone = tone
    }
}

// MARK: - Каталог

/// Статический демо-каталог: 7 позиций, по одной на категорию.
public enum PartnerCatalogStub {

    public static let items: [PartnerCatalogItem] = [
        PartnerCatalogItem(
            article: "TEST-SOFA-001",
            name: "Диван трёхместный «Осло»",
            factory: "Северный Дом",
            category: "sofa", style: "scandinavian",
            priceRub: 64_900, widthCm: 220, depthCm: 95, heightCm: 80,
            usdzFile: "sofa.usdz", tone: .sand
        ),
        PartnerCatalogItem(
            article: "TEST-ARMCH-001",
            name: "Кресло «Полярис» с подлокотниками",
            factory: "Северный Дом",
            category: "armchair", style: "scandinavian",
            priceRub: 24_900, widthCm: 80, depthCm: 85, heightCm: 100,
            usdzFile: "armchair.usdz", tone: .sage
        ),
        PartnerCatalogItem(
            article: "TEST-CHAIR-001",
            name: "Стул обеденный «Сканди Вуд»",
            factory: "Северный Дом",
            category: "chair", style: "scandinavian",
            priceRub: 6_900, widthCm: 45, depthCm: 52, heightCm: 82,
            usdzFile: "chair.usdz", tone: .cream
        ),
        PartnerCatalogItem(
            article: "TEST-TABLE-002",
            name: "Стол журнальный «Лофт Куб»",
            factory: "ЛофтМеталл",
            category: "table", style: "loft",
            priceRub: 14_900, widthCm: 80, depthCm: 80, heightCm: 45,
            usdzFile: "table.usdz", tone: .taupe
        ),
        PartnerCatalogItem(
            article: "TEST-SHELF-001",
            name: "Стеллаж пятиярусный «Лофт Грид»",
            factory: "ЛофтМеталл",
            category: "shelf", style: "loft",
            priceRub: 16_900, widthCm: 80, depthCm: 35, heightCm: 185,
            usdzFile: "bookshelf.usdz", tone: .stone
        ),
        PartnerCatalogItem(
            article: "TEST-WARD-003",
            name: "Комод четыре ящика «Минима»",
            factory: "Минима",
            category: "wardrobe", style: "minimalist",
            priceRub: 18_900, widthCm: 90, depthCm: 45, heightCm: 95,
            usdzFile: "wardrobe.usdz", tone: .clay
        ),
        PartnerCatalogItem(
            article: "TEST-BED-003",
            name: "Кровать классическая «Усадьба» 180",
            factory: "Усадьба",
            category: "bed", style: "classic_russian",
            priceRub: 84_900, widthCm: 185, depthCm: 210, heightCm: 120,
            usdzFile: "bed.usdz", tone: .terracotta
        )
    ]

    /// Поиск по артикулу (контракт B3/B4: артикул → карточка).
    public static func item(article: String) -> PartnerCatalogItem? {
        items.first { $0.article == article }
    }

    /// Подборка для inline-карусели чата: укладывается в бюджет и
    /// разнообразна по категориям (диван — кресло — стол, а не три стула).
    public static func chatShowcase(budgetRub: Int? = nil) -> [PartnerCatalogItem] {
        let fitting = budgetRub.map { budget in
            items.filter { $0.priceRub <= budget }
        } ?? items

        let categoryPriority = ["sofa", "armchair", "table", "chair", "shelf", "wardrobe", "bed"]
        var showcase: [PartnerCatalogItem] = []
        for category in categoryPriority {
            if let match = fitting.first(where: { $0.category == category }) {
                showcase.append(match)
            }
            if showcase.count == 3 { break }
        }
        return showcase
    }
}
