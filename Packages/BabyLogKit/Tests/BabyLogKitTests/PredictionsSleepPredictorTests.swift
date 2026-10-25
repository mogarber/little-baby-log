import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsSleepPredictorTests {
    let s = Scenario()
    var calendar: Calendar { s.calendar }

    private func clock(_ date: Date, _ calendar: Calendar? = nil) -> String {
        let minute = clockMinutes(date, calendar ?? self.calendar)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    // MARK: Realistic babies

    @Test func sevenWeekOldGetsAShortNapWindow() throws {
        let now = s.now(10)
        let prediction = try #require(s.predict(.sevenWeeks, ageDays: 49, at: now))
        #expect(prediction.kind == .nap)
        #expect(prediction.window.duration == 20 * 60, "+/- 10 minutes under 8 weeks")
        let gap = try #require(prediction.gapMinutes)
        #expect((58...74).contains(gap), "60-75 minute wake windows, got \(gap)")
        #expect(prediction.basis == .personal(days: 13))
        // The window is ahead of the wake-up it counts from.
        #expect(prediction.window.start > prediction.lastWake!)
    }

    @Test func sixMonthOldFollowsHerOwnWindowsThroughThreeNaps() throws {
        // Morning: just woke up at 06:45.
        let morning = try #require(s.predict(.sixMonths, ageDays: 190, at: s.now(7, 30)))
        #expect(morning.kind == .nap)
        #expect((104...116).contains(try #require(morning.gapMinutes)), "first window is about 110 minutes")
        #expect(morning.window.duration == 30 * 60)

        // After nap 1 the second (longer) window applies.
        let afterNap1 = try #require(s.predict(.sixMonths, ageDays: 190, at: s.now(10, 15)))
        #expect(afterNap1.kind == .nap)
        #expect((120...132).contains(try #require(afterNap1.gapMinutes)), "second window is about 125 minutes")

        // After nap 2 the third, longest one.
        let afterNap2 = try #require(s.predict(.sixMonths, ageDays: 190, at: s.now(13, 40)))
        #expect(afterNap2.kind == .nap)
        #expect((154...166).contains(try #require(afterNap2.gapMinutes)), "third window is about 160 minutes")
        let start = clockMinutes(afterNap2.window.start, calendar)
        #expect(start > 15 * 60 && start < 16 * 60 + 30, "mid-afternoon, got \(clock(afterNap2.window.start))")
    }

    @Test func sixMonthOldGoesToBedAfterThirdNap() throws {
        let prediction = try #require(s.predict(.sixMonths, ageDays: 190, at: s.now(17, 10)))
        #expect(prediction.kind == .bedtime, "3 naps done, which is what she takes")
        let centre = clockMinutes(prediction.centre, calendar)
        #expect(abs(centre - (19 * 60 + 14)) <= 12, "around 7:15 PM, got \(clock(prediction.centre))")
        #expect(prediction.window.duration == 30 * 60)
        if case .personal = prediction.basis {} else { Issue.record("expected a personal basis, got \(prediction.basis)") }
    }

    @Test func fourteenMonthOldOnOneNap() throws {
        let morning = try #require(s.predict(.fourteenMonths, ageDays: 425, at: s.now(8)))
        #expect(morning.kind == .nap)
        let nap = clockMinutes(morning.centre, calendar)
        #expect(abs(nap - (11 * 60 + 45)) <= 12, "late morning nap, got \(clock(morning.centre))")

        let afterNap = try #require(s.predict(.fourteenMonths, ageDays: 425, at: s.now(14, 5)))
        #expect(afterNap.kind == .bedtime, "one nap is all she takes")
        let bed = clockMinutes(afterNap.centre, calendar)
        #expect(abs(bed - (18 * 60 + 45)) <= 15, "early evening, got \(clock(afterNap.centre))")
    }

    @Test func napVersusBedtimeFollowsTheBabysOwnNapCountNotJustTheAgeNorm() throws {
        // A 6-month-old (norm up to 3 naps at this age) who really takes two.
        let twoNaps = SleepPlan(wake: 7 * 60, windows: [150, 180], napLengths: [90, 60], bed: 19 * 60 + 30, jitter: 5)
        let now = s.now(15, 30)
        let sleeps = s.sleeps(twoNaps, now: now)
        let history = SleepHistory(sleeps: sleeps, ageDays: 190, now: now, calendar: calendar)
        #expect(history.personalNapCount == 2)
        let prediction = try #require(s.predict(twoNaps, ageDays: 190, at: now))
        #expect(prediction.kind == .bedtime)

        // The same day a nap earlier is still a nap.
        let earlier = try #require(s.predict(twoNaps, ageDays: 190, at: s.now(11, 30)))
        #expect(earlier.kind == .nap)
    }

    @Test func clockRuleSwitchesToBedtimeEvenBeforeTheNapCountIsReached() throws {
        // Three naps a day normally, but today's second nap ended late, at 15:30: another 160 minute window
        // would start at 18:10, inside the 90 minutes before her usual 19:14 bedtime.
        let now = s.now(15, 30)
        let sleeps = s.sleeps(.sixMonths, now: now).filter { $0.start < s.now(11, 0) }
            + [SleepSession(start: s.now(13, 0), end: s.now(15, 30))]
        let prediction = try #require(s.predict(sleeps: sleeps, ageDays: 190, at: now))
        #expect(prediction.kind == .bedtime)
    }

    // MARK: Typical-only

    @Test func withoutAnyLogsTheWindowCountsFromNowAndSaysTypical() throws {
        let now = s.now(10)
        let prediction = try #require(s.predict(sleeps: [], ageDays: 49, at: now))
        #expect(prediction.kind == .nap)
        #expect(prediction.basis == .typicalForAge)
        #expect(prediction.lastWake == nil)
        // 7 weeks: wake window 45-75 minutes, so 60 in the middle, +/- 10.
        #expect(prediction.window == DateInterval(start: now.addingTimeInterval(50 * 60), end: now.addingTimeInterval(70 * 60)))
    }

    @Test func typicalNapCountSwitchesToBedtime() throws {
        // A 7-month-old, nothing known about her except today's naps.
        func nap(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> SleepSession {
            SleepSession(start: s.now(h1, m1), end: s.now(h2, m2))
        }
        let twoNaps = [nap(9, 0, 10, 0), nap(12, 0, 13, 30)]
        let afterTwo = try #require(s.predict(sleeps: twoNaps, ageDays: 215, at: s.now(13, 45)))
        #expect(afterTwo.kind == .nap)
        #expect(afterTwo.basis == .typicalForAge)
        // 2.5 h (middle of 2-3 h) after the 13:30 wake-up: 16:00, +/- 15.
        #expect(afterTwo.window == DateInterval(start: s.now(15, 45), end: s.now(16, 15)))

        let threeNaps = twoNaps + [nap(15, 30, 16, 15)]
        let afterThree = try #require(s.predict(sleeps: threeNaps, ageDays: 215, at: s.now(16, 30)))
        #expect(afterThree.kind == .bedtime, "the age's maximum of 3 naps is done")
        #expect(afterThree.basis == .typicalForAge)
        // Wake window rule: 16:15 + 2.5 h = 18:45; the typical 19:30 bedtime has a quarter of the say: ~18:56.
        let centre = clockMinutes(afterThree.centre, calendar)
        #expect(abs(centre - (18 * 60 + 56)) <= 1, "got \(clock(afterThree.centre))")
    }

    @Test func fewerThanThreeSamplesAreIgnored() throws {
        // Two days with a single nap each: two wake-window samples, not enough.
        let two = Scenario(today: TestSupport.utc(2026, 3, 3), days: 2)
        let plan = SleepPlan(wake: 7 * 60, windows: [90], napLengths: [60], bed: 19 * 60)
        let prediction = try #require(two.predict(plan, ageDays: 190, at: two.now(7, 30)))
        #expect(prediction.basis == .typicalForAge)
        #expect(abs(prediction.gapMinutes! - 150) < 0.01, "the middle of 2-3 h")
    }

    // MARK: Blend weight, clamping, basis labels

    /// A 6-month-old (2-3 h wake windows) whose only nap follows a wake window of `window` minutes, logged for
    /// `days` days before today.
    private func onePerDay(window: Int, days: Int) throws -> SleepPrediction {
        let scenario = Scenario(today: TestSupport.utc(2026, 3, 1 + days), days: days)
        let plan = SleepPlan(wake: 7 * 60, windows: [window], napLengths: [60], bed: 19 * 60)
        return try #require(scenario.predict(plan, ageDays: 190, at: scenario.now(7, 30)))
    }

    @Test func personalWeightGrowsWithSamples() throws {
        // Own windows of 90 minutes; the age middle is 150.
        let three = try onePerDay(window: 90, days: 3)
        #expect(abs(three.gapMinutes! - (0.3 * 90 + 0.7 * 150)) < 0.01)
        #expect(three.basis == .blended(days: 3))

        let five = try onePerDay(window: 90, days: 5)
        #expect(abs(five.gapMinutes! - 120) < 0.01, "half and half")
        #expect(five.basis == .blended(days: 5))

        let ten = try onePerDay(window: 100, days: 10)
        #expect(abs(ten.gapMinutes! - 100) < 0.01, "ten samples: all her own")
        #expect(ten.basis == .personal(days: 10))
    }

    @Test func resultIsClampedToTheAgeRangeWidenedBy25Percent() throws {
        // 6 months: 120-180 min, widened to 90-225.
        let long = try onePerDay(window: 330, days: 14)
        #expect(abs(long.gapMinutes! - 225) < 0.01)
        let short = try onePerDay(window: 65, days: 14)
        #expect(abs(short.gapMinutes! - 90) < 0.01)
    }

    @Test func outlierGapsDoNotMoveTheEstimate() throws {
        let now = s.now(10, 15)
        let clean = s.sleeps(.sixMonths, now: now)
        // On three days nap 2 was never logged, so nap 1 -> nap 3 looks like a 6-hour wake window.
        let calendar = s.calendar
        let broken = clean.filter { sleep in
            let day = calendar.component(.day, from: sleep.start)
            let minute = clockMinutes(sleep.start, calendar)
            return !([4, 6, 9].contains(day) && minute > 11 * 60 + 30 && minute < 13 * 60)
        }
        #expect(broken.count == clean.count - 3)
        let history = SleepHistory(sleeps: broken, ageDays: 190, now: now, calendar: calendar)
        #expect(history.droppedGaps >= 3)
        let before = try #require(s.predict(sleeps: clean, ageDays: 190, at: now))
        let after = try #require(s.predict(sleeps: broken, ageDays: 190, at: now))
        #expect(abs(after.gapMinutes! - before.gapMinutes!) <= 3)
    }

    // MARK: Nothing to say

    @Test func runningSleepMeansNoPrediction() {
        var sleeps = s.sleeps(.sixMonths, now: s.now(8))
        sleeps.append(SleepSession(start: s.now(10, 5), end: nil))
        #expect(s.predict(sleeps: sleeps, ageDays: 190, at: s.now(10, 30)) == nil)
        // The scenario's own log has the baby asleep at 09:00 (nap 1), too.
        #expect(s.predict(.sixMonths, ageDays: 190, at: s.now(9)) == nil)
    }

    @Test func nightWakingsGetNoNapWindow() {
        // 02:58, awake after the first night stretch.
        #expect(s.predict(.sixMonths, ageDays: 190, at: s.now(2, 58)) == nil)
        // Evening wake-up after a 3-hour first stretch.
        let evening = [SleepSession(start: s.now(19), end: s.now(22))]
        #expect(s.predict(sleeps: evening, ageDays: 49, at: s.now(22, 10)) == nil)
        // An early riser at 05:15 gets predictions once 05:30 has passed.
        let riser = [SleepSession(start: s.now(19, 30).addingTimeInterval(-86_400), end: s.now(5, 15))]
        #expect(s.predict(sleeps: riser, ageDays: 190, at: s.now(5, 20)) == nil)
        #expect(s.predict(sleeps: riser, ageDays: 190, at: s.now(6)) != nil)
    }

    @Test func aWindowThatPassedLongAgoIsCountedFromNowInstead() throws {
        // Last logged: this morning's wake-up. Nothing since, and it is already 13:00.
        let sleeps = s.sleeps(.sixMonths, now: s.now(6, 50))
        let prediction = try #require(s.predict(sleeps: sleeps, ageDays: 190, at: s.now(13)))
        #expect(prediction.lastWake == nil)
        #expect(prediction.basis == .typicalForAge)
        #expect(prediction.kind == .nap)
        #expect(prediction.window == DateInterval(start: s.now(15, 15), end: s.now(15, 45)), "13:00 + 2.5 h, +/- 15 minutes")
    }

    @Test func aRecentlyPassedWindowIsKeptAsOverdue() throws {
        let sleeps = s.sleeps(.sixMonths, now: s.now(10, 15))
        let normal = try #require(s.predict(sleeps: sleeps, ageDays: 190, at: s.now(10, 15)))
        let late = normal.window.end.addingTimeInterval(30 * 60)
        let prediction = try #require(s.predict(sleeps: sleeps, ageDays: 190, at: late))
        #expect(prediction.window == normal.window)
        #expect(PredictionText.timing(of: prediction.window, at: late) == .overdue)
    }

    @Test func aStaleBedtimeIsDropped() {
        // Late evening, no logs: the typical bedtime window (14 months: 19:30) is long over.
        #expect(s.predict(sleeps: [], ageDays: 425, at: s.now(22)) == nil)
        // Not long over: still shown.
        #expect(s.predict(sleeps: [], ageDays: 425, at: s.now(20)) != nil)
    }

    @Test func nothingLoggedInTheEveningPredictsBedtimeFromTheClock() throws {
        let prediction = try #require(s.predict(sleeps: [], ageDays: 425, at: s.now(17, 30)))
        #expect(prediction.kind == .bedtime)
        #expect(prediction.window == DateInterval(start: s.now(19, 15), end: s.now(19, 45)))
        #expect(prediction.basis == .typicalForAge)
    }

    // MARK: Time zones

    @Test(arguments: [
        (2026, 3, 1, "spring forward on 2026-03-08"),
        (2026, 10, 25, "fall back on 2026-11-01"),
    ])
    func windowsStayOnTheLocalClockAcrossDST(year: Int, month: Int, day: Int, label: String) throws {
        let ny = Calendar.newYork
        let first = ny.date(from: DateComponents(year: year, month: month, day: day))!
        // The clocks change on day index 7 of each log, and "today" is that day.
        let changeDay = ny.date(byAdding: .day, value: 7, to: first)!
        let scenario = Scenario(calendar: ny, firstDay: first, today: changeDay, days: 8)

        // Mid-day on the change day, after nap 2 (about 13:30 local).
        let afterNap2 = scenario.now(13, 40)
        let nap = try #require(scenario.predict(.sixMonths, ageDays: 190, at: afterNap2))
        #expect(nap.kind == .nap, Comment(rawValue: label))
        let napStart = clockMinutes(nap.centre, ny)
        #expect(napStart > 15 * 60 + 40 && napStart < 16 * 60 + 40, "\(label): nap 3 around 16:10 local, got \(clock(nap.centre, ny))")

        // Evening: bedtime stays at 19:15 local, not an hour off.
        let evening = scenario.now(17, 10)
        let bed = try #require(scenario.predict(.sixMonths, ageDays: 190, at: evening))
        #expect(bed.kind == .bedtime, Comment(rawValue: label))
        let bedMinutes = clockMinutes(bed.centre, ny)
        #expect(abs(bedMinutes - (19 * 60 + 15)) <= 15, "\(label): bedtime around 19:15 local, got \(clock(bed.centre, ny))")

        // The usual bedtime is read in local time across the change as well.
        let history = SleepHistory(sleeps: scenario.sleeps(.sixMonths, now: evening), ageDays: 190, now: evening, calendar: ny)
        let median = try #require(history.medianBedtime)
        #expect(abs(median - (19 * 60 + 15)) <= 6, Comment(rawValue: label))
    }

    // MARK: Messy logs

    @Test func irregularLogsStillLandInTheAgeRange() {
        // Keep roughly half of a 6-month-old's sessions, chosen by a seeded pseudo-random.
        var jitter = SeededJitter(seed: 99)
        let full = Synthetic.sleeps(.sixMonths, calendar: calendar, firstDay: s.firstDay, days: 15)
        let sparse = full.filter { _ in jitter.minutes(9) > -4 }
        #expect(sparse.count < full.count && sparse.count > full.count / 2, "kept \(sparse.count) of \(full.count)")
        let norm = AgeNorms.wakeWindow(ageDays: 190)
        let low = norm.lowerBound * 0.75 / 60, high = norm.upperBound * 1.25 / 60

        var checked = 0
        for day in 8...14 {
            for hour in 6..<22 {
                let now = Synthetic.at(calendar, day: TestSupport.utc(2026, 3, 1 + day), minute: hour * 60 + 20)
                let sleeps = Synthetic.clip(sparse, to: now)
                guard let prediction = SleepPredictor.next(
                    birthDate: s.birthDate(ageDays: 190, now: now), sleeps: sleeps, now: now, calendar: calendar
                ) else { continue }
                checked += 1
                #expect(prediction.window.duration == 30 * 60)
                if prediction.kind == .nap, let gap = prediction.gapMinutes {
                    #expect(gap >= low - 0.01 && gap <= high + 0.01, "gap \(gap) outside \(low)-\(high)")
                }
                if prediction.lastWake == nil { #expect(prediction.basis == .typicalForAge) }
            }
        }
        #expect(checked > 30, "predictions exist for most of the day")
    }

    @Test func aBabyWithThreeDaysOfLogsIsBlendedNotPersonal() throws {
        let three = Scenario(today: TestSupport.utc(2026, 3, 3), days: 3)
        let prediction = try #require(three.predict(.sixMonths, ageDays: 190, at: three.now(14, 30)))
        #expect(prediction.kind == .nap)
        #expect(prediction.basis == .blended(days: 3))
        #expect(prediction.window.duration == 30 * 60)
    }
}
