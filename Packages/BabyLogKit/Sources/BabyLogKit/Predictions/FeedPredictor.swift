import Foundation

/// Predicts when the baby will next want to feed.
///
/// - Feeds are breastfeeds and bottles. Two within 20 minutes of each other (a top-up bottle after nursing) are
///   one feed.
/// - The gaps between feed *starts* over the last 3 days are split into day (07:00-19:00, by the earlier feed)
///   and night, because babies space night feeds differently. The median of the matching bucket is used; with
///   fewer than 3 gaps in it, all gaps together.
/// - Gaps outside 0.5x-2x of the age range are dropped, then the same blend as sleep applies: personal weight
///   `min(1, samples / 10)`, clamped to the age range widened by 25%.
/// - The window is that long after the latest feed's start, +/- 15 minutes (+/- 10 under 8 weeks). Nothing is
///   predicted when there is no feed yet, or when the window passed more than an hour ago (the log is probably
///   missing a feed).
public enum FeedPredictor {
    static let historyDays = 3
    static let mergeWithin: TimeInterval = 20 * 60
    static let staleAfter: TimeInterval = 60 * 60
    /// Feeds starting at or after this minute of the day, and before `dayEnd`, count as daytime feeds.
    static let dayStart = 7 * 60
    static let dayEnd = 19 * 60

    public static func next(birthDate: Date, feeds: [FeedSample], now: Date, calendar: Calendar) -> FeedPrediction? {
        let ageDays = AgeNorms.ageDays(birthDate: birthDate, now: now, calendar: calendar)
        let norm = AgeNorms.feedInterval(ageDays: ageDays)

        let starts = mergedStarts(feeds, now: now)
        guard let last = starts.last else { return nil }

        let since = now.addingTimeInterval(-TimeInterval(historyDays) * 86_400)
        var day: [(start: Date, gap: TimeInterval)] = []
        var night: [(start: Date, gap: TimeInterval)] = []
        for (earlier, later) in zip(starts, starts.dropFirst()) where earlier >= since {
            let gap = later.timeIntervalSince(earlier)
            guard PredictionMath.isPlausible(gap, norm: norm) else { continue }
            let minute = PredictionMath.minuteOfDay(earlier, calendar: calendar)
            if minute >= dayStart && minute < dayEnd {
                day.append((earlier, gap))
            } else {
                night.append((earlier, gap))
            }
        }

        let lastMinute = PredictionMath.minuteOfDay(last, calendar: calendar)
        let isDay = lastMinute >= dayStart && lastMinute < dayEnd
        var chosen = isDay ? day : night
        if chosen.count < PredictionMath.minimumSamples { chosen = day + night }

        let gap = PredictionMath.blend(
            personalMedian: PredictionMath.median(chosen.map(\.gap)),
            samples: chosen.count,
            norm: norm
        )
        let window = PredictionMath.window(centre: last.addingTimeInterval(gap), ageDays: ageDays)
        guard now.timeIntervalSince(window.end) <= staleAfter else { return nil }

        return FeedPrediction(
            around: window,
            basis: PredictionMath.basis(
                samples: chosen.count,
                days: PredictionMath.distinctDays(chosen.map(\.start), calendar: calendar)
            )
        )
    }

    /// Start times of the feeds up to now, oldest first, with near-duplicates merged.
    static func mergedStarts(_ feeds: [FeedSample], now: Date) -> [Date] {
        var result: [Date] = []
        for start in feeds.filter({ $0.kind.isFeed && $0.start <= now }).map(\.start).sorted() {
            if let last = result.last, start.timeIntervalSince(last) < mergeWithin { continue }
            result.append(start)
        }
        return result
    }
}
