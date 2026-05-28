// AIVibe/Navigation/AppRoute.swift
// Единый enum маршрутов для NavigationStack. Лежит в публичном API,
// чтобы App-shell мог склеить любые экраны в любом порядке.

import Foundation

public enum AppRoute: Hashable, Sendable {
    /// Карточка товара из маркетплейса.
    case productDetail(ProductDetail)

    /// Flow сканирования комнаты (intro → scanning → result).
    case roomScan

    /// AR-расстановка мебели (опционально с предзагруженным проектом).
    case arDesigner

    /// Карточка идеи дня (пока — заглушка, открывает AR с тоном идеи).
    case ideaPreview(HomeIdea)

    /// Проект пользователя (откроет AR-сцену проекта).
    case project(HomeProject)
}
