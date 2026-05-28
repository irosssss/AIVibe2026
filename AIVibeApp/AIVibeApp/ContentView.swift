import SwiftUI
import AIVibe
import ComposableArchitecture

struct ContentView: View {

    // — TCA-stores на уровне App, чтобы при смене таба не пересоздавались.
    @State private var homeStore = Store(initialState: HomeFeature.State()) {
        HomeFeature()
    }

    // — Отдельный NavigationPath на каждый таб.
    @State private var homePath = NavigationPath()
    @State private var chatPath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var arPath   = NavigationPath()

    // — Последний сгенерированный план (для передачи в AR-экран).
    @State private var pendingDesignPlan: RoomDesignPlan?
    @State private var pendingRoomGeometry: RoomGeometry?

    // — Выбранный таб + предыдущий, чтобы поймать «повторный тап» = pop to root.
    @State private var selectedTab: Tab = Self.initialTab()
    @State private var previousTab: Tab = .home

    enum Tab: Hashable { case home, chat, scan, ar }

    /// Поддержка launch arg `-StartTab home|chat|scan|ar` для скриптовых
    /// скриншотов через `xcrun simctl launch ... -StartTab ar`.
    private static func initialTab() -> Tab {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-StartTab"), idx + 1 < args.count else {
            return .home
        }
        switch args[idx + 1].lowercased() {
        case "chat", "ai": return .chat
        case "scan":       return .scan
        case "ar":         return .ar
        default:           return .home
        }
    }

    var body: some View {
        AIThemeReader {
            TabView(selection: tabSelectionBinding) {
                // — Таб 1: Главная
                NavigationStack(path: $homePath) {
                    HomeView(
                        store: homeStore,
                        onStartScan: { homePath.append(AppRoute.roomScan) },
                        onProjectTap: { project in
                            homePath.append(AppRoute.project(project))
                        },
                        onIdeaTryOn: { idea in
                            homePath.append(AppRoute.ideaPreview(idea))
                        }
                    )
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, in: $homePath)
                    }
                }
                .tabItem { Label("Главная", systemImage: "house") }
                .tag(Tab.home)

                // — Таб 2: AI-помощник
                NavigationStack(path: $chatPath) {
                    AIAdvisorScreen(
                        budget: BudgetSnapshot(current: 245_000, max: 350_000),
                        onProductTap: { item in
                            chatPath.append(AppRoute.productDetail(productFor(item)))
                        }
                    )
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, in: $chatPath)
                    }
                }
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(Tab.chat)

                // — Таб 3: Скан
                NavigationStack(path: $scanPath) {
                    RoomScanFlowScreen(
                        onContinueWithResult: {
                            scanPath.append(AppRoute.arDesigner)
                        },
                        onContinueWithDesign: { plan, geometry in
                            pendingDesignPlan = plan
                            pendingRoomGeometry = geometry
                            scanPath.append(AppRoute.arDesigner)
                        }
                    )
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, in: $scanPath)
                    }
                }
                .tabItem { Label("Скан", systemImage: "camera.viewfinder") }
                .tag(Tab.scan)

                // — Таб 4: AR
                NavigationStack(path: $arPath) {
                    Group {
                        if let plan = pendingDesignPlan, let geo = pendingRoomGeometry {
                            ARDesignerScreen(
                                designPlan: plan,
                                roomGeometry: geo
                            )
                        } else {
                            ARDesignerEmptyState {
                                selectedTab = .scan
                            }
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, in: $arPath)
                    }
                }
                .tabItem { Label("AR", systemImage: "cube") }
                .tag(Tab.ar)
            }
            .tint(AIColors.light.terracotta)
        }
    }

    // MARK: - Tab selection binding (pop-to-root on re-tap)

    /// Биндинг с перехватом «повторного тапа на активный таб» — сбрасывает
    /// стек до корня (стандартный iOS-паттерн, как в Mail/Messages).
    private var tabSelectionBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    Haptics.selection()
                    popToRoot(for: newTab)
                }
                previousTab = selectedTab
                selectedTab = newTab
            }
        )
    }

    private func popToRoot(for tab: Tab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .chat: chatPath = NavigationPath()
        case .scan: scanPath = NavigationPath()
        case .ar:   arPath   = NavigationPath()
        }
    }

    // MARK: - Destination factory

    /// Фабрика screens. Push'ит новые routes в тот же path,
    /// pop'ит — через мутацию переданного binding'а.
    @ViewBuilder
    private func destination(for route: AppRoute, in path: Binding<NavigationPath>) -> some View {
        switch route {
        case .roomScan:
            RoomScanFlowScreen(
                onClose: { pop(path) },
                onContinueWithResult: {
                    path.wrappedValue.append(AppRoute.arDesigner)
                },
                onContinueWithDesign: { plan, geometry in
                    pendingDesignPlan = plan
                    pendingRoomGeometry = geometry
                    path.wrappedValue.append(AppRoute.arDesigner)
                }
            )

        case .arDesigner:
            if let plan = pendingDesignPlan, let geo = pendingRoomGeometry {
                ARDesignerScreen(
                    designPlan: plan,
                    roomGeometry: geo,
                    onClose: { pop(path) }
                )
            } else {
                ARDesignerEmptyState {
                    pop(path)
                    selectedTab = .scan
                }
            }

        case .productDetail(let product):
            ProductDetailScreen(
                product: product,
                onViewInAR: {
                    // «В AR» — push AR-сцены поверх ProductDetail.
                    path.wrappedValue.append(AppRoute.arDesigner)
                }
            )

        case .ideaPreview:
            ARDesignerEmptyState { pop(path) }

        case .project:
            ARDesignerEmptyState { pop(path) }
        }
    }

    private func pop(_ path: Binding<NavigationPath>) {
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    // MARK: - Mock conversion

    /// Inline-карточка чата → mock `ProductDetail` для push'а.
    /// При подключении backend заменим на загрузку из MarketplaceClient.
    private func productFor(_ item: ChatFurnitureItem) -> ProductDetail {
        let firstPart = item.title.split(separator: ",").first.map(String.init) ?? item.title
        let brand = "IKEA · " + firstPart.trimmingCharacters(in: .whitespaces)
        return ProductDetail(
            market: item.market,
            brand: brand,
            title: item.title,
            price: item.price,
            oldPrice: item.price + 11_000,
            discountPercent: 19,
            rating: 4.8, reviews: 124,
            width: 240, depth: 95, height: 82,
            fitVerdict: "Помещается в вашу гостиную",
            fitDetail: "Займёт 58% свободного места у окна",
            aiCommentary: "Эта модель хорошо вписывается в выбранный стиль и помещается по габаритам.",
            aiProvider: "YandexGPT · design_advisor",
            description: "Описание товара будет загружено с маркетплейса при подключении backend.",
            photoTone: item.tone
        )
    }
}

#Preview {
    ContentView()
}
