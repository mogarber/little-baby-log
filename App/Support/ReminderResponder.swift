import CoreData
import Foundation
import UIKit
import os
import BabyLogKit

/// What a tapped notification (or one of its buttons) carries, as plain Sendable values.
struct ReminderResponse: Sendable {
    enum Action: Sendable {
        case open, startLeft, startRight, snooze, other
    }

    var action: Action
    var title: String
    var body: String
    var categoryIdentifier: String
    var userInfo: [String: String]
}

/// A `littlebabylog://` link waiting for the UI, for when a notification tap launches the app: the link can be
/// produced before the root view exists, so it is parked here and announced with a notification.
@MainActor
enum DeepLinkRouter {
    static let didReceiveLink = Notification.Name("LittleBabyLogDeepLink")
    private(set) static var pending: DeepLink?

    static func open(_ link: DeepLink) {
        pending = link
        NotificationCenter.default.post(name: didReceiveLink, object: nil)
    }

    static func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}

/// Runs a reminder's notification actions. Start and Snooze do their work without opening the app, using the same
/// `WidgetActions` and store the widgets use, then save so sync, the Live Activity, and the widget snapshot update.
@MainActor
enum ReminderResponder {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "reminders")

    static func handle(_ response: ReminderResponse) async {
        // A cold launch for a notification action can reach us before the app's own startup has run.
        AppServices.start()
        let babyID = response.userInfo[ReminderUserInfoKey.babyID].flatMap(UUID.init(uuidString:))

        switch response.action {
        case .open:
            DeepLinkRouter.open(.today(babyID: babyID))
        case .startLeft:
            await startNursing(.left, babyID: babyID)
        case .startRight:
            await startNursing(.right, babyID: babyID)
        case .snooze:
            await snooze(response)
        case .other:
            break
        }
    }

    private static func startNursing(_ side: BreastSide, babyID: UUID?) async {
        guard let babyID else { return }
        let persistence = PersistenceController.shared
        guard persistence.loadError == nil else { return }
        let context = persistence.viewContext

        // Start means start: if this side is already running, leave it alone rather than pausing it.
        let alreadyRunning = (try? context.fetch(Baby.fetchRequest()))?
            .first(where: { $0.uuid == babyID })
            .flatMap { baby in
                (try? context.fetch(LogEvent.requestRunning(baby: baby)))?
                    .first(where: { $0.kind == .breastfeed })
            }
            .map { $0.activeSide == side } ?? false

        if !alreadyRunning {
            if WidgetActions.nursing(babyID: babyID, side: side, in: context) {
                context.saveIfNeeded()
            } else {
                log.notice("startNursing: baby not found")
            }
        }
        await AppServices.syncNow(.intent)
        keepAliveForSync()
    }

    private static func snooze(_ response: ReminderResponse) async {
        guard let request = ReminderPlanner.snooze(
            title: response.title,
            body: response.body,
            categoryIdentifier: response.categoryIdentifier.isEmpty ? nil : response.categoryIdentifier,
            urgency: .timeSensitive,
            userInfo: response.userInfo,
            now: Date()
        ) else { return }
        await ReminderScheduler.shared.schedule(request)
    }

    /// iOS may suspend a background-launched app right after the handler returns; give CloudKit a few seconds to
    /// export the change so a partner sees the timer start.
    private static func keepAliveForSync() {
        guard PersistenceController.shared.isCloudSyncEnabled else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "reminder-action-sync", expirationHandler: nil)
        guard task != .invalid else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { UIApplication.shared.endBackgroundTask(task) }
    }
}
