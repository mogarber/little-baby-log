import Testing
import Foundation
@testable import BabyLogKit

struct DurationFormatTests {
    @Test func shortFormat() {
        #expect(DurationFormat.short(3900) == "1h 5m")
        #expect(DurationFormat.short(7200) == "2h")
        #expect(DurationFormat.short(720) == "12m")
        #expect(DurationFormat.short(45) == "<1m")
        #expect(DurationFormat.short(0) == "0m")
        #expect(DurationFormat.short(-30) == "0m")
        #expect(DurationFormat.short(3599) == "59m")
    }

    @Test func clockFormat() {
        #expect(DurationFormat.clock(309) == "5:09")
        #expect(DurationFormat.clock(3909) == "1:05:09")
        #expect(DurationFormat.clock(0) == "0:00")
        #expect(DurationFormat.clock(-5) == "0:00")
    }
}

struct BabyAgeTests {
    let cal = TestSupport.utcCalendar
    let now = TestSupport.utc(2026, 6, 15, 14, 30)

    func age(_ birth: Date) -> String {
        BabyAge.description(birthDate: birth, now: now, calendar: cal)
    }

    @Test func newborn() {
        #expect(age(TestSupport.utc(2026, 6, 15, 3)) == "Born today")
        #expect(age(TestSupport.utc(2026, 6, 14, 23)) == "1 day old")
        #expect(age(TestSupport.utc(2026, 6, 10)) == "5 days old")
    }

    @Test func weeks() {
        #expect(age(TestSupport.utc(2026, 6, 8)) == "1 week")
        #expect(age(TestSupport.utc(2026, 5, 23)) == "3 weeks, 2 days")
    }

    @Test func months() {
        #expect(age(TestSupport.utc(2026, 2, 8)) == "4 months, 1 week")
        #expect(age(TestSupport.utc(2026, 3, 15)) == "3 months")
    }

    @Test func years() {
        #expect(age(TestSupport.utc(2024, 3, 10)) == "2 years, 3 months")
        #expect(age(TestSupport.utc(2025, 6, 15)) == "1 year")
    }

    @Test func dueDate() {
        #expect(age(TestSupport.utc(2026, 6, 18)) == "Due in 3 days")
        #expect(age(TestSupport.utc(2026, 6, 16)) == "Due in 1 day")
    }
}

@MainActor
struct EventDescriberTests {
    let describer = EventDescriber(volumeUnit: .milliliters, unitSystem: .metric, locale: TestSupport.enUS)
    let now = TestSupport.utc(2026, 3, 10, 12)

    @Test func summaries() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)

        let sleep = LogEvent.create(kind: .sleep, for: baby, start: now.addingTimeInterval(-34 * 60), in: ctx)
        #expect(describer.summary(for: sleep, now: now) == "Asleep for 34m")
        sleep.endDate = now.addingTimeInterval(-34 * 60 + 80 * 60)
        #expect(describer.summary(for: sleep, now: now) == "1h 20m")

        let nurse = LogEvent.create(kind: .breastfeed, for: baby, start: now, in: ctx)
        nurse.leftSeconds = 480; nurse.rightSeconds = 360; nurse.endDate = now
        #expect(describer.summary(for: nurse, now: now) == "L 8m · R 6m")

        let bottle = LogEvent.create(kind: .bottle, for: baby, start: now, in: ctx)
        bottle.amountML = 120; bottle.bottleContent = .formula
        #expect(describer.summary(for: bottle, now: now) == "120 ml formula")
        let ozDescriber = EventDescriber(volumeUnit: .ounces, unitSystem: .imperial, locale: TestSupport.enUS)
        #expect(ozDescriber.summary(for: bottle, now: now) == "4.1 oz formula")

        let diaper = LogEvent.create(kind: .diaper, for: baby, start: now, in: ctx)
        diaper.diaperKind = .mixed
        #expect(describer.summary(for: diaper, now: now) == "Wet + dirty")

        let pump = LogEvent.create(kind: .pump, for: baby, start: now, in: ctx)
        pump.leftML = 60; pump.rightML = 50
        #expect(describer.summary(for: pump, now: now) == "L 60 ml · R 50 ml")

        let growth = LogEvent.create(kind: .growth, for: baby, start: now, in: ctx)
        growth.weightKg = 4.25; growth.lengthCm = 55; growth.headCm = 37
        #expect(describer.summary(for: growth, now: now) == "4.25 kg · 55 cm · head 37 cm")

        let med = LogEvent.create(kind: .medicine, for: baby, start: now, in: ctx)
        med.medicineName = "Tylenol"; med.dose = "2.5 ml"
        #expect(describer.summary(for: med, now: now) == "Tylenol · 2.5 ml")

        let solids = LogEvent.create(kind: .solids, for: baby, start: now, in: ctx)
        solids.foodName = "Avocado"
        #expect(describer.summary(for: solids, now: now) == "Avocado")
    }
}
