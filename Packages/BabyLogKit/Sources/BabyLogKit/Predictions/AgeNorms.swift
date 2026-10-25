import Foundation

/// Typical sleep and feeding rhythms by age. These are only the starting point of a prediction; once a baby has
/// a few days of logs, their own pattern takes over (see `SleepPredictor` / `FeedPredictor`).
///
/// Basis: general ranges that pediatric sleep and feeding guidance commonly publishes (for example the American
/// Academy of Pediatrics and Sleep Foundation overviews of infant sleep and feeding, and widely shared
/// wake-window charts). They are a conservative composite, rounded to simple numbers and deliberately
/// not copied from any one source; individual babies vary a lot, and these ranges make no claim about what is
/// healthy. Ages are in days since birth, upper bounds exclusive.
public struct AgeNorms: Sendable {
    private struct Row<Value> {
        /// The row applies while `ageDays < upToDays`.
        let upToDays: Int
        let value: Value
    }

    private static func lookup<Value>(_ rows: [Row<Value>], _ ageDays: Int) -> Value {
        rows.first(where: { ageDays < $0.upToDays })?.value ?? rows[rows.count - 1].value
    }

    private static func minutes(_ range: ClosedRange<Double>) -> ClosedRange<TimeInterval> {
        (range.lowerBound * 60)...(range.upperBound * 60)
    }

    // MARK: Wake windows

    private static let wakeWindows: [Row<ClosedRange<Double>>] = [
        Row(upToDays: 28, value: 35...60),         // 0-4 weeks
        Row(upToDays: 56, value: 45...75),         // 4-8 weeks
        Row(upToDays: 84, value: 60...90),         // 2-3 months
        Row(upToDays: 120, value: 75...120),       // 3-4 months
        Row(upToDays: 180, value: 90...150),       // 4-6 months
        Row(upToDays: 240, value: 120...180),      // 6-8 months
        Row(upToDays: 365, value: 150...210),      // 8-12 months
        Row(upToDays: 450, value: 180...300),      // 12-15 months (two naps to one)
        Row(upToDays: 540, value: 240...360),      // 15-18 months
        Row(upToDays: 730, value: 300...360),      // 18-24 months
        Row(upToDays: Int.max, value: 300...420),  // 2 years and up
    ]

    /// How long a baby of this age is typically awake between sleeps, in seconds.
    public static func wakeWindow(ageDays: Int) -> ClosedRange<TimeInterval> {
        minutes(lookup(wakeWindows, ageDays))
    }

    // MARK: Naps per day

    private static let naps: [Row<ClosedRange<Int>>] = [
        Row(upToDays: 56, value: 4...6),
        Row(upToDays: 120, value: 3...5),
        Row(upToDays: 180, value: 3...4),
        Row(upToDays: 270, value: 2...3),
        Row(upToDays: 365, value: 2...2),
        Row(upToDays: 540, value: 1...2),
        Row(upToDays: 730, value: 1...1),
        Row(upToDays: Int.max, value: 0...1),
    ]

    /// How many daytime naps are typical at this age.
    public static func napsPerDay(ageDays: Int) -> ClosedRange<Int> {
        lookup(naps, ageDays)
    }

    // MARK: Feed intervals

    private static let feedIntervals: [Row<ClosedRange<Double>>] = [
        Row(upToDays: 28, value: 120...180),       // newborn: every 2-3 hours
        Row(upToDays: 56, value: 120...210),
        Row(upToDays: 120, value: 180...240),      // 2-4 months: every 3-4 hours
        Row(upToDays: 180, value: 210...270),
        Row(upToDays: 365, value: 240...300),      // with solids starting, milk feeds spread out
        Row(upToDays: Int.max, value: 240...360),
    ]

    /// How far apart feed starts typically are at this age, in seconds.
    public static func feedInterval(ageDays: Int) -> ClosedRange<TimeInterval> {
        minutes(lookup(feedIntervals, ageDays))
    }

    // MARK: Night

    /// A typical bedtime as minutes after midnight, or nil for young babies who have no steady one yet.
    public static func typicalBedtime(ageDays: Int) -> Int? {
        if ageDays < 84 { return nil }
        return ageDays < 180 ? 20 * 60 : 19 * 60 + 30
    }

    /// The shortest sleep that starts in the evening and still counts as "night sleep" (not an evening nap).
    public static func minimumNightSleep(ageDays: Int) -> TimeInterval {
        ageDays < 120 ? 2 * 3600 : 3 * 3600
    }

    // MARK: Helpers

    /// Whole calendar days from birth to `now`, never negative.
    public static func ageDays(birthDate: Date, now: Date, calendar: Calendar) -> Int {
        let birthDay = calendar.startOfDay(for: birthDate)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: birthDay, to: today).day ?? 0)
    }

    public static func midpoint(_ range: ClosedRange<TimeInterval>) -> TimeInterval {
        (range.lowerBound + range.upperBound) / 2
    }
}
