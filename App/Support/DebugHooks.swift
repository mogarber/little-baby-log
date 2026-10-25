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
/// - `-lblTestFeedReminder <seconds>`: schedule a feed reminder for the first baby that many seconds from launch
///   (for trying the Start Left / Start Right / Snooze actions without waiting).
/// - `-lblTestDailyReminder <minutes>`: add a daily "Vitamin D drops" medicine reminder for the first baby that many
///   minutes from now.
/// - `-lblClearReminders`: forget every reminder setting on this device (and so cancel their notifications).
/// - `-lblInitializeCloudKitSchema`: create every record type and field in the CloudKit Development
///   environment (CloudKit only creates fields for values it has seen), so the schema can be deployed to
///   Production before a TestFlight or App Store build. Run on a device signed in to iCloud.
@MainActor
enum DebugHooks {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "debug")
    private static var observer: NSObjectProtocol?

    static func prepare() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lblInitializeCloudKitSchema"),
           let container = PersistenceController.shared.cloudKitContainer {
            let log = Self.log
            Task.detached(priority: .utility) {
                do {
                    try container.initializeCloudKitSchema(options: [])
                    log.notice("debug: CloudKit schema initialized")
                    print("LBL: CloudKit schema initialized")
                } catch {
                    log.error("debug: CloudKit schema initialization failed: \(error.localizedDescription, privacy: .public)")
                    print("LBL: CloudKit schema initialization failed: \(error)")
                }
            }
        }
        if let index = arguments.firstIndex(of: "-lblTestFeedReminder"), index + 1 < arguments.count,
           let seconds = TimeInterval(arguments[index + 1]) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            let babies = ReminderInputs.load(in: context)
            if let baby = babies.first {
                // Feed reminders must be on, or the reminder below is retired as stale at the next refresh.
                let store = ReminderSettingsStore()
                var settings = store.settings(for: baby.id)
                if !settings.feedEvery.isEnabled {
                    settings.feedEvery = FeedIntervalReminder(isEnabled: true, intervalMinutes: 180)
                    store.save(settings, for: baby.id)
                }
                let start = baby.lastFeed?.start ?? .now
                let info = FeedReminderInfo(babyName: baby.name, feedStart: start, since: start,
                                            kind: baby.lastFeed?.kind ?? .breastfeed, lastSide: baby.lastFeed?.lastSide)
                let userInfo = [ReminderUserInfoKey.babyID: baby.id.uuidString,
                                ReminderUserInfoKey.feedInfo: info.userInfoValue ?? ""]
                if let request = ReminderPlanner.snooze(
                    title: "", body: "", categoryIdentifier: ReminderCategory.feed, urgency: .timeSensitive,
                    userInfo: userInfo, now: .now, delay: seconds
                ) {
                    _ = await ReminderScheduler.shared.requestPermissionIfNeeded()
                    await ReminderScheduler.shared.schedule(request)
                    log.notice("debug: test feed reminder in \(seconds, privacy: .public)s")
                }
            }
        }
        if let index = arguments.firstIndex(of: "-lblTestDailyReminder"), index + 1 < arguments.count,
           let minutes = Int(arguments[index + 1]) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            if let baby = ReminderInputs.load(in: context).first {
                let store = ReminderSettingsStore()
                var settings = store.settings(for: baby.id)
                let parts = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(TimeInterval(minutes * 60)))
                settings.daily.append(DailyReminder(
                    minutesOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), label: "Vitamin D drops", kind: .medicine
                ))
                store.save(settings, for: baby.id)
                _ = await ReminderScheduler.shared.requestPermissionIfNeeded()
                await ReminderScheduler.shared.refresh()
                log.notice("debug: added a daily reminder in \(minutes, privacy: .public) min")
            }
        }
        if arguments.contains("-lblClearReminders") {
            UserDefaults.standard.removeObject(forKey: ReminderSettingsStore.defaultsKey)
            await ReminderScheduler.shared.refresh()
            log.notice("debug: cleared reminder settings")
        }
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
