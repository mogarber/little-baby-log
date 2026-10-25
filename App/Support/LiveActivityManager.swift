import ActivityKit
import CoreData
import Foundation
import os
import BabyLogKit

/// Keeps ActivityKit in step with the running sleep / nursing timers in the local store: starts an activity
/// for each timer that has none, updates the ones whose timer changed, and ends the ones whose timer was
/// finished or deleted. No push tokens: the app (or an intent running in it) is the only updater.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private static let log = Logger(subsystem: "app.littlebabylog", category: "liveactivity")
    private static let startedKey = "liveActivityStartedTimers"

    /// A running timer, as a Live Activity wants to see it.
    private struct RunningTimer {
        var eventID: String
        var attributes: TimerActivityAttributes
        var state: TimerActivityAttributes.ContentState
        var key: String { Self.key(babyID: attributes.babyID, kind: attributes.kind) }

        static func key(babyID: String, kind: EventKind) -> String { "\(babyID)|\(kind.rawValue)" }
    }

    func reconcile(persistence: PersistenceController = .shared) async {
        guard persistence.loadError == nil else { return }
        let timers = runningTimers(in: persistence.viewContext)
        let timersByKey = Dictionary(timers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // Existing activities: update, or end when their timer is gone (or is a duplicate).
        var covered = Set<String>()
        for activity in Activity<TimerActivityAttributes>.activities {
            let key = RunningTimer.key(babyID: activity.attributes.babyID, kind: activity.attributes.kind)
            guard activity.activityState == .active || activity.activityState == .stale else { continue }
            guard let timer = timersByKey[key], !covered.contains(key) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            covered.insert(key)
            if activity.content.state != timer.state {
                await activity.update(ActivityContent(state: timer.state, staleDate: nil))
            }
        }

        // Timers without an activity. Each timer gets one start attempt: if the person swipes the
        // activity away (or the system ends it after its time limit), it doesn't come back.
        let previouslyStarted = Set(UserDefaults.standard.stringArray(forKey: Self.startedKey) ?? [])
        var started = previouslyStarted
        started = started.filter { id in timers.contains { $0.eventID == id } }
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            for timer in timers where !covered.contains(timer.key) && !started.contains(timer.eventID) {
                do {
                    _ = try Activity.request(
                        attributes: timer.attributes,
                        content: ActivityContent(state: timer.state, staleDate: nil),
                        pushType: nil
                    )
                    started.insert(timer.eventID)
                } catch {
                    Self.log.error("Couldn't start a Live Activity: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if started != previouslyStarted {
            UserDefaults.standard.set(Array(started).sorted(), forKey: Self.startedKey)
        }
    }

    // MARK: Timers

    private func runningTimers(in context: NSManagedObjectContext) -> [RunningTimer] {
        let request: NSFetchRequest<LogEvent> = LogEvent.fetchRequest()
        request.predicate = NSPredicate(
            format: "kindRaw IN %@ AND endDate == nil",
            [EventKind.sleep.rawValue, EventKind.breastfeed.rawValue]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        let events = (try? context.fetch(request)) ?? []

        var timers: [RunningTimer] = []
        var seen = Set<String>()
        for event in events where event.isRunning && !event.isDeleted {
            guard let baby = event.baby, let babyID = baby.uuid, let eventID = event.uuid, let start = event.startDate else { continue }
            let attributes = TimerActivityAttributes(babyID: babyID.uuidString, babyName: baby.displayName, kind: event.kind)
            let key = RunningTimer.key(babyID: attributes.babyID, kind: attributes.kind)
            guard seen.insert(key).inserted else { continue }   // newest running timer per baby and kind

            let state: TimerActivityAttributes.ContentState
            if event.kind == .breastfeed {
                state = .init(
                    startedAt: start,
                    leftSeconds: event.leftSeconds,
                    rightSeconds: event.rightSeconds,
                    activeSide: event.activeSide,
                    activeSideStartedAt: event.activeSideStartedAt,
                    isPaused: event.activeSide == nil
                )
            } else {
                state = .init(startedAt: start, leftSeconds: 0, rightSeconds: 0, activeSide: nil, activeSideStartedAt: nil, isPaused: false)
            }
            timers.append(RunningTimer(eventID: eventID.uuidString, attributes: attributes, state: state))
        }
        return timers
    }
}
