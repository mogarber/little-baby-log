import SwiftUI
import CoreData
import BabyLogKit

@main
struct LittleBabyLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let persistence = PersistenceController.shared

    init() {
        AppServices.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(\.persistence, persistence)
        }
    }
}
