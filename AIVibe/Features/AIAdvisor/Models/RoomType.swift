// RoomType.swift
// Из siegblink: Living Room / Dining Room / Bedroom / Bedroom / Bathroom / Office

import Foundation

enum RoomType: String, CaseIterable, Codable, Sendable {
    case livingRoom  = "living_room"
    case bedroom     = "bedroom"
    case kitchen     = "kitchen"
    case bathroom    = "bathroom"
    case office      = "office"
    case diningRoom  = "dining_room"
    case hallway     = "hallway"
    case childRoom   = "child_room"

    var displayName: String {
        switch self {
        case .livingRoom:  return "Гостиная"
        case .bedroom:     return "Спальня"
        case .kitchen:     return "Кухня"
        case .bathroom:    return "Ванная"
        case .office:      return "Кабинет"
        case .diningRoom:  return "Столовая"
        case .hallway:     return "Прихожая"
        case .childRoom:   return "Детская"
        }
    }

    var emoji: String {
        switch self {
        case .livingRoom:  return "🛋"
        case .bedroom:     return "🛏"
        case .kitchen:     return "🍳"
        case .bathroom:    return "🚿"
        case .office:      return "💻"
        case .diningRoom:  return "🍽"
        case .hallway:     return "🚪"
        case .childRoom:   return "🧸"
        }
    }

    var promptContext: String {
        switch self {
        case .livingRoom:  return "жилая комната (гостиная)"
        case .bedroom:     return "спальня"
        case .kitchen:     return "кухня"
        case .bathroom:    return "ванная комната"
        case .office:      return "домашний кабинет"
        case .diningRoom:  return "столовая"
        case .hallway:     return "прихожая"
        case .childRoom:   return "детская комната"
        }
    }
}