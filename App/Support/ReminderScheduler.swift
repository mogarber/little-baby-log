import CoreData
import Foundation
import UserNotifications
import os
import BabyLogKit

/// Makes the notification center match the reminder plan (`ReminderPlanner`, BabyLogKit): feed-every-N-hours
/// requests that follow the latest feed, nap-window heads-ups that follow the sleep prediction, and daily repeating
/// reminders. Everything is local to this phone.
///
/// - Requests are replaced by fixed identifiers (`ReminderIdentifier`), so a reminder moves instead of duplicating.
///   Pending ones that are no longer planned (a baby deleted, a reminder turned off, a feed logged after the
///   due time) are removed. Delivered feed reminders that a newer feed has made out of date are cleared too.
/// - `refresh()` is cheap and idempotent. `AppServices` calls it after saves, remote (iCloud) changes, launch,
///   and foreground, and the settings screen calls it after every edit. There is no polling and no background work.
/// - Calls are serialized and coalesced: a call that arrives while one is running makes it run once more.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    enum Permission: Equatable {
        case notDetermined, denied, granted
    }

    private static let log = Logger(subsystem: "app.littlebabylog", category: "reminders")

    private var inFlight: Task<Void, Never>?
    private var runAgain = false
    private var readContext: NSManagedObjectContext?
    private let store: ReminderSettingsStore

    init(store: ReminderSettingsStore = ReminderSettingsStore()) {
        self.store = store
    }

    // MARK: Permission

    func permission() async -> Permission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .granted
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt the first time (and only then); returns where things stand afterwards.
    func requestPermissionIfNeeded() async -> Permission {
        if await permission() == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        return await permission()
    }

    // MARK: Categories

    /// Feed reminders get Start Left / Start Right / Snooze. Call once at launch.
    func registerCategories() {
        let startLeft = UNNotificationAction(identifier: ReminderCategory.startLeft, title: "Start Left", options: [])
        let startRight = UNNotificationAction(identifier: ReminderCategory.startRight, title: "Start Right", options: [])
        let snooze = UNNotificationAction(
            identifier: ReminderCategory.snooze,
            title: "Snooze \(ReminderCategory.snoozeMinutes) min",
            options: []
        )
        let feed = UNNotificationCategory(
            identifier: ReminderCategory.feed,
            actions: [startLeft, startRight, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([feed])
    }

    // MARK: Refresh

    /// Brings the notification center in line with the settings and the latest feeds, now.
    func refresh(persistence: PersistenceController = .shared) async {
        if let inFlight {
            runAgain = true
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                runAgain = false
                await perform(persistence)
            } while runAgain
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func perform(_ persistence: PersistenceController) async {
        guard persistence.loadError == nil else { return }
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let babies = loadBabies(persistence, now: now)
        let allowed = await permission() == .granted
        let planned = allowed ? ReminderPlanner.plan(babies: babies, now: now, calendar: .current) : []

        // Pending: remove what isn't planned any more (a snooze stays until it fires or goes stale).
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(ReminderIdentifier.prefix) }
        let plannedIDs = Set(planned.map(\.identifier))
        let pendingByID = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = pending.filter { request in
            if plannedIDs.contains(request.identifier) { return false }
            guard request.identifier.hasPrefix(ReminderIdentifier.snoozePrefix) else { return true }
            return !allowed || ReminderPlanner.isStale(userInfo: Self.stringInfo(request.content.userInfo), babies: babies)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale.map(\.identifier))
        }

        // Pending: add or move what changed.
        var changed = 0
        for request in planned {
            if let existing = pendingByID[request.identifier], Self.matches(existing, request) { continue }
            do {
                try await center.add(Self.makeRequest(request, now: now))
                changed += 1
            } catch {
                Self.log.error("Couldn't schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Delivered: a feed reminder for an older feed is noise once a newer feed is logged.
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(ReminderIdentifier.prefix) }
        let outdated = delivered.filter {
            ReminderPlanner.isStale(userInfo: Self.stringInfo($0.request.content.userInfo), babies: babies)
        }
        if !outdated.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: outdated.map { $0.request.identifier })
        }

        #if DEBUG
        if changed > 0 || !stale.isEmpty { await logPending(allowed: allowed) }
        #endif
    }

    /// Schedules a one-off reminder now (used by the Snooze action).
    func schedule(_ request: ReminderRequest) async {
        guard await permission() == .granted else { return }
        do {
            try await UNUserNotificationCenter.current().add(Self.makeRequest(request, now: Date()))
        } catch {
            Self.log.error("Couldn't schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        #if DEBUG
        await logPending(allowed: true)
        #endif
    }

    // MARK: Inputs

    private func loadBabies(_ persistence: PersistenceController, now: Date) -> [ReminderBaby] {
        let context: NSManagedObjectContext
        if let existing = readContext {
            context = existing
        } else {
            context = persistence.container.newBackgroundContext()
            context.name = "reminders"
            readContext = context
        }
        // Reset before reading: a long-lived context would keep serving cached rows.
        context.performAndWait { context.reset() }
        return ReminderInputs.load(in: context, settings: store, now: now)
    }

    // MARK: UserNotifications glue

    static func makeRequest(_ request: ReminderRequest, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.threadIdentifier = request.babyID.uuidString
        content.userInfo = request.userInfo
        if let category = request.categoryIdentifier { content.categoryIdentifier = category }
        content.interruptionLevel = Self.level(request.urgency)

        let trigger: UNNotificationTrigger
        switch request.trigger {
        case .date(let date):
            // An interval from now is an absolute moment: daylight saving or a time-zone change can't shift it.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
        case .daily(let hour, let minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
        return UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
    }

    private static func level(_ urgency: ReminderUrgency) -> UNNotificationInterruptionLevel {
        switch urgency {
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }

    /// True when `pending` already is exactly what `request` asks for, so it needn't be added again.
    private static func matches(_ pending: UNNotificationRequest, _ request: ReminderRequest) -> Bool {
        let content = pending.content
        guard content.title == request.title,
              content.body == request.body,
              content.categoryIdentifier == (request.categoryIdentifier ?? ""),
              content.interruptionLevel == level(request.urgency),
              stringInfo(content.userInfo) == request.userInfo else { return false }
        switch request.trigger {
        case .date(let date):
            guard let trigger = pending.trigger as? UNTimeIntervalNotificationTrigger,
                  let next = trigger.nextTriggerDate() else { return false }
            return abs(next.timeIntervalSince(date)) < 5
        case .daily(let hour, let minute):
            guard let trigger = pending.trigger as? UNCalendarNotificationTrigger, trigger.repeats else { return false }
            let components = trigger.dateComponents
            return components.hour == hour && components.minute == minute && components.year == nil && components.day == nil
        }
    }

    nonisolated static func stringInfo(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in userInfo {
            if let key = key as? String, let value = value as? String { result[key] = value }
        }
        return result
    }

    #if DEBUG
    /// Logs every pending reminder (identifier, fire time, text) so the schedule can be checked in the simulator:
    /// `xcrun simctl spawn booted log stream --predicate 'category == "reminders"'`.
    func logPending(allowed: Bool) async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderIdentifier.prefix) }
            .sorted { $0.identifier < $1.identifier }
        var lines = ["reminders: \(pending.count) pending (notifications \(allowed ? "allowed" : "not allowed"))"]
        for request in pending {
            let when: String
            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger, let next = trigger.nextTriggerDate() {
                when = "at \(next.formatted(date: .abbreviated, time: .standard))"
            } else if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                let c = trigger.dateComponents
                when = String(format: "daily %02d:%02d", c.hour ?? 0, c.minute ?? 0)
            } else {
                when = "?"
            }
            lines.append("  \(request.identifier.replacingOccurrences(of: ReminderIdentifier.prefix, with: "")) \(when) | \(request.content.title) | \(request.content.body)")
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(ReminderIdentifier.prefix) }
        lines.append("  delivered: \(delivered.map { $0.request.content.title + " @ " + $0.date.formatted(date: .omitted, time: .standard) })")
        let text = lines.joined(separator: "\n")
        Self.log.notice("\(text, privacy: .public)")
        print("LBL: " + text)
    }
    #endif
}
