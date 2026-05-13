# СЕССИЯ 3 — RoomScan + AR Designer

> Добавь в контекст: @PROJECT_RULES.md @Core/AI/AIProviderRouter.swift
> Режим: Agent

---

Реализуй AR-модуль: сканирование комнаты + 3D дизайнер.

## 1. RoomScanManager
Файл: `Features/RoomScan/RoomScanManager.swift`

Требования:
- RoomPlan 2 API (iOS 17+, только LiDAR устройства)
- Graceful degradation: без LiDAR — предложить фото-режим
- Экспорт в USDZ (сохранить в Yandex Object Storage)
- Прогресс сканирования через AsyncStream<ScanProgress>
- Автоматическая остановка через 3 минуты (или по команде)
- После сканирования — сразу отправить превью в AIAdvisorService

```swift
// Минимальный интерфейс
actor RoomScanManager {
    var scanProgress: AsyncStream<ScanProgress> { get }
    func startScan() async throws
    func stopScan() async -> RoomScanResult?
    func exportUSDZ() async throws -> URL
}

enum ScanProgress {
    case initializing
    case scanning(coverage: Float, detectedObjects: Int)
    case processing
    case completed(previewImage: UIImage)
    case failed(Error)
}
```

## 2. RealityDesignerView
Файл: `Features/ARDesigner/RealityDesignerView.swift`

Требования:
- RealityView (SwiftUI, iOS 18+)
- Загрузка USDZ модели комнаты из кэша
- Размещение мебели (USDZ объекты) drag & drop
- Система снимков (screenshot → отправить в AI для анализа)
- Lighting estimation (ARKit)
- Undo/Redo стек (минимум 20 действий)

GitHub референс:
- https://github.com/maxxfrazer/RealityKit-Sampler (примеры RealityKit)
- https://github.com/Reality-Dev/RealityKit-Utilities

## 3. ImagePreprocessor
Файл: `Core/AI/ImagePreprocessor.swift`

Требования:
- Resize изображения до 1024x1024 max (Accelerate framework)
- K-means кластеризация для извлечения доминирующих цветов (5 цветов)
- Определение стиля освещения (тёплое/холодное/нейтральное)
- Компрессия до JPEG 85% для отправки в AI
- Всё на фоновом потоке (actor или Task.detached)

```swift
actor ImagePreprocessor {
    func process(_ image: UIImage) async throws -> ProcessedImage
    func extractDominantColors(_ image: UIImage, count: Int) async -> [UIColor]
    func estimateLighting(_ image: UIImage) async -> LightingType
}
```

## 4. Оптимизация USDZ
В отдельном файле `Shared/Utils/USDZOptimizer.swift`:
- LOD (Level of Detail) для дальних объектов
- Texture compression перед сохранением
- Кэш в NSCache + disk cache (максимум 500MB)
- Очистка кэша при memory warning

## Тесты
- `RoomScanManagerTests.swift` — mock RoomPlanSession
- `ImagePreprocessorTests.swift` — тест k-means на фото с известными цветами
- Performance тест: обработка 4K изображения < 200ms
