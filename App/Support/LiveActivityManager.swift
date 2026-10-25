import ActivityKit
import CoreData
import Foundation
import UIKit
import os
import BabyLogKit

/// Keeps ActivityKit in step with the running sleep / nursing timers in the local store: starts an activity
/// for each timer that has none, updates the ones whose timer changed, and ends the ones whose timer was
/// finished or deleted. No push tokens: the app (or an intent running in it) is the only updater.
///
/// The decisions live in `LiveActivityPlanner` (BabyLogKit, unit tested); this type gathers the inputs from
/// Core Data and ActivityKit, performs the actions, and remembers per timer (event uuid) what happened.
///
/// - `Activity.request` only works while the app is in the foreground (or while a `LiveActivityIntent` runs,
///   `Trigger.intent`). A timer that needs an activity at any other time stays *pending* and is started by the
///   next reconcile in the foreground (`scenePhase == .active`). Updates and ends work in the background and
///   happen immediately.
/// - A timer whose activity the person swiped away (or the system ended) is remembered and not started again.
///   A timer that never got an activity is not remembered as anything, so it still gets one.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Why a reconcile runs. Decides whether starting an activity is allowed.
    enum Trigger {
        /// Process start (may be a background launch from a CloudKit push).
        case launch
        /// A save or a remote (iCloud) change.
        case change
        /// The scene became active: starting is allowed.
        case foreground
        /// A widget / Live Activity intent just ran: iOS lets it start activities from the background.
        case intent
    }

    private typealias Planner = LiveActivityPlanner<TimerActivityAttributes.ContentState>

    private static let log = Logger(subsystem: "app.littlebabylog", category: "liveactivity")
    private static let startedKey = "liveActivityStartedTimers"
    private static let dismissedKey = "liveActivityDismissedTimers"

    /// Events that need an activity but couldn't start one yet (not in the foreground). Informational: the
    /// store and ledger are the source of truth, so every reconcile recomputes it.
    private(set) var pendingStarts: [String] = []

    private var inFlight: Task<Void, Never>?
    private var observedActivities = Set<String>()
    private var endedByUs = Set<String>()
    private var eventIDByActivity = [String: String]()

    /// Reconciles now. Calls are serialized, so two overlapping triggers can never both start an activity.
    func reconcile(_ trigger: Trigger = .change, persistence: PersistenceController = .shared) async {
        let previous = inFlight
        let task = Task { @MainActor in
            await previous?.value
            await self.performReconcile(trigger, persistence)
        }
        inFlight = task
        await task.value
    }

    private func performReconcile(_ trigger: Trigger, _ persistence: PersistenceController) async {
        guard persistence.loadError == nil else { return }
        let isForeground = trigger == .foreground || trigger == .intent || UIApplication.shared.applicationState == .active

        let timers = runningTimers(in: persistence.viewContext)
        let timersByKey = Dictionary(timers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let activities = Activity<TimerActivityAttributes>.activities
        let live = activities.filter { $0.activityState == .active || $0.activityState == .stale }

        var ledger = loadLedger()
        let originalLedger = ledger
        ledger.prune(keeping: Set(timers.map(\.eventID)))
        let liveEventIDs = Set(live.compactMap { activity in
            activity.attributes.eventID
                ?? timersByKey[RunningTimer.key(babyID: activity.attributes.babyID, kind: activity.attributes.kind)]?.eventID
        })

        let plan = Planner.plan(
            timers: timers.map(\.planned),
            activities: activities.map { activity in
                Planner.Existing(
                    id: activity.id,
                    eventID: activity.attributes.eventID,
                    babyID: activity.attributes.babyID,
                    kind: activity.attributes.kind,
                    state: activity.content.state,
                    isLive: activity.activityState == .active || activity.activityState == .stale
                )
            },
            dismissed: ledger.suppressed(liveEventIDs: liveEventIDs),
            isForeground: isForeground
        )

        // Re-adopt activities (after a relaunch they're still there) and watch them for dismissal.
        for match in plan.matches {
            ledger.started.insert(match.eventID)
            eventIDByActivity[match.activityID] = match.eventID
            if let activity = live.first(where: { $0.id == match.activityID }) { observe(activity) }
        }

        var pending = plan.pendingStarts
        for action in plan.actions {
            switch action {
            case .end(let id):
                guard let activity = live.first(where: { $0.id == id }) else { continue }
                endedByUs.insert(id)
                await activity.end(nil, dismissalPolicy: .immediate)
            case .update(let id, let state):
                guard let activity = live.first(where: { $0.id == id }) else { continue }
                await activity.update(ActivityContent(state: state, staleDate: nil))
            case .start(let eventID):
                guard let timer = timers.first(where: { $0.eventID == eventID }),
                      ActivityAuthorizationInfo().areActivitiesEnabled else { continue }
                do {
                    let activity = try Activity.request(
                        attributes: timer.attributes,
                        content: ActivityContent(state: timer.state, staleDate: nil),
                        pushType: nil
                    )
                    ledger.started.insert(eventID)
                    eventIDByActivity[activity.id] = eventID
                    observe(activity)
                } catch {
                    // Not remembered, so a later reconcile (e.g. the next .active) tries again.
                    pending.append(eventID)
                    Self.log.error("Couldn't start a Live Activity: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        pendingStarts = pending
        #if DEBUG
        Self.log.notice("reconcile(\(String(describing: trigger), privacy: .public)) fg=\(isForeground) timers=\(timers.count) live=\(Activity<TimerActivityAttributes>.activities.filter { $0.activityState == .active }.count) actions=\(plan.actions.count) pending=\(pending.count)")
        #endif
        if !pending.isEmpty {
            Self.log.info("\(pending.count) Live Activity start(s) waiting for the foreground")
        }

        // Re-read first: a dismissal observed while we were awaiting is already stored and must survive.
        ledger.dismissed.formUnion(loadLedger().dismissed)
        ledger.prune(keeping: Set(timers.map(\.eventID)))
        if ledger != originalLedger { saveLedger(ledger) }
    }

    // MARK: Dismissal tracking

    /// Watches one activity. If it ends without us having ended it, the person swiped it away (or the system
    /// ended it after its time limit): remember that, so its timer doesn't get another activity.
    private func observe(_ activity: Activity<TimerActivityAttributes>) {
        guard observedActivities.insert(activity.id).inserted else { return }
        let id = activity.id
        let fallbackEventID = activity.attributes.eventID
        Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                self?.activityStopped(id: id, fallbackEventID: fallbackEventID)
                return
            }
        }
    }

    private func activityStopped(id: String, fallbackEventID: String?) {
        observedActivities.remove(id)
        let eventID = eventIDByActivity.removeValue(forKey: id) ?? fallbackEventID
        if endedByUs.remove(id) != nil { return }
        guard let eventID else { return }
        var ledger = loadLedger()
        ledger.dismissed.insert(eventID)
        saveLedger(ledger)
        Self.log.info("Live Activity dismissed by the person or the system; it won't be restarted for this timer")
    }

    // MARK: Ledger

    private func loadLedger() -> LiveActivityLedger {
        let defaults = UserDefaults.standard
        return LiveActivityLedger(
            started: Set(defaults.stringArray(forKey: Self.startedKey) ?? []),
            dismissed: Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        )
    }

    private func saveLedger(_ ledger: LiveActivityLedger) {
        let defaults = UserDefaults.standard
        defaults.set(ledger.started.sorted(), forKey: Self.startedKey)
        defaults.set(ledger.dismissed.sorted(), forKey: Self.dismissedKey)
    }

    #if DEBUG
    /// Debug launch argument support: forget everything and end every activity.
    func debugReset() async {
        for activity in Activity<TimerActivityAttributes>.activities {
            endedByUs.insert(activity.id)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        saveLedger(LiveActivityLedger())
    }
    #endif

    // MARK: Timers

    /// A running timer, as a Live Activity wants to see it.
    private struct RunningTimer {
        var eventID: String
        var attributes: TimerActivityAttributes
        var state: TimerActivityAttributes.ContentState
        var key: String { Self.key(babyID: attributes.babyID, kind: attributes.kind) }

        static func key(babyID: String, kind: EventKind) -> String { "\(babyID)|\(kind.rawValue)" }

        var planned: Planner.Timer {
            .init(eventID: eventID, babyID: attributes.babyID, kind: attributes.kind, state: state)
        }
    }

    private func runningTimers(in context: NSManagedObjectContext) -> [RunningTimer] {
        let request: NSFetchRequest<LogEvent> = LogEvent.fetchRequest()
        request.predicate = NSPredicate(
            format: "kindRaw IN %@ AND endDate == nil",
            [EventKind.sleep.rawValue, EventKind.breastfeed.rawValue]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        // Pull current values from the store for rows already in the context: a partner's change may have
        // landed in the store a moment before the view context merged it.
        request.shouldRefreshRefetchedObjects = true
        let events = (try? context.fetch(request)) ?? []

        var timers: [RunningTimer] = []
        var seen = Set<String>()
        for event in events where event.isRunning && !event.isDeleted {
            guard let baby = event.baby, let babyID = baby.uuid, let eventID = event.uuid, let start = event.startDate else { continue }
            let attributes = TimerActivityAttributes(
                babyID: babyID.uuidString,
                babyName: baby.displayName,
                kind: event.kind,
                eventID: eventID.uuidString
            )
            guard seen.insert(RunningTimer.key(babyID: attributes.babyID, kind: attributes.kind)).inserted else { continue }   // newest running timer per baby and kind

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
