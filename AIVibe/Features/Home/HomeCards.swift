// AIVibe/Features/Home/HomeCards.swift
// Карточки главного экрана: ProjectCard, IdeaCard + line-art иллюстрация.

import SwiftUI

// MARK: - ProjectCard

struct ProjectCard: View {
    let project: HomeProject
    let onTap: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                PhotoSlot(
                    tone: tone,
                    label: "скан комнаты",
                    cornerRadius: 12,
                    aspectRatio: 16.0 / 10.0
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .aiType(.headline)
                        .foregroundStyle(c.onSurface)

                    HStack {
                        Text("Шаг \(project.step) из \(project.totalSteps)")
                            .aiType(.caption)
                            .foregroundStyle(c.onSurfaceMuted)
                        Spacer()
                        Text("\(formattedBudget(project.currentBudget)) ₽")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(c.onSurface)
                    }

                    AIProgressBar(value: project.budgetRatio)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .padding(.top, 2)
            }
            .padding(12)
            .frame(width: 248)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .aiSoftShadow(scheme == .dark)
        }
        .buttonStyle(.plain)
    }

    private var tone: AIPhotoTone {
        AIPhotoTone(rawValue: project.tone) ?? .sand
    }

    private func formattedBudget(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}"
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - IdeaCard

struct IdeaCard: View {
    let idea: HomeIdea
    let onTryOn: () -> Void

    @Environment(\.aiColors) private var c
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            PhotoSlot(
                tone: AIPhotoTone(rawValue: idea.tone) ?? .terracotta,
                cornerRadius: 12,
                aspectRatio: 1
            )
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 4) {
                Text("ИДЕЯ ОТ AI")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(c.sage)
                Text(idea.title)
                    .aiType(.headline)
                    .foregroundStyle(c.onSurface)
                    .lineLimit(2)
                Text(idea.budgetHint)
                    .aiType(.caption)
                    .foregroundStyle(c.onSurfaceMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onTryOn) {
                Text("Примерить")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        (scheme == .dark
                         ? Color(hex: 0xD17F62, alpha: 0.18)
                         : Color(hex: 0xC2674A, alpha: 0.12)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .aiSoftShadow(scheme == .dark)
    }
}

// MARK: - Room line-art (SVG → SwiftUI Path)

/// Перенос SVG из home.jsx — упрощённая изометрия пустой комнаты + окно + лампа.
struct RoomLineArt: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.aiColors) private var c

    var body: some View {
        Canvas { ctx, size in
            // Координаты — относительно viewBox "0 0 320 124".
            let sx = size.width / 320
            let sy = size.height / 124
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

            let stroke = scheme == .dark
                ? Color(hex: 0xF1ECE2, alpha: 0.55)
                : Color(hex: 0x1C1916, alpha: 0.45)
            let line = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)

            // Перспектива комнаты.
            var room = Path()
            room.move(to: p(30, 110)); room.addLine(to: p(120, 70)); room.addLine(to: p(240, 70)); room.addLine(to: p(290, 110)); room.closeSubpath()
            room.move(to: p(30, 18)); room.addLine(to: p(120, 50)); room.addLine(to: p(240, 50)); room.addLine(to: p(290, 18))
            room.move(to: p(30, 18)); room.addLine(to: p(30, 110))
            room.move(to: p(290, 18)); room.addLine(to: p(290, 110))
            room.move(to: p(120, 50)); room.addLine(to: p(120, 70))
            room.move(to: p(240, 50)); room.addLine(to: p(240, 70))
            ctx.stroke(room, with: .color(stroke), style: line)

            // Окно.
            var window = Path()
            window.addRect(CGRect(x: 140 * sx, y: 58 * sy, width: 40 * sx, height: 10 * sy))
            window.move(to: p(160, 58)); window.addLine(to: p(160, 68))
            ctx.stroke(window, with: .color(stroke), style: line)

            // Лампа: стойка + плафон.
            var lampStem = Path()
            lampStem.move(to: p(210, 50))
            lampStem.addLine(to: p(210, 95))
            lampStem.addLine(to: p(218, 100))
            ctx.stroke(lampStem, with: .color(stroke), style: line)

            let bulbRect = CGRect(x: (218 - 6) * sx, y: (92 - 6) * sy, width: 12 * sx, height: 12 * sy)
            ctx.fill(Path(ellipseIn: bulbRect), with: .color(c.sandSoft))
            ctx.stroke(Path(ellipseIn: bulbRect), with: .color(stroke), style: line)
        }
    }
}
