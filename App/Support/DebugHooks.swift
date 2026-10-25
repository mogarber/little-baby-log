#if DEBUG
import CoreData
import UIKit
import os
import BabyLogKit

/// Debug-only launch arguments for exercising the Live Activity paths in the simulator (not compiled in Release).
///
/// - `-lblResetLiveActivities`: at launch, end every Live Activity and forget what was started / dismissed.
/// - `-lblInsertTimerInBackground sleep|breastfeed`: once the app has gone to the background, insert a running
///   timer for the first baby from a background context, as if a partner's timer had just synced in.
@MainActor
enum DebugHooks {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "debug")
    private static var observer: NSObjectProtocol?

    static func prepare() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lblResetLiveActivities") {
            await LiveActivityManager.shared.debugReset()
            log.notice("debug: reset Live Activities")
        }
        if let index = arguments.firstIndex(of: "-lblInsertTimerInBackground"), index + 1 < arguments.count,
           let kind = EventKind(rawValue: arguments[index + 1]) {
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { insertTimerSoon(kind) }
            }
        }
    }

    private static func insertTimerSoon(_ kind: EventKind) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let log = Self.log
            let persistence = PersistenceController.shared
            let context = persistence.container.newBackgroundContext()
            context.perform {
                if let baby = try? context.fetch(Baby.lblAllByCreation()).first {
                    _ = LogEvent.create(kind: kind, for: baby, start: .now, in: context)
                    context.saveIfNeeded()
                    log.notice("debug: inserted a running \(kind.rawValue, privacy: .public) timer while backgrounded")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { UIApplication.shared.endBackgroundTask(task) }
        }
    }
}
#endif
