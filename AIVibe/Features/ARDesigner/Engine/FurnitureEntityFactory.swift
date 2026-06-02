// AIVibe/Features/ARDesigner/Engine/FurnitureEntityFactory.swift
// L3: создаёт ModelEntity из USDZAsset. Применяет transform/scale,
// навешивает компоненты (Collision/Input/GroundingShadow рекурсивно).
// Держит in-memory кэш ModelEntity. ВСЁ изолировано на @MainActor —
// ModelEntity не пересекает actor-границу.

import Foundation
import RealityKit
import UIKit
import Logging

@MainActor
public final class FurnitureEntityFactory {

    private let loader: USDZLoader
    private var memoryCache: [UUID: ModelEntity] = [:]
    private let logger = Logger(label: "ar.entity-factory")

    public init(loader: USDZLoader) {
        self.loader = loader
    }

    // MARK: - Public API

    public func loadEntity(for item: FurnitureItem) async -> ModelEntity {
        if let cached = memoryCache[item.id] {
            return cached.clone(recursive: true)
        }

        let asset = await loader.resolveAsset(for: item)
        let entity = await materialize(asset: asset, item: item)
        entity.name = item.id.uuidString

        applyTransform(entity, item: item)
        attachComponents(entity, item: item)

        memoryCache[item.id] = entity
        return entity.clone(recursive: true)
    }

    public func preloadAll(items: [FurnitureItem]) async {
        for item in items {
            _ = await loadEntity(for: item)
        }
    }

    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    // MARK: - Materialization

    private func materialize(asset: USDZAsset, item: FurnitureItem) async -> ModelEntity {
        switch asset {
        case .file(let url):
            do {
                return try await loadUSDZ(from: url, targetSize: item.size)
            } catch {
                logger.warning("Не удалось загрузить \(url.lastPathComponent): \(error.localizedDescription)")
                return generatePlaceholder(for: item)
            }
        case .placeholder:
            return generatePlaceholder(for: item)
        }
    }

    private func loadUSDZ(from url: URL, targetSize: SIMD3<Float>) async throws -> ModelEntity {
        let entity = try await Entity(contentsOf: url)
        guard let model = entity as? ModelEntity
                ?? entity.children.first(where: { $0 is ModelEntity }) as? ModelEntity else {
            let wrapper = ModelEntity()
            wrapper.addChild(entity)
            scaleToFit(wrapper, targetSize: targetSize)
            return wrapper
        }
        scaleToFit(model, targetSize: targetSize)
        return model
    }

    private func generatePlaceholder(for item: FurnitureItem) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: item.size, cornerRadius: 0.02)
        let color = placeholderColor(for: item.itemType)
        let material = SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func placeholderColor(for itemType: String) -> UIColor {
        switch itemType.lowercased() {
        case "sofa", "диван", "armchair", "кресло":
            return UIColor(red: 0.61, green: 0.71, blue: 0.59, alpha: 0.85) // sage
        case "table", "стол", "desk", "письменный стол":
            return UIColor(red: 0.85, green: 0.79, blue: 0.67, alpha: 0.85) // sand
        case "chair", "стул":
            return UIColor(red: 0.55, green: 0.49, blue: 0.42, alpha: 0.85) // taupe
        case "bed", "кровать":
            return UIColor(red: 0.94, green: 0.88, blue: 0.76, alpha: 0.85) // cream
        case "wardrobe", "шкаф", "bookshelf", "полка":
            return UIColor(red: 0.70, green: 0.63, blue: 0.53, alpha: 0.85) // warm grey
        default:
            return UIColor(red: 0.82, green: 0.50, blue: 0.38, alpha: 0.85) // terracotta
        }
    }

    // MARK: - Transform & components

    private func scaleToFit(_ entity: ModelEntity, targetSize: SIMD3<Float>) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let currentSize = bounds.extents
        guard currentSize.x > 0, currentSize.y > 0, currentSize.z > 0 else { return }

        let scaleX = targetSize.x / currentSize.x
        let scaleY = targetSize.y / currentSize.y
        let scaleZ = targetSize.z / currentSize.z
        let uniformScale = min(scaleX, min(scaleY, scaleZ))
        entity.scale = SIMD3<Float>(repeating: uniformScale)
    }

    private func applyTransform(_ entity: ModelEntity, item: FurnitureItem) {
        entity.position = item.position
        let radians = item.rotation * .pi / 180
        entity.orientation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
    }

    private func attachComponents(_ entity: ModelEntity, item: FurnitureItem) {
        let shape = ShapeResource.generateBox(size: item.size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(InputTargetComponent())
        // Apple forum #733918: GroundingShadowComponent должен стоять на каждом
        // ModelEntity внутри USDZ-иерархии, не только на корне.
        applyGroundingShadowRecursively(entity)
    }

    private func applyGroundingShadowRecursively(_ entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children {
            applyGroundingShadowRecursively(child)
        }
    }
}
