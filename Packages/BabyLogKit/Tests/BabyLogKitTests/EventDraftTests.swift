import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct EventDraftTests {
    let now = Date.now

    @Test func newEntryDefaults() {
        let sleep = EventDraft(kind: .sleep, now: now)
        #expect(sleep.startDate == now.addingTimeInterval(-3600))
        #expect(sleep.endDate == now)
        let nurse = EventDraft(kind: .breastfeed, now: now)
        #expect(nurse.startDate == now.addingTimeInterval(-900))
        #expect(nurse.endDate == nurse.startDate)
        #expect(!nurse.isRunning)
        let pump = EventDraft(kind: .pump, now: now)
        #expect(pump.pumpDuration == 900)
        #expect(pump.startDate == now.addingTimeInterval(-900))
        #expect(EventDraft(kind: .diaper, now: now).startDate == now)
        #expect(EventDraft(kind: .diaper, now: now).endDate == nil)
    }

    @Test func validationRules() {
        // Future start
        var d = EventDraft(kind: .diaper, now: now)
        #expect(d.validationMessage == nil)
        d.startDate = Date.now.addingTimeInterval(30)
        #expect(d.validationMessage == nil, "within 1 minute is allowed")
        d.startDate = Date.now.addingTimeInterval(5 * 60)
        #expect(d.validationMessage != nil)

        // Sleep
        var sleep = EventDraft(kind: .sleep, now: now)
        #expect(sleep.validationMessage == nil)
        sleep.endDate = sleep.startDate
        #expect(sleep.validationMessage != nil)
        sleep.endDate = sleep.startDate.addingTimeInterval(-60)
        #expect(sleep.validationMessage != nil)
        sleep.endDate = sleep.startDate.addingTimeInterval(25 * 3600)
        #expect(sleep.validationMessage != nil)
        sleep.endDate = sleep.startDate.addingTimeInterval(24 * 3600)
        #expect(sleep.validationMessage == nil)
        sleep.endDate = nil // still asleep
        #expect(sleep.validationMessage == nil)
        #expect(sleep.isRunning)

        // Breastfeed
        var nurse = EventDraft(kind: .breastfeed, now: now)
        #expect(nurse.validationMessage != nil)
        nurse.leftSeconds = 60
        #expect(nurse.validationMessage == nil)
        nurse.leftSeconds = 0
        nurse.endDate = nil // running timer needs no duration
        #expect(nurse.validationMessage == nil)

        // Bottle
        var bottle = EventDraft(kind: .bottle, now: now)
        #expect(bottle.validationMessage != nil)
        bottle.amountML = 90
        #expect(bottle.validationMessage == nil)

        // Pump
        var pump = EventDraft(kind: .pump, now: now)
        #expect(pump.validationMessage != nil)
        pump.rightML = 30
        #expect(pump.validationMessage == nil)

        // Growth
        var growth = EventDraft(kind: .growth, now: now)
        #expect(growth.validationMessage != nil)
        growth.headCm = 35
        #expect(growth.validationMessage == nil)

        // Medicine
        var med = EventDraft(kind: .medicine, now: now)
        #expect(med.validationMessage != nil)
        med.medicineName = "   "
        #expect(med.validationMessage != nil)
        med.medicineName = "Tylenol"
        #expect(med.validationMessage == nil)

        // Solids have no requirements
        #expect(EventDraft(kind: .solids, now: now).validationMessage == nil)
    }

    @Test func roundTripAllKinds() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let start = TestSupport.utc(2026, 3, 10, 8)

        func roundTrip(_ kind: EventKind, configure: (inout EventDraft) -> Void) -> (EventDraft, EventDraft, LogEvent) {
            var draft = EventDraft(kind: kind, now: start)
            draft.startDate = start
            configure(&draft)
            let event = LogEvent.create(kind: kind, for: baby, start: start, in: ctx)
            draft.apply(to: event, now: start)
            let back = EventDraft(event: event)
            return (draft, back, event)
        }

        var (draft, back, event) = roundTrip(.sleep) { $0.endDate = start.addingTimeInterval(5400); $0.notes = " nap \n" }
        #expect(event.notes == "nap")
        draft.notes = "nap"
        #expect(back == draft)

        (draft, back, event) = roundTrip(.breastfeed) {
            $0.leftSeconds = 300; $0.rightSeconds = 240; $0.lastSide = .right; $0.endDate = start
        }
        #expect(event.endDate == start.addingTimeInterval(540))
        draft.endDate = start.addingTimeInterval(540)
        #expect(back == draft)

        (draft, back, _) = roundTrip(.bottle) { $0.amountML = 120; $0.bottleContent = .breastMilk }
        #expect(back == draft)
        #expect(back.endDate == nil)

        (draft, back, _) = roundTrip(.solids) { $0.foodName = "Banana" }
        #expect(back == draft)

        (draft, back, _) = roundTrip(.diaper) { $0.diaperKind = .mixed }
        #expect(back == draft)

        (draft, back, event) = roundTrip(.pump) { $0.leftML = 60; $0.rightML = 50; $0.pumpDuration = 1200 }
        #expect(event.endDate == start.addingTimeInterval(1200))
        draft.endDate = start.addingTimeInterval(1200)
        #expect(back == draft)
        #expect(back.pumpDuration == 1200)

        (draft, back, _) = roundTrip(.growth) { $0.weightKg = 4.25; $0.lengthCm = 55.5; $0.headCm = 37 }
        #expect(back == draft)

        (draft, back, event) = roundTrip(.medicine) { $0.medicineName = " Tylenol "; $0.dose = "2.5 ml" }
        #expect(event.medicineName == "Tylenol")
        draft.medicineName = "Tylenol"
        #expect(back == draft)
    }

    @Test func applyRunningBreastfeedOnlyWritesStartAndNotes() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let t0 = TestSupport.utc(2026, 3, 10, 8)
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: t0, in: ctx)
        event.startSide(.left, at: t0)
        event.pauseNursing(at: t0.addingTimeInterval(100))

        var draft = EventDraft(event: event)
        #expect(draft.isRunning)
        draft.startDate = t0.addingTimeInterval(-60)
        draft.notes = "fussy"
        draft.leftSeconds = 9999 // must be ignored
        draft.apply(to: event, now: t0.addingTimeInterval(200))
        #expect(event.startDate == t0.addingTimeInterval(-60))
        #expect(event.notes == "fussy")
        #expect(event.leftSeconds == 100)
        #expect(event.endDate == nil)
        #expect(event.modifiedAt == t0.addingTimeInterval(200))
    }

    @Test func emptyNotesBecomeNil() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let event = LogEvent.create(kind: .diaper, for: baby, in: ctx)
        event.notes = "old"
        var draft = EventDraft(event: event)
        draft.notes = "  \n "
        draft.apply(to: event)
        #expect(event.notes == nil)
    }
}
