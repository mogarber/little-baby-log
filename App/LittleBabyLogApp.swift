import SwiftUI
import CoreData
import BabyLogKit

@main
struct LittleBabyLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    private let persistence = PersistenceController.shared

    init() {
        AppServices.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(\.persistence, persistence)
                .appearanceHost()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Live Activities for timers that were already running (or arrived from a partner while
                    // the app wasn't in the foreground) can only be started now.
                    if phase == .active { Task { await AppServices.sceneDidBecomeActive() } }
                }
        }
    }
}
