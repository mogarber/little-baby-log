import SwiftUI
import UIKit
import BabyLogKit

struct MainTabView: View {
    let baby: Baby
    /// A deep link to act on. Any link brings Today forward; Today consumes it.
    @Binding var link: DeepLink?

    private enum Tab: Hashable {
        case today, history, trends, settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var tab: Tab = .today

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                TodayView(baby: baby, day: day, link: $link)
                    .id(day)
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(Tab.today)

            NavigationStack {
                HistoryView(baby: baby)
            }
            .tabItem { Label("History", systemImage: "calendar") }
            .tag(Tab.history)

            NavigationStack {
                TrendsView(baby: baby)
            }
            .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
            .tag(Tab.trends)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
        .onChange(of: link, initial: true) { _, newLink in
            if newLink != nil { tab = .today }
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
    MainTabView(baby: PreviewData.baby, link: .constant(nil))
        .previewEnvironment()
}
