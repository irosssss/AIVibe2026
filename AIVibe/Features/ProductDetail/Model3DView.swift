// AIVibe/Features/ProductDetail/Model3DView.swift
// Интерактивный 3D-просмотр USDZ из бандла: SceneKit с управлением камерой
// пальцем (вращение/зум). Используется в hero-блоке карточки товара.

import SwiftUI
import SceneKit

/// 3D-просмотрщик модели товара. Файл берётся из бандла приложения.
public struct Model3DView: UIViewRepresentable {

    public let usdzFile: String

    public init(usdzFile: String) {
        self.usdzFile = usdzFile
    }

    public func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling2X

        let name = usdzFile.replacingOccurrences(of: ".usdz", with: "")
        if let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
           let scene = try? SCNScene(url: url) {
            view.scene = scene
        }
        return view
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {}
}
