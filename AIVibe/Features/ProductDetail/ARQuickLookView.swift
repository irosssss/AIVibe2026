// AIVibe/Features/ProductDetail/ARQuickLookView.swift
// Системный AR-просмотр одного товара (Apple AR Quick Look) — путь
// Яндекс Маркета/Amazon: перенос, вращение двумя пальцами, реальный
// масштаб, тени и окклюзия людей — из коробки от iOS, без своего
// AR-кода. Для сцены «вся комната» остаётся наш ARDesigner.

import ARKit
import QuickLook
import SwiftUI

/// Полноэкранный AR Quick Look для USDZ-файла.
public struct ARQuickLookView: UIViewControllerRepresentable {

    /// URL USDZ-файла (бандл или скачанный).
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    public final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        public func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            let item = ARQuickLookPreviewItem(fileAt: fileURL)
            // Мебель примеряют в реальном размере — пользовательское
            // масштабирование запрещено (стандарт IKEA/Wayfair).
            item.allowsContentScaling = false
            return item
        }
    }
}

/// Резолвит USDZ из бандла приложения по имени файла каталога
/// (та же нормализация, что в USDZLoader: имя без расширения).
public func bundledUSDZURL(for usdzFile: String?) -> URL? {
    guard let usdzFile, !usdzFile.isEmpty else { return nil }
    let name = usdzFile.replacingOccurrences(of: ".usdz", with: "")
    return Bundle.main.url(forResource: name, withExtension: "usdz")
}
