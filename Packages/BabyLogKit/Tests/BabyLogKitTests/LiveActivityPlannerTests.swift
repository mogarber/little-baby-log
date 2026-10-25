import Testing
import Foundation
@testable import BabyLogKit

struct LiveActivityPlannerTests {
    typealias Planner = LiveActivityPlanner<Int>

    private func timer(_ event: String, baby: String = "b1", kind: EventKind = .sleep, state: Int = 1) -> Planner.Timer {
        .init(eventID: event, babyID: baby, kind: kind, state: state)
    }

    private func activity(
        _ id: String, event: String? = "e1", baby: String = "b1", kind: EventKind = .sleep, state: Int = 1, live: Bool = true
    ) -> Planner.Existing {
        .init(id: id, eventID: event, babyID: baby, kind: kind, state: state, isLive: live)
    }

    private func plan(
        timers: [Planner.Timer] = [], activities: [Planner.Existing] = [],
        dismissed: Set<String> = [], foreground: Bool = true
    ) -> Planner.Plan {
        Planner.plan(timers: timers, activities: activities, dismissed: dismissed, isForeground: foreground)
    }

    // MARK: starting

    @Test func startsMissingActivityInForeground() {
        let p = plan(timers: [timer("e1")])
        #expect(p.actions == [.start(eventID: "e1")])
        #expect(p.pendingStarts.isEmpty)
    }

    @Test func inBackgroundStartIsPendingNotAttempted() {
        let p = plan(timers: [timer("e1")], foreground: false)
        #expect(p.actions.isEmpty)
        #expect(p.pendingStarts == ["e1"])
    }

    @Test func pendingStartHappensOnceForeground() {
        let timers = [timer("e1")]
        #expect(plan(timers: timers, foreground: false).pendingStarts == ["e1"])
        #expect(plan(timers: timers, foreground: true).actions == [.start(eventID: "e1")])
    }

    @Test func dismissedTimerIsNeverStartedOrPending() {
        for foreground in [true, false] {
            let p = plan(timers: [timer("e1")], dismissed: ["e1"], foreground: foreground)
            #expect(p.actions.isEmpty)
            #expect(p.pendingStarts.isEmpty)
        }
    }

    @Test func dismissingOneTimerDoesNotBlockAnother() {
        let p = plan(timers: [timer("e1"), timer("e2", kind: .breastfeed)], dismissed: ["e1"])
        #expect(p.actions == [.start(eventID: "e2")])
    }

    @Test func eachBabyAndKindGetsItsOwnActivity() {
        let p = plan(timers: [timer("e1"), timer("e2", kind: .breastfeed), timer("e3", baby: "b2")])
        #expect(p.actions == [.start(eventID: "e1"), .start(eventID: "e2"), .start(eventID: "e3")])
    }

    @Test func endedActivityDoesNotCountAsCovering() {
        let p = plan(timers: [timer("e1")], activities: [activity("a1", live: false)])
        #expect(p.actions == [.start(eventID: "e1")])   // and the dead one is left alone, not "ended" again
    }

    // MARK: no duplicates

    @Test func existingActivityIsNeverStartedTwice() {
        let p = plan(timers: [timer("e1")], activities: [activity("a1")])
        #expect(p.actions.isEmpty)
        #expect(p.matches == [.init(activityID: "a1", eventID: "e1")])
    }

    @Test func duplicateActivitiesForOneTimerKeepFirstEndRest() {
        let p = plan(timers: [timer("e1")], activities: [activity("a1"), activity("a2")])
        #expect(p.actions == [.end(activityID: "a2")])
        #expect(p.matches.map(\.activityID) == ["a1"])
    }

    @Test func duplicateTimersForSameBabyAndKindYieldOneStart() {
        let p = plan(timers: [timer("e1"), timer("e2")])
        #expect(p.actions == [.start(eventID: "e1")])
    }

    @Test func legacyActivityWithoutEventIDIsAdoptedByBabyAndKind() {
        let p = plan(timers: [timer("e1")], activities: [activity("a1", event: nil)])
        #expect(p.actions.isEmpty)
        #expect(p.matches == [.init(activityID: "a1", eventID: "e1")])
    }

    @Test func legacyAndTaggedActivityForSameTimerDoNotDuplicate() {
        let p = plan(timers: [timer("e1")], activities: [activity("a1", event: "e1"), activity("a2", event: nil)])
        #expect(p.actions == [.end(activityID: "a2")])
    }

    // MARK: updating and ending

    @Test func updatesOnlyWhenStateChanged() {
        #expect(plan(timers: [timer("e1", state: 1)], activities: [activity("a1", state: 1)]).actions.isEmpty)
        #expect(plan(timers: [timer("e1", state: 2)], activities: [activity("a1", state: 1)]).actions
                == [.update(activityID: "a1", state: 2)])
    }

    @Test func endsActivityWhoseTimerFinished() {
        let p = plan(timers: [], activities: [activity("a1")])
        #expect(p.actions == [.end(activityID: "a1")])
    }

    @Test func newTimerReplacesFinishedOneEndsFirstThenStarts() {
        let p = plan(timers: [timer("e2")], activities: [activity("a1", event: "e1")])
        #expect(p.actions == [.end(activityID: "a1"), .start(eventID: "e2")])
    }

    @Test func newTimerReplacingOldOneWaitsInBackgroundButOldOneEndsNow() {
        let p = plan(timers: [timer("e2")], activities: [activity("a1", event: "e1")], foreground: false)
        #expect(p.actions == [.end(activityID: "a1")])
        #expect(p.pendingStarts == ["e2"])
    }

    @Test func backgroundStillUpdatesAndEnds() {
        let p = plan(
            timers: [timer("e1", state: 2)],
            activities: [activity("a1", state: 1), activity("a2", event: "e9", kind: .breastfeed)],
            foreground: false
        )
        #expect(p.actions == [.update(activityID: "a1", state: 2), .end(activityID: "a2")])
    }

    @Test func partnerFinishingTimerEndsActivityEvenInBackground() {
        let p = plan(timers: [], activities: [activity("a1")], foreground: false)
        #expect(p.actions == [.end(activityID: "a1")])
    }

    @Test func activityForDismissedTimerIsStillUpdated() {
        // dismissed only blocks *starting*; an activity that is somehow live keeps tracking its timer
        let p = plan(timers: [timer("e1", state: 2)], activities: [activity("a1")], dismissed: ["e1"])
        #expect(p.actions == [.update(activityID: "a1", state: 2)])
    }

    @Test func emptyInputsDoNothing() {
        #expect(plan() == Planner.Plan())
    }
}

struct LiveActivityLedgerTests {
    @Test func startedWithoutLiveActivityCountsAsDismissed() {
        let ledger = LiveActivityLedger(started: ["e1", "e2"], dismissed: [])
        #expect(ledger.suppressed(liveEventIDs: ["e2"]) == ["e1"])
    }

    @Test func neverStartedIsNotSuppressed() {
        let ledger = LiveActivityLedger(started: ["e1"], dismissed: [])
        #expect(!ledger.suppressed(liveEventIDs: []).contains("e2"))
    }

    @Test func observedDismissalIsSuppressedEvenIfStartedIsPruned() {
        let ledger = LiveActivityLedger(started: [], dismissed: ["e1"])
        #expect(ledger.suppressed(liveEventIDs: []) == ["e1"])
    }

    @Test func pruneForgetsFinishedTimers() {
        var ledger = LiveActivityLedger(started: ["e1", "e2"], dismissed: ["e2", "e3"])
        ledger.prune(keeping: ["e2"])
        #expect(ledger == LiveActivityLedger(started: ["e2"], dismissed: ["e2"]))
    }
}
