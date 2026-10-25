import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsMathTests {
    let norm: ClosedRange<TimeInterval> = (120 * 60.0)...(180 * 60.0)   // 2-3 h

    @Test func medianHandlesOddEvenAndEmpty() {
        #expect(PredictionMath.median([]) == nil)
        #expect(PredictionMath.median([5]) == 5)
        #expect(PredictionMath.median([9, 1, 5]) == 5)
        #expect(PredictionMath.median([1, 2, 10, 20]) == 6)
    }

    @Test func personalWeightRamps() {
        #expect(PredictionMath.personalWeight(samples: 0) == 0)
        #expect(PredictionMath.personalWeight(samples: 2) == 0, "under 3 samples the logs are ignored")
        #expect(PredictionMath.personalWeight(samples: 3) == 0.3)
        #expect(PredictionMath.personalWeight(samples: 5) == 0.5)
        #expect(PredictionMath.personalWeight(samples: 10) == 1)
        #expect(PredictionMath.personalWeight(samples: 40) == 1, "capped at 1")
    }

    @Test func blendMixesPersonalMedianAndAgeMidpoint() {
        let mid = 150 * 60.0
        let personal = 130 * 60.0
        #expect(PredictionMath.blend(personalMedian: nil, samples: 0, norm: norm) == mid)
        #expect(PredictionMath.blend(personalMedian: personal, samples: 2, norm: norm) == mid)
        // 5 samples: half and half.
        #expect(PredictionMath.blend(personalMedian: personal, samples: 5, norm: norm) == 140 * 60.0)
        // 3 samples: 30% own.
        let thirty = PredictionMath.blend(personalMedian: personal, samples: 3, norm: norm)
        #expect(abs(thirty - (0.3 * personal + 0.7 * mid)) < 1e-6)
        #expect(PredictionMath.blend(personalMedian: personal, samples: 10, norm: norm) == personal)
    }

    @Test func blendClampsToTheRangeWidenedBy25Percent() {
        // 2-3 h widened by 25%: 90 min to 225 min.
        #expect(PredictionMath.blend(personalMedian: 70 * 60, samples: 20, norm: norm) == 90 * 60.0)
        #expect(PredictionMath.blend(personalMedian: 330 * 60, samples: 20, norm: norm) == 225 * 60.0)
        #expect(PredictionMath.blend(personalMedian: 200 * 60, samples: 20, norm: norm) == 200 * 60.0, "inside the widened range")
        #expect(PredictionMath.clamp(1, to: norm) == 90 * 60.0)
    }

    @Test func outliersAreHalfToDoubleTheRange() {
        #expect(!PredictionMath.isPlausible(59 * 60, norm: norm))
        #expect(PredictionMath.isPlausible(60 * 60, norm: norm))
        #expect(PredictionMath.isPlausible(360 * 60, norm: norm))
        #expect(!PredictionMath.isPlausible(361 * 60, norm: norm))
    }

    @Test func basisThresholds() {
        #expect(PredictionMath.basis(samples: 0, days: 0) == .typicalForAge)
        #expect(PredictionMath.basis(samples: 2, days: 2) == .typicalForAge)
        #expect(PredictionMath.basis(samples: 3, days: 3) == .blended(days: 3))
        #expect(PredictionMath.basis(samples: 9, days: 5) == .blended(days: 5))
        #expect(PredictionMath.basis(samples: 10, days: 7) == .personal(days: 7))
        #expect(PredictionMath.basis(samples: 50, days: 0) == .personal(days: 1), "at least one day")
        #expect(PredictionBasis.typicalForAge.days == nil)
        #expect(PredictionBasis.blended(days: 4).days == 4)
    }

    @Test func windowIsPlusMinus15MinutesOr10ForNewborns() {
        let centre = TestSupport.utc(2026, 3, 1, 14, 30)
        let older = PredictionMath.window(centre: centre, ageDays: 100)
        #expect(older.start == TestSupport.utc(2026, 3, 1, 14, 15))
        #expect(older.end == TestSupport.utc(2026, 3, 1, 14, 45))
        let newborn = PredictionMath.window(centre: centre, ageDays: 55)
        #expect(newborn.duration == 20 * 60)
        #expect(PredictionMath.window(centre: centre, ageDays: 56).duration == 30 * 60)
    }

    @Test func clockHelpersFollowTheCalendarAcrossDST() {
        let ny = Calendar.newYork
        // 2026-03-08 is the spring-forward day: 02:00 -> 03:00.
        let evening = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 19, minute: 15))!
        #expect(PredictionMath.minuteOfDay(evening, calendar: ny) == 19 * 60 + 15)
        let anchored = PredictionMath.date(atMinuteOfDay: 19 * 60 + 15, on: ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!, calendar: ny)
        #expect(anchored == evening)
        #expect(PredictionMath.distinctDays([evening, evening.addingTimeInterval(60), evening.addingTimeInterval(86_400)], calendar: ny) == 2)
    }
}
