import Foundation

/// Pure decision logic for keeping Live Activities in step with running timers. No ActivityKit, no Core Data:
/// the app's `LiveActivityManager` feeds it what exists, performs the returned actions, and records the outcome.
///
/// `State` is the activity's content state (`TimerActivityAttributes.ContentState` in the app); the planner only
/// compares it for equality, so an update is emitted only when something actually changed.
public enum LiveActivityPlanner<State: Equatable & Sendable> {

    /// A running timer, at most one per baby and kind.
    public struct Timer: Equatable, Sendable {
        public var eventID: String
        public var babyID: String
        public var kind: EventKind
        public var state: State

        public init(eventID: String, babyID: String, kind: EventKind, state: State) {
            self.eventID = eventID
            self.babyID = babyID
            self.kind = kind
            self.state = state
        }

        var key: String { "\(babyID)|\(kind.rawValue)" }
    }

    /// An activity the system currently knows about.
    public struct Existing: Equatable, Sendable {
        public var id: String
        /// The event the activity was started for. nil for activities started by an older build; those are
        /// matched to the running timer of the same baby and kind.
        public var eventID: String?
        public var babyID: String
        public var kind: EventKind
        public var state: State
        /// Active or stale. Ended / dismissed activities are ignored entirely.
        public var isLive: Bool

        public init(id: String, eventID: String?, babyID: String, kind: EventKind, state: State, isLive: Bool = true) {
            self.id = id
            self.eventID = eventID
            self.babyID = babyID
            self.kind = kind
            self.state = state
            self.isLive = isLive
        }

        var key: String { "\(babyID)|\(kind.rawValue)" }
    }

    public enum Action: Equatable, Sendable {
        case end(activityID: String)
        case update(activityID: String, state: State)
        case start(eventID: String)
    }

    public struct Plan: Equatable, Sendable {
        /// Ends and updates first, then starts, so two activities for one baby and kind never overlap.
        public var actions: [Action] = []
        /// Timers that should have an activity but can't get one yet because the app isn't in the foreground.
        /// They start at the next reconcile with `isForeground == true`.
        public var pendingStarts: [String] = []
        /// Every kept activity paired with the timer it now represents (including legacy activities that had
        /// no event id), for the caller to remember.
        public var matches: [Match] = []

        public struct Match: Equatable, Sendable {
            public var activityID: String
            public var eventID: String
        }

        public init() {}
    }

    /// - Parameters:
    ///   - timers: running timers; if two share a baby and kind the first wins.
    ///   - activities: everything in `Activity.activities`.
    ///   - dismissed: events that must not get a (new) activity: the person swiped it away, or the system
    ///     ended it. See `LiveActivityLedger.suppressed`.
    ///   - isForeground: `Activity.request` only works while the app is in the foreground (or running a
    ///     Live Activity intent). Updates and ends work in the background and are always planned.
    public static func plan(
        timers: [Timer],
        activities: [Existing],
        dismissed: Set<String>,
        isForeground: Bool
    ) -> Plan {
        var plan = Plan()

        var seenKeys = Set<String>()
        let timers = timers.filter { seenKeys.insert($0.key).inserted }
        var claimed = Set<String>()   // event ids that already have an activity
        var starts: [Action] = []

        for activity in activities where activity.isLive {
            let timer: Timer?
            if let eventID = activity.eventID {
                timer = timers.first { $0.eventID == eventID }
            } else {
                timer = timers.first { $0.key == activity.key }
            }
            guard let timer, !claimed.contains(timer.eventID) else {
                plan.actions.append(.end(activityID: activity.id))   // timer finished, deleted, or already covered
                continue
            }
            claimed.insert(timer.eventID)
            plan.matches.append(.init(activityID: activity.id, eventID: timer.eventID))
            if activity.state != timer.state {
                plan.actions.append(.update(activityID: activity.id, state: timer.state))
            }
        }

        for timer in timers where !claimed.contains(timer.eventID) && !dismissed.contains(timer.eventID) {
            if isForeground {
                starts.append(.start(eventID: timer.eventID))
            } else {
                plan.pendingStarts.append(timer.eventID)
            }
        }
        plan.actions.append(contentsOf: starts)
        return plan
    }
}

/// What the app remembers about each timer's Live Activity, so a timer the person dismissed doesn't keep
/// coming back while one that never got an activity (app wasn't in the foreground) still gets one.
/// Persisted by the app as two sets of event uuids.
public struct LiveActivityLedger: Equatable, Sendable {
    /// An activity was requested for this event.
    public var started: Set<String>
    /// The activity ended without us ending it: swiped away from the Lock Screen / Dynamic Island, or
    /// ended by the system (time limit).
    public var dismissed: Set<String>

    public init(started: Set<String> = [], dismissed: Set<String> = []) {
        self.started = started
        self.dismissed = dismissed
    }

    /// Forget events whose timer is gone, so the sets can't grow without bound.
    public mutating func prune(keeping runningEventIDs: Set<String>) {
        started.formIntersection(runningEventIDs)
        dismissed.formIntersection(runningEventIDs)
    }

    /// Events that must not be started again. "Started, but no live activity now" is a dismissal too, even
    /// if it happened while the app wasn't running and couldn't observe it.
    public func suppressed(liveEventIDs: Set<String>) -> Set<String> {
        dismissed.union(started.subtracting(liveEventIDs))
    }
}
