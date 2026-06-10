// AIVibe/DesignSystem/Haptics.swift
// Тонкая обёртка над UIFeedbackGenerator. На MainActor — генераторы
// должны вызываться с main thread.

import UIKit

@MainActor
public enum Haptics {

    /// Успех — добавление в проект, завершение скана, confirm покупки.
    public static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// Предупреждение — удаление товара из подборки, отмена действия.
    public static func warning() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }

    /// Ошибка — failure скана, отказ AI, network failure.
    public static func error() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.error)
    }

    /// Лёгкий tap — selection в списке, page-flip, отправка сообщения.
    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Средний tap — primary CTA (Начать сканирование, Открыть товар).
    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Жёсткий tap — для редких "wow"-моментов (генерация дизайна готова).
    public static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Выбор из списка (chip, segmented).
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
