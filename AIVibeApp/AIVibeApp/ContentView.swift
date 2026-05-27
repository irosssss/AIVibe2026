import SwiftUI
import AIVibe

struct ContentView: View {
    var body: some View {
        TabView {
            // AI-Советник (заглушка пока)
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("AI-Советник")
                        .font(.largeTitle).bold()
                    Text("Экран AIAdvisor подключим в следующем шаге")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .navigationTitle("AI")
            }
            .tabItem { Label("AI", systemImage: "sparkles") }

            // Сканирование комнаты (LiDAR)
            RoomScanEntry()
                .tabItem { Label("Скан", systemImage: "camera.viewfinder") }

            // Маркетплейс (заглушка пока)
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "cart")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("Маркетплейс")
                        .font(.largeTitle).bold()
                    Text("Подключение Ozon/Wildberries — в следующем шаге")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .navigationTitle("Магазин")
            }
            .tabItem { Label("Магазин", systemImage: "cart") }
        }
    }
}

#Preview {
    ContentView()
}
