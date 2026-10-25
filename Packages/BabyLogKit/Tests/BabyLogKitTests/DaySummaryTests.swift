import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct DaySummaryTests {
    let day1 = DateInterval(start: TestSupport.utc(2026, 3, 9), end: TestSupport.utc(2026, 3, 10))
    let day2 = DateInterval(start: TestSupport.utc(2026, 3, 10), end: TestSupport.utc(2026, 3, 11))

    @Test func overnightSleepIsSplitAcrossDays() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: day1.start, in: ctx)
        let night = LogEvent.create(kind: .sleep, for: baby, start: TestSupport.utc(2026, 3, 9, 22), in: ctx)
        night.endDate = TestSupport.utc(2026, 3, 10, 6)
        let nap = LogEvent.create(kind: .sleep, for: baby, start: TestSupport.utc(2026, 3, 10, 13), in: ctx)
        nap.endDate = TestSupport.utc(2026, 3, 10, 14, 30)

        let events = [night, nap]
        let now = TestSupport.utc(2026, 3, 10, 18)
        #expect(DaySummary(events: events, interval: day1, now: now).sleep == 2 * 3600)
        #expect(DaySummary(events: events, interval: day2, now: now).sleep == 7.5 * 3600)
    }

    @Test func runningSleepCountsToNow() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: day1.start, in: ctx)
        let running = LogEvent.create(kind: .sleep, for: baby, start: TestSupport.utc(2026, 3, 10, 20), in: ctx)
        let now = TestSupport.utc(2026, 3, 10, 22, 30)
        #expect(DaySummary(events: [running], interval: day2, now: now).sleep == 2.5 * 3600)
        #expect(DaySummary(events: [running], interval: day1, now: now).sleep == 0)
    }

    @Test func diapers() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: day1.start, in: ctx)
        let kinds: [DiaperKind] = [.wet, .wet, .dirty, .mixed, .dry]
        var events: [LogEvent] = []
        for (i, kind) in kinds.enumerated() {
            let e = LogEvent.create(kind: .diaper, for: baby, start: TestSupport.utc(2026, 3, 10, 6 + i), in: ctx)
            e.diaperKind = kind
            events.append(e)
        }
        let outside = LogEvent.create(kind: .diaper, for: baby, start: TestSupport.utc(2026, 3, 9, 6), in: ctx)
        outside.diaperKind = .wet
        events.append(outside)

        let s = DaySummary(events: events, interval: day2, now: TestSupport.utc(2026, 3, 10, 18))
        #expect(s.diaperCount == 5)
        #expect(s.wetCount == 3)    // 2 wet + 1 mixed
        #expect(s.dirtyCount == 2)  // 1 dirty + 1 mixed
        #expect(s.diapers[.dry] == 1)
    }

    @Test func feedsAndOthers() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: day1.start, in: ctx)
        let nurse = LogEvent.create(kind: .breastfeed, for: baby, start: TestSupport.utc(2026, 3, 10, 7), in: ctx)
        nurse.leftSeconds = 480; nurse.rightSeconds = 300; nurse.endDate = TestSupport.utc(2026, 3, 10, 7, 13)
        let bottle = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        bottle.amountML = 90
        let bottle2 = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 10, 12), in: ctx)
        bottle2.amountML = 60
        let solids = LogEvent.create(kind: .solids, for: baby, start: TestSupport.utc(2026, 3, 10, 12), in: ctx)
        let pump = LogEvent.create(kind: .pump, for: baby, start: TestSupport.utc(2026, 3, 10, 15), in: ctx)
        pump.leftML = 60; pump.rightML = 50
        let med = LogEvent.create(kind: .medicine, for: baby, start: TestSupport.utc(2026, 3, 10, 16), in: ctx)
        med.medicineName = "Vit D"

        let s = DaySummary(events: [nurse, bottle, bottle2, solids, pump, med], interval: day2, now: TestSupport.utc(2026, 3, 10, 20))
        #expect(s.feedCount == 3)
        #expect(s.nursing == 780)
        #expect(s.bottleML == 150)
        #expect(s.solidsCount == 1)
        #expect(s.pumpML == 110)
        #expect(s.medicineCount == 1)
        #expect(DaySummary() == DaySummary(events: [LogEvent](), interval: day2))
    }
}
