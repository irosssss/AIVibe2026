// AIVibe/Features/ARDesigner/Assets/USDZAsset.swift
// Sendable обёртка над загруженным USDZ-ресурсом. Используется как
// граничный тип между actor USDZLoader (L2) и @MainActor
// FurnitureEntityFactory (L3) — ModelEntity не пересекает actor-границу.

import Foundation

public enum USDZAsset: Sendable {
    /// Локальный путь к .usdz файлу (network-кэш, bundle, Hunyuan3D output).
    case file(URL)

    /// Сигнал: для этого item не найден USDZ, нужен placeholder.
    /// Genre + размер передаётся через item напрямую — здесь только маркер.
    case placeholder
}
