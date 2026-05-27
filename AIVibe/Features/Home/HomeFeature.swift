// AIVibe/Features/Home/HomeFeature.swift
// Минимальный reducer главного экрана. Данные пока mock — продактовые проекты
// и идеи дня. В будущем подцепится к ProjectStore / SkillIndex.

import ComposableArchitecture
import Foundation

// MARK: - Domain DTO для UI

public struct HomeProject: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let tone: String          // строка под AIPhotoTone.rawValue
    public let step: Int
    public let totalSteps: Int
    public let currentBudget: Int    // ₽
    public let maxBudget: Int        // ₽

    public init(
        id: UUID = UUID(),
        name: String,
        tone: String,
        step: Int,
        totalSteps: Int,
        currentBudget: Int,
        maxBudget: Int
    ) {
        self.id = id
        self.name = name
        self.tone = tone
        self.step = step
        self.totalSteps = totalSteps
        self.currentBudget = currentBudget
        self.maxBudget = maxBudget
    }

    public var budgetRatio: Double {
        guard maxBudget > 0 else { return 0 }
        return Double(currentBudget) / Double(maxBudget)
    }
}

public struct HomeIdea: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let tone: String
    public let title: String         // "Скандинавский · светлая гостиная"
    public let budgetHint: String    // "от 180 000 ₽"

    public init(id: UUID = UUID(), tone: String, title: String, budgetHint: String) {
        self.id = id
        self.tone = tone
        self.title = title
        self.budgetHint = budgetHint
    }
}

// MARK: - Reducer

@Reducer
public struct HomeFeature: Sendable {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var userName: String
        public var projects: [HomeProject]
        public var ideas: [HomeIdea]

        public init(
            userName: String = "Анна",
            projects: [HomeProject] = HomeFeature.mockProjects,
            ideas: [HomeIdea] = HomeFeature.mockIdeas
        ) {
            self.userName = userName
            self.projects = projects
            self.ideas = ideas
        }
    }

    public enum Action: Sendable {
        case startScanTapped
        case projectTapped(HomeProject.ID)
        case ideaTryOnTapped(HomeIdea.ID)
        case searchTapped
        case avatarTapped
        case allProjectsTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { _, action in
            // На этом этапе reducer — это рассылка событий вверх.
            // Навигация будет подключена на уровне App-shell.
            switch action {
            case .startScanTapped,
                 .projectTapped,
                 .ideaTryOnTapped,
                 .searchTapped,
                 .avatarTapped,
                 .allProjectsTapped:
                return .none
            }
        }
    }

    // MARK: - Mock data (визуальная демонстрация по design ref)

    public static let mockProjects: [HomeProject] = [
        HomeProject(name: "Гостиная", tone: "sand", step: 3, totalSteps: 5,
                    currentBudget: 245_000, maxBudget: 350_000),
        HomeProject(name: "Кухня", tone: "sage", step: 1, totalSteps: 5,
                    currentBudget: 62_000, maxBudget: 180_000)
    ]

    public static let mockIdeas: [HomeIdea] = [
        HomeIdea(tone: "terracotta",
                 title: "Скандинавский · светлая гостиная",
                 budgetHint: "от 180 000 ₽"),
        HomeIdea(tone: "olive",
                 title: "Японди · спальня в тёплых тонах",
                 budgetHint: "от 220 000 ₽")
    ]
}
