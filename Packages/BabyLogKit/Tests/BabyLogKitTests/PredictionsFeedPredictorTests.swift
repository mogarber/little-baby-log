import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsFeedPredictorTests {
    let s = Scenario()
    var calendar: Calendar { s.calendar }

    private func feeds(dayGap: Int = 150, nightGap: Int = 210, days: Int = 6) -> [FeedSample] {
        Synthetic.feeds(calendar: calendar, firstDay: s.firstDay, days: days, dayGap: dayGap, nightGap: nightGap)
    }

    private func predict(_ feeds: [FeedSample], ageDays: Int, at now: Date) -> FeedPrediction? {
        FeedPredictor.next(
            birthDate: s.birthDate(ageDays: ageDays, now: now),
            feeds: feeds.filter { $0.start <= now },
            now: now,
            calendar: calendar
        )
    }

    /// The history ends "today" (day 5 of the log starts on 2026-03-06).
    private var today: Date { TestSupport.utc(2026, 3, 6) }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date { Synthetic.at(calendar, day: today, minute: hour * 60 + minute) }

    @Test func sevenWeekOldDayFeedsAreAboutTwoAndAHalfHoursApart() throws {
        let log = feeds().filter { $0.start <= at(14, 40) }
        let last = try #require(log.last)
        let prediction = try #require(predict(log, ageDays: 49, at: at(14, 45)))
        let gap = minutes(from: last.start, to: prediction.centre)
        #expect((138...162).contains(gap), "day gap about 150, got \(gap)")
        #expect(prediction.around.duration == 20 * 60, "+/- 10 under 8 weeks")
        if case .personal = prediction.basis {} else { Issue.record("expected personal, got \(prediction.basis)") }
    }

    @Test func nightFeedsAreSpacedSeparately() throws {
        let log = feeds().filter { $0.start <= at(23, 30) }
        let last = try #require(log.last)
        let minute = clockMinutes(last.start, calendar)
        #expect(minute >= 19 * 60, "the last feed is a night feed, at \(minute / 60):\(minute % 60)")
        let prediction = try #require(predict(log, ageDays: 49, at: last.start.addingTimeInterval(600)))
        let gap = minutes(from: last.start, to: prediction.centre)
        #expect((198...222).contains(gap), "night gap about 210, got \(gap)")
    }

    @Test func dayAndNightGapsDifferForTheSameBaby() throws {
        // Day feeds every 150 minutes and night feeds every 240: the predictions must follow the bucket.
        let log = feeds(dayGap: 150, nightGap: 240)
        let dayLast = try #require(log.last(where: { $0.start <= at(12, 30) }))
        let day = try #require(predict(log, ageDays: 100, at: dayLast.start.addingTimeInterval(300)))
        let nightLast = try #require(log.last(where: { $0.start <= at(22, 30) && clockMinutes($0.start, calendar) >= 19 * 60 }))
        let night = try #require(predict(log, ageDays: 100, at: nightLast.start.addingTimeInterval(300)))
        let dayGap = minutes(from: dayLast.start, to: day.centre)
        let nightGap = minutes(from: nightLast.start, to: night.centre)
        #expect(nightGap - dayGap > 60, "day \(dayGap), night \(nightGap)")
    }

    @Test func bottlesCountAndSolidsAndOtherEventsDoNot() throws {
        var log = feeds().filter { $0.start <= at(14, 40) }
        #expect(log.contains { $0.kind == .bottle })
        let reference = try #require(predict(log, ageDays: 49, at: at(14, 45)))
        log.append(FeedSample(start: at(14, 50), kind: .solids))
        log.append(FeedSample(start: at(14, 55), kind: .diaper))
        let withExtras = try #require(predict(log, ageDays: 49, at: at(15)))
        #expect(withExtras == reference, "solids and diapers are not feeds")
    }

    @Test func feedsWithin20MinutesAreOneFeed() {
        let base = at(8)
        let merged = FeedPredictor.mergedStarts([
            FeedSample(start: base, kind: .breastfeed),
            FeedSample(start: base.addingTimeInterval(12 * 60), kind: .bottle),
            FeedSample(start: base.addingTimeInterval(19 * 60), kind: .bottle),
            FeedSample(start: base.addingTimeInterval(45 * 60), kind: .breastfeed),
            FeedSample(start: base.addingTimeInterval(3600 * 5), kind: .breastfeed),
        ], now: base.addingTimeInterval(86_400))
        #expect(merged == [base, base.addingTimeInterval(45 * 60), base.addingTimeInterval(5 * 3600)])
    }

    @Test func noFeedsMeansNoPrediction() {
        #expect(predict([], ageDays: 49, at: at(12)) == nil)
        #expect(predict([FeedSample(start: at(9), kind: .solids)], ageDays: 49, at: at(12)) == nil)
    }

    @Test func oneFeedIsTypicalForTheAge() throws {
        let last = at(9)
        let prediction = try #require(predict([FeedSample(start: last, kind: .breastfeed)], ageDays: 49, at: at(10)))
        // 7 weeks: 2-3.5 h, middle 2 h 45 min, +/- 10 minutes.
        #expect(prediction.basis == .typicalForAge)
        #expect(prediction.around == DateInterval(
            start: last.addingTimeInterval((165 - 10) * 60), end: last.addingTimeInterval((165 + 10) * 60)
        ))
    }

    @Test func blendWeightFollowsTheNumberOfGaps() throws {
        // Six feeds two hours apart: five gaps of 120 minutes against a 165 minute age middle.
        let log = (0..<6).map { FeedSample(start: at(8 + 2 * $0), kind: .breastfeed) }
        let prediction = try #require(predict(log, ageDays: 49, at: at(18, 30)))
        let expected = at(18).addingTimeInterval(142.5 * 60)
        #expect(abs(prediction.centre.timeIntervalSince(expected)) < 1, "half and half: 142.5 minutes")
        #expect(prediction.basis == .blended(days: 1))

        // Only two gaps: ignored.
        let short = Array(log.prefix(3))
        let ignored = try #require(predict(short, ageDays: 49, at: at(12, 30)))
        #expect(abs(ignored.centre.timeIntervalSince(at(12).addingTimeInterval(165 * 60))) < 1)
        #expect(ignored.basis == .typicalForAge)
    }

    @Test func personalIntervalIsClampedToTheWidenedAgeRange() throws {
        // 5 months (3.5-4.5 h, widened 2 h 37.5 min to 5 h 37.5 min) fed every 2 hours around the clock.
        let log = Synthetic.feeds(calendar: calendar, firstDay: s.firstDay, days: 6, dayGap: 120, nightGap: 120, firstFeed: 6 * 60, jitter: 0)
        let last = try #require(log.last(where: { $0.start <= at(14, 10) }))
        let prediction = try #require(predict(log, ageDays: 150, at: at(14, 20)))
        let gap = minutes(from: last.start, to: prediction.centre)
        #expect(abs(gap - 157.5) < 0.01, "2h37.5, got \(gap)")
        #expect(prediction.around.duration == 30 * 60)
    }

    @Test func missingLogsDoNotSkewTheMedian() throws {
        // A 9-hour hole (nobody logged overnight) is dropped as a bad gap.
        var log = feeds()
        log.removeAll { $0.start > at(0).addingTimeInterval(-9 * 3600) && $0.start < at(0) }
        let withHole = try #require(predict(log.filter { $0.start <= at(14, 40) }, ageDays: 49, at: at(14, 45)))
        let clean = try #require(predict(feeds().filter { $0.start <= at(14, 40) }, ageDays: 49, at: at(14, 45)))
        #expect(abs(withHole.centre.timeIntervalSince(clean.centre)) < 6 * 60)
    }

    @Test func aFeedDueAnHourAgoIsOverdueButMuchLaterIsDropped() throws {
        let last = at(9)
        let log = [FeedSample(start: last, kind: .breastfeed)]
        // Typical 165 min -> window ends 09:00 + 175 min = 11:55.
        #expect(predict(log, ageDays: 49, at: at(12, 30)) != nil)
        #expect(predict(log, ageDays: 49, at: at(13, 10)) == nil)
    }

    @Test func onlyTheLastThreeDaysCount() throws {
        // Four days ago the baby fed hourly; that must not drag the estimate down.
        var log = feeds().filter { $0.start > at(0).addingTimeInterval(-3 * 86_400 + 3600) }
        let hourly = (0..<20).map { FeedSample(start: at(0).addingTimeInterval(-4 * 86_400 + Double($0) * 3600), kind: .breastfeed) }
        log = hourly + log
        let now = at(14, 45)
        let last = try #require(log.last(where: { $0.start <= at(14, 40) }))
        let prediction = try #require(predict(log, ageDays: 49, at: now))
        #expect(minutes(from: last.start, to: prediction.centre) > 135)
    }
}
