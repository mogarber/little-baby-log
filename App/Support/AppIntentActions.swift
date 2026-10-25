import CoreData
import os
import BabyLogKit

/// The app-side bodies of the widget / Live Activity intents (`Shared/ActionIntents.swift`).
/// Runs in the app's process, against the app's own Core Data (and CloudKit) container.
@MainActor
enum AppIntentActions {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "intents")

    static func nursing(babyID: String, side: BreastSide?) async {
        await run("nursing", babyID) { id, context in
            WidgetActions.nursing(babyID: id, side: side, in: context)
        }
    }

    static func finishNursing(babyID: String) async {
        await run("finishNursing", babyID) { id, context in
            WidgetActions.finishNursing(babyID: id, in: context)
        }
    }

    static func toggleSleep(babyID: String) async {
        await run("toggleSleep", babyID) { id, context in
            WidgetActions.toggleSleep(babyID: id, in: context)
        }
    }

    static func logDiaper(babyID: String, kind: DiaperKind) async {
        await run("logDiaper", babyID) { id, context in
            WidgetActions.logDiaper(babyID: id, kind: kind, in: context)
        }
    }

    /// Applies the action, saves, then brings the snapshot, widget timelines, and Live Activities up to
    /// date *before* returning, because iOS may suspend the process as soon as `perform()` finishes.
    private static func run(
        _ name: String,
        _ babyID: String,
        _ action: (UUID, NSManagedObjectContext) -> Bool
    ) async {
        let persistence = PersistenceController.shared
        guard persistence.loadError == nil, let id = UUID(uuidString: babyID) else {
            log.error("\(name, privacy: .public): store unavailable or bad baby id")
            return
        }
        let context = persistence.viewContext
        if action(id, context) {
            context.saveIfNeeded()
        } else {
            log.notice("\(name, privacy: .public): baby or timer not found")
        }
        await AppServices.syncNow(.intent)
    }
}
