import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsSleepHistoryTests {
    let calendar = TestSupport.utcCalendar
    let now = TestSupport.utc(2026, 3, 10, 15)

    private func t(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { TestSupport.utc(2026, 3, day, hour, minute) }

    private func history(_ sleeps: [SleepSession], ageDays: Int = 100, now: Date? = nil) -> SleepHistory {
        SleepHistory(sleeps: sleeps, ageDays: ageDays, now: now ?? self.now, calendar: calendar)
    }

    @Test func overnightSleepAcrossMidnightIsOneNightSession() {
        let h = history([
            SleepSession(start: t(8, 19, 30), end: t(9, 6, 45)),
            SleepSession(start: t(9, 8, 30), end: t(9, 9, 30)),
        ])
        #expect(h.sessions.map(\.isNight) == [true, false])
        #expect(h.sessions[0].duration == 11.25 * 3600)
        #expect(h.bedtimes.map(\.minuteOfDay) == [19 * 60 + 30])
        // Morning wake 06:45 -> nap at 08:30 is the first wake window of the day.
        #expect(h.napGaps == [.init(start: t(9, 6, 45), duration: 105 * 60, position: 1)])
    }

    @Test func nightWakingsAreNotWakeWindows() {
        // 19:00-23:00, awake 40 min, 23:40-03:00, awake 30 min, 03:30-06:30 (starts before 05:30: night).
        let h = history([
            SleepSession(start: t(8, 19), end: t(8, 23)),
            SleepSession(start: t(8, 23, 40), end: t(9, 3)),
            SleepSession(start: t(9, 3, 30), end: t(9, 6, 30)),
            SleepSession(start: t(9, 8, 15), end: t(9, 9, 15)),
        ], ageDays: 200)
        #expect(h.sessions.map(\.isNight) == [true, true, true, false])
        #expect(h.bedtimes.count == 1, "one bedtime, not three")
        #expect(h.napGaps.map(\.position) == [1])
        #expect(abs((h.napGaps.first?.duration ?? 0) - 105 * 60) < 1)
        #expect(h.bedGaps.isEmpty)
    }

    @Test func positionsCountNapsThroughTheDayAndBedGapIsSeparate() {
        let h = history([
            SleepSession(start: t(8, 19), end: t(9, 6, 30)),        // night
            SleepSession(start: t(9, 8, 20), end: t(9, 9, 30)),     // gap 110
            SleepSession(start: t(9, 11, 45), end: t(9, 13, 15)),   // gap 135
            SleepSession(start: t(9, 15, 55), end: t(9, 16, 30)),   // gap 160
            SleepSession(start: t(9, 19), end: t(10, 6, 30)),       // bed gap 150
            SleepSession(start: t(10, 8, 25), end: t(10, 9, 30)),   // next morning: gap 115, position 1 again
        ], ageDays: 200, now: t(10, 12))
        #expect(h.napGaps.map(\.position) == [1, 2, 3, 1])
        #expect(h.napGaps.map { $0.duration / 60 } == [110, 135, 160, 115])
        #expect(h.bedGaps.map { $0.duration / 60 } == [150])
        #expect(h.bedtimes.map(\.minuteOfDay) == [19 * 60, 19 * 60])
    }

    @Test func evenLongEveningSleepIsANapForYoungBabiesOnlyIfShort() {
        // 2 h evening sleep: a night sleep for a 7-week-old (minimum 2 h), an evening nap for a 6-month-old.
        let evening = [SleepSession(start: t(9, 19), end: t(9, 21))]
        #expect(history(evening, ageDays: 49).sessions.map(\.isNight) == [true])
        #expect(history(evening, ageDays: 190).sessions.map(\.isNight) == [false])
        // Before 17:30 never counts as night, however long.
        #expect(history([SleepSession(start: t(9, 16, 50), end: t(9, 21))], ageDays: 190).sessions.map(\.isNight) == [false])
    }

    @Test func briefWakingsAreMergedAndTinySleepsIgnored() {
        let h = history([
            SleepSession(start: t(9, 12), end: t(9, 12, 40)),
            SleepSession(start: t(9, 12, 50), end: t(9, 13, 30)),   // 10-minute break: same nap
            SleepSession(start: t(9, 14), end: t(9, 14, 5)),        // 5 minutes: an accidental tap
        ])
        #expect(h.sessions.count == 1)
        #expect(h.sessions[0].start == t(9, 12))
        #expect(h.sessions[0].end == t(9, 13, 30))
    }

    @Test func implausibleGapsAreDropped() {
        // 7 weeks: wake window 45-75 min, so plausible gaps are 22.5-150 min.
        let h = history([
            SleepSession(start: t(8, 21), end: t(9, 7)),
            SleepSession(start: t(9, 8, 5), end: t(9, 8, 50)),      // 65: kept
            SleepSession(start: t(9, 12, 50), end: t(9, 13, 30)),   // 240: a nap went unlogged, dropped
            SleepSession(start: t(9, 13, 55), end: t(9, 14, 30)),   // 25: kept
            SleepSession(start: t(9, 15, 40), end: t(9, 16, 15)),   // 70: kept
        ], ageDays: 49, now: t(9, 17))
        #expect(h.napGaps.map { $0.duration / 60 } == [65, 25, 70])
        #expect(h.napGaps.map(\.position) == [1, 3, 4], "a dropped gap still uses up its position")
        #expect(h.droppedGaps == 1)
    }

    @Test func runningAndFutureSleepsMeanAsleep() {
        #expect(history([SleepSession(start: t(10, 14), end: nil)]).isSleeping)
        #expect(history([SleepSession(start: t(10, 14), end: t(10, 16))]).isSleeping, "ends in the future")
        #expect(!history([SleepSession(start: t(10, 12), end: t(10, 13))]).isSleeping)
        #expect(!history([SleepSession(start: t(10, 16), end: t(10, 17))]).isSleeping, "hasn't started: ignored")
    }

    @Test func onlyTheLast14DaysCount() {
        let h = history([
            SleepSession(start: TestSupport.utc(2026, 2, 1, 12), end: TestSupport.utc(2026, 2, 1, 13)),
            SleepSession(start: t(10, 12), end: t(10, 13)),
        ])
        #expect(h.sessions.count == 1)
    }

    @Test func napsPerDayAndBedtimeSummaries() {
        let plan = SleepPlan.sixMonths
        let sleeps = Scenario().sleeps(plan, now: Scenario().now(12))
        let h = history(sleeps, ageDays: 190, now: Scenario().now(12))
        #expect(h.personalNapCount == 3)
        let bedtime = h.medianBedtime
        #expect(bedtime != nil && abs(bedtime! - (19 * 60 + 15)) <= 6)
        #expect(h.bedtimes.count == 7, "last 7 evenings")

        // Under 3 days of logs there is no personal nap count and no median bedtime.
        let fresh = history([
            SleepSession(start: t(8, 19), end: t(9, 6, 30)),
            SleepSession(start: t(9, 9), end: t(9, 10)),
        ], ageDays: 190)
        #expect(fresh.personalNapCount == nil)
        #expect(fresh.medianBedtime == nil)
    }
}
