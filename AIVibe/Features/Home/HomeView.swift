// AIVibe/Features/Home/HomeView.swift
// Главный экран. Дизайн: docs/design/ai-vibe/project/home.jsx

import ComposableArchitecture
import SwiftUI

public struct HomeView: View {

    @Bindable public var store: StoreOf<HomeFeature>

    /// Outbound navigation — App-shell решает, какие routes пушить.
    let onStartScan: () -> Void
    let onProjectTap: (HomeProject) -> Void
    let onIdeaTryOn: (HomeIdea) -> Void

    @Environment(\.aiColors) private var c

    public init(
        store: StoreOf<HomeFeature>,
        onStartScan: @escaping () -> Void = {},
        onProjectTap: @escaping (HomeProject) -> Void = { _ in },
        onIdeaTryOn: @escaping (HomeIdea) -> Void = { _ in }
    ) {
        self.store = store
        self.onStartScan = onStartScan
        self.onProjectTap = onProjectTap
        self.onIdeaTryOn = onIdeaTryOn
    }

    public var body: some View {
        AIThemeReader {
            ZStack {
                c.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topActions
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        greeting
                            .padding(.horizontal, 16)
                            .padding(.top, 6)

                        heroCTA
                            .padding(.horizontal, 16)
                            .padding(.top, 20)

                        SectionHeader("Текущие проекты", trailing: "Все") {
                            store.send(.allProjectsTapped)
                        }
                        .padding(.top, 24)

                        projectsCarousel
                            .padding(.bottom, 4)

                        SectionHeader("Идеи дня")
                            .padding(.top, 24)

                        VStack(spacing: 10) {
                            ForEach(store.ideas) { idea in
                                IdeaCard(idea: idea) {
                                    Haptics.selection()
                                    store.send(.ideaTryOnTapped(idea.id))
                                    onIdeaTryOn(idea)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 32)
                    }
                }
            }
        }
    }

    // MARK: - Top bar (search + avatar)

    private var topActions: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                Haptics.selection()
                store.send(.searchTapped)
            } label: {
                ZStack {
                    Circle().fill(scheme == .dark
                                  ? Color(hex: 0xF1ECE2, alpha: 0.08)
                                  : Color(hex: 0x1C1916, alpha: 0.05))
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(c.onSurfaceMuted)
                }
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Поиск")

            Button {
                Haptics.selection()
                store.send(.avatarTapped)
            } label: {
                ZStack {
                    Circle().fill(
                        LinearGradient(
                            colors: [c.sandSoft, c.terracottaSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    Text(String(store.userName.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(c.onSurface)
                }
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Профиль \(store.userName)")
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Привет, \(store.userName)")
                .aiType(.largeTitle)
                .foregroundStyle(c.onSurface)
            Text("Чем займёмся сегодня?")
                .aiType(.body)
                .foregroundStyle(c.onSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero CTA card

    @Environment(\.colorScheme) private var scheme

    private var heroCTA: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoomLineArt()
                .frame(height: 124)
                .background(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color(hex: 0x26221C), Color(hex: 0x1F1C17)]
                            : [Color(hex: 0xFAF6EF), Color(hex: 0xF2EBDD)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                CapsLabel("Новый проект", color: c.terracotta)
                Text("Отсканируйте комнату")
                    .aiType(.title2)
                    .foregroundStyle(c.onSurface)
                Text("AI подберёт стиль и мебель в рамках бюджета")
                    .aiType(.callout)
                    .foregroundStyle(c.onSurfaceMuted)
            }

            PrimaryButton("Начать сканирование") {
                Haptics.medium()
                store.send(.startScanTapped)
                onStartScan()
            }
        }
        .padding(18)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .aiSoftShadow(scheme == .dark)
    }

    // MARK: - Projects carousel

    private var projectsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.projects) { project in
                    ProjectCard(project: project) {
                        Haptics.selection()
                        store.send(.projectTapped(project.id))
                        onProjectTap(project)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
