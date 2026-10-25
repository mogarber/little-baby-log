import Foundation
@testable import BabyLogKit

/// Synthetic baby histories for the prediction tests. Everything is deterministic (a seeded jitter), built in
/// local clock times of the given calendar, so the same plan works across a DST change.
struct SleepPlan {
    /// Morning wake, minutes after midnight.
    var wake: Int
    /// Wake window before each nap, in minutes. With `repeating`, the list cycles until bedtime nears.
    var windows: [Int]
    var napLengths: [Int]
    var repeating = false
    /// Night sleep start, minutes after midnight.
    var bed: Int
    /// Sleeping chunks of the night before each waking (the last chunk runs to the next morning wake), and the
    /// awake minutes after each chunk.
    var nightChunks: [Int] = []
    var nightAwakes: [Int] = []
    /// Random +/- minutes on every wake window and on bedtime.
    var jitter = 0
    /// Number of naps when not repeating (default: `windows.count`).
    var naps: Int { windows.count }

    /// 7 weeks: ~60-75 minute wake windows, short naps all day, bed around 21:00.
    static let sevenWeeks = SleepPlan(
        wake: 7 * 60, windows: [65, 70, 60, 75], napLengths: [45, 60, 90, 40, 50],
        repeating: true, bed: 21 * 60, nightChunks: [210, 190], nightAwakes: [45, 40], jitter: 5
    )
    /// 6 months: three naps with windows that grow through the day, bed 19:15.
    static let sixMonths = SleepPlan(
        wake: 6 * 60 + 45, windows: [110, 125, 160], napLengths: [75, 90, 40],
        bed: 19 * 60 + 15, nightChunks: [450], nightAwakes: [25], jitter: 5
    )
    /// 14 months: one nap after a five hour morning, bed five hours after it ends.
    static let fourteenMonths = SleepPlan(
        wake: 6 * 60 + 45, windows: [300], napLengths: [120], bed: 18 * 60 + 45,
        nightChunks: [], nightAwakes: [], jitter: 5
    )
}

/// A tiny seeded generator, so "random" jitter is reproducible.
struct SeededJitter {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }

    mutating func minutes(_ plusMinus: Int) -> Int {
        guard plusMinus > 0 else { return 0 }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = Int((state >> 33) % UInt64(2 * plusMinus + 1))
        return value - plusMinus
    }
}

enum Synthetic {
    static func at(_ calendar: Calendar, day: Date, minute: Int) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(minute * 60))
    }

    /// Sleeps for `days` days starting at `firstDay` (a start of day), including the night before the first
    /// morning. Sessions are complete; use `clip` to cut the log off at "now".
    static func sleeps(
        _ plan: SleepPlan,
        calendar: Calendar,
        firstDay: Date,
        days: Int,
        seed: UInt64 = 1,
        skipDays: Set<Int> = []
    ) -> [SleepSession] {
        var jitter = SeededJitter(seed: seed)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: firstDay)! }
        let wakes = (0...days).map { at(calendar, day: day($0), minute: plan.wake + jitter.minutes(plan.jitter)) }

        var result: [SleepSession] = []
        for offset in -1..<days {
            let bed = offset < 0
                ? nil
                : at(calendar, day: day(offset), minute: plan.bed + jitter.minutes(plan.jitter))
            // The night that ends on the morning of `offset + 1` starts at this day's bedtime.
            if let bed {
                let wake = wakes[offset + 1]
                var cursor = bed
                for (index, chunk) in plan.nightChunks.enumerated() {
                    let end = cursor.addingTimeInterval(TimeInterval(chunk * 60))
                    result.append(SleepSession(start: cursor, end: end))
                    cursor = end.addingTimeInterval(TimeInterval(plan.nightAwakes[index] * 60))
                }
                result.append(SleepSession(start: cursor, end: wake))
            } else {
                // The night before day 0: just a long sleep ending at the first wake.
                let start = at(calendar, day: day(-1), minute: plan.bed)
                result.append(SleepSession(start: start, end: wakes[0]))
            }
            guard offset >= 0, !skipDays.contains(offset) else { continue }

            // Naps of day `offset`.
            var cursor = wakes[offset]
            let bedStart = bed!
            var index = 0
            while true {
                if !plan.repeating && index >= plan.naps { break }
                let window = plan.windows[index % plan.windows.count] + jitter.minutes(plan.jitter)
                let start = cursor.addingTimeInterval(TimeInterval(window * 60))
                if plan.repeating && start.addingTimeInterval(45 * 60) > bedStart.addingTimeInterval(-60 * 60) { break }
                let length = plan.napLengths[index % plan.napLengths.count]
                let end = start.addingTimeInterval(TimeInterval(length * 60))
                result.append(SleepSession(start: start, end: end))
                cursor = end
                index += 1
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// What the app would have at `now`: sessions that haven't started are gone, one still going has no end.
    static func clip(_ sleeps: [SleepSession], to now: Date) -> [SleepSession] {
        sleeps.compactMap { sleep in
            guard sleep.start < now else { return nil }
            if let end = sleep.end, end > now { return SleepSession(start: sleep.start, end: nil) }
            return sleep
        }
    }

    /// Feeds: every `dayGap` minutes between 07:00 and 19:00 and every `nightGap` otherwise, alternating
    /// breast and bottle now and then.
    static func feeds(
        calendar: Calendar,
        firstDay: Date,
        days: Int,
        dayGap: Int,
        nightGap: Int,
        firstFeed: Int = 6 * 60 + 30,
        jitter: Int = 8,
        seed: UInt64 = 7
    ) -> [FeedSample] {
        var generator = SeededJitter(seed: seed)
        var result: [FeedSample] = []
        var cursor = at(calendar, day: firstDay, minute: firstFeed)
        let end = calendar.date(byAdding: .day, value: days, to: firstDay)!
        var count = 0
        while cursor < end {
            result.append(FeedSample(start: cursor, kind: count % 5 == 4 ? .bottle : .breastfeed))
            let minute = calendar.component(.hour, from: cursor) * 60 + calendar.component(.minute, from: cursor)
            let gap = (minute >= 7 * 60 && minute < 19 * 60) ? dayGap : nightGap
            cursor = cursor.addingTimeInterval(TimeInterval((gap + generator.minutes(jitter)) * 60))
            count += 1
        }
        return result
    }
}

extension Calendar {
    static var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
}

/// Minutes between two dates, for readable assertions.
func minutes(from a: Date, to b: Date) -> Double { b.timeIntervalSince(a) / 60 }

/// Local clock minutes after midnight.
func clockMinutes(_ date: Date, _ calendar: Calendar) -> Int {
    calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
}

/// Fifteen days of history ending "today" (2026-03-15, UTC unless a calendar is given).
struct Scenario {
    var calendar = TestSupport.utcCalendar
    var firstDay = TestSupport.utc(2026, 3, 1)
    var today = TestSupport.utc(2026, 3, 15)
    var days = 15

    func now(_ hour: Int, _ minute: Int = 0) -> Date {
        Synthetic.at(calendar, day: today, minute: hour * 60 + minute)
    }

    func birthDate(ageDays: Int, now: Date) -> Date {
        calendar.date(byAdding: .day, value: -ageDays, to: calendar.startOfDay(for: now))!
    }

    /// The log as the app would have it at `now`.
    func sleeps(_ plan: SleepPlan, now: Date, seed: UInt64 = 1, skipDays: Set<Int> = []) -> [SleepSession] {
        Synthetic.clip(
            Synthetic.sleeps(plan, calendar: calendar, firstDay: firstDay, days: days, seed: seed, skipDays: skipDays),
            to: now
        )
    }

    func predict(
        _ plan: SleepPlan,
        ageDays: Int,
        at now: Date,
        seed: UInt64 = 1
    ) -> SleepPrediction? {
        SleepPredictor.next(
            birthDate: birthDate(ageDays: ageDays, now: now),
            sleeps: sleeps(plan, now: now, seed: seed),
            now: now,
            calendar: calendar
        )
    }

    func predict(sleeps: [SleepSession], ageDays: Int, at now: Date) -> SleepPrediction? {
        SleepPredictor.next(birthDate: birthDate(ageDays: ageDays, now: now), sleeps: sleeps, now: now, calendar: calendar)
    }
}

extension SleepPrediction {
    /// Minutes from the wake-up it was counted from to the middle of the window.
    var gapMinutes: Double? { lastWake.map { minutes(from: $0, to: centre) } }
}
