import SwiftUI
import UIKit
import BabyLogKit

struct MainTabView: View {
    let baby: Baby

    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Calendar.current.startOfDay(for: .now)

    var body: some View {
        TabView {
            NavigationStack {
                TodayView(baby: baby, day: day)
                    .id(day)
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }

            NavigationStack {
                HistoryView(baby: baby)
            }
            .tabItem { Label("History", systemImage: "calendar") }

            NavigationStack {
                TrendsView(baby: baby)
            }
            .tabItem { Label("Trends", systemImage: "chart.bar.fill") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshDay()
        }
    }

    private func refreshDay() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != day { day = today }
    }
}

#Preview {
    MainTabView(baby: PreviewData.baby)
        .previewEnvironment()
}
