import Foundation

/// The small, shared pieces of arithmetic behind both predictors. Kept separate so each rule can be tested on
/// its own.
enum PredictionMath {
    /// Below this many samples a baby's own history is ignored (`PredictionBasis.typicalForAge`).
    static let minimumSamples = 3
    /// At this many samples the baby's own median gets the whole vote.
    static let fullTrustSamples = 10
    /// A gap shorter than `outlierLow` x the age range's lower bound, or longer than `outlierHigh` x its upper
    /// bound, is a bad log (a forgotten timer, a missed nap) and is dropped.
    static let outlierLow = 0.5
    static let outlierHigh = 2.0
    /// The result is kept inside the age range, widened by this fraction on each side.
    static let rangeWidening = 0.25

    /// Under 8 weeks the windows are tighter, because the rhythms are.
    static func halfWidth(ageDays: Int) -> TimeInterval {
        ageDays < 56 ? 10 * 60 : 15 * 60
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// `min(1, samples / 10)`, and 0 until there are `minimumSamples`.
    static func personalWeight(samples: Int) -> Double {
        guard samples >= minimumSamples else { return 0 }
        return min(1, Double(samples) / Double(fullTrustSamples))
    }

    static func clamp(_ value: TimeInterval, to norm: ClosedRange<TimeInterval>) -> TimeInterval {
        let low = norm.lowerBound * (1 - rangeWidening)
        let high = norm.upperBound * (1 + rangeWidening)
        return min(max(value, low), high)
    }

    /// The expected gap: the baby's own median mixed with the middle of the age range by `personalWeight`, then
    /// clamped to the widened range.
    static func blend(personalMedian: TimeInterval?, samples: Int, norm: ClosedRange<TimeInterval>) -> TimeInterval {
        let typical = AgeNorms.midpoint(norm)
        guard let personalMedian else { return clamp(typical, to: norm) }
        let weight = personalWeight(samples: samples)
        return clamp(weight * personalMedian + (1 - weight) * typical, to: norm)
    }

    static func isPlausible(_ gap: TimeInterval, norm: ClosedRange<TimeInterval>) -> Bool {
        gap >= norm.lowerBound * outlierLow && gap <= norm.upperBound * outlierHigh
    }

    static func basis(samples: Int, days: Int) -> PredictionBasis {
        guard samples >= minimumSamples else { return .typicalForAge }
        let days = max(1, days)
        return samples >= fullTrustSamples ? .personal(days: days) : .blended(days: days)
    }

    static func window(centre: Date, ageDays: Int) -> DateInterval {
        let half = halfWidth(ageDays: ageDays)
        return DateInterval(start: centre.addingTimeInterval(-half), end: centre.addingTimeInterval(half))
    }

    static func distinctDays(_ dates: [Date], calendar: Calendar) -> Int {
        Set(dates.map { calendar.startOfDay(for: $0) }).count
    }

    /// Minutes after local midnight (DST-safe: read from the calendar, not computed from seconds).
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `minutes` after local midnight on the calendar day of `day`.
    static func date(atMinuteOfDay minutes: Int, on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
