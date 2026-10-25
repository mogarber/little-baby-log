import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsAgeNormsTests {
    @Test func wakeWindowsGrowWithAge() {
        var previous = AgeNorms.wakeWindow(ageDays: 0)
        for age in stride(from: 1, through: 1200, by: 1) {
            let range = AgeNorms.wakeWindow(ageDays: age)
            #expect(range.lowerBound >= previous.lowerBound, "lower bound shrank at \(age) days")
            #expect(range.upperBound >= previous.upperBound, "upper bound shrank at \(age) days")
            #expect(range.lowerBound > 0 && range.lowerBound < range.upperBound)
            previous = range
        }
    }

    @Test func wakeWindowAnchors() {
        #expect(AgeNorms.wakeWindow(ageDays: 10) == (35 * 60.0)...(60 * 60.0), "newborn")
        #expect(AgeNorms.wakeWindow(ageDays: 49) == (45 * 60.0)...(75 * 60.0), "7 weeks")
        #expect(AgeNorms.wakeWindow(ageDays: 200) == (120 * 60.0)...(180 * 60.0), "6-8 months")
        #expect(AgeNorms.wakeWindow(ageDays: 425) == (180 * 60.0)...(300 * 60.0), "14 months")
        #expect(AgeNorms.wakeWindow(ageDays: 600) == (300 * 60.0)...(360 * 60.0), "18-24 months: 5-6 h")
    }

    @Test func rowBoundariesAreExclusiveUpperBounds() {
        #expect(AgeNorms.wakeWindow(ageDays: 27) == AgeNorms.wakeWindow(ageDays: 0))
        #expect(AgeNorms.wakeWindow(ageDays: 28) == AgeNorms.wakeWindow(ageDays: 40))
        #expect(AgeNorms.wakeWindow(ageDays: 28) != AgeNorms.wakeWindow(ageDays: 27))
        #expect(AgeNorms.wakeWindow(ageDays: 100_000) == AgeNorms.wakeWindow(ageDays: 800))
    }

    @Test func napsPerDayFallAsBabiesGrow() {
        #expect(AgeNorms.napsPerDay(ageDays: 14) == 4...6)
        #expect(AgeNorms.napsPerDay(ageDays: 150) == 3...4)
        #expect(AgeNorms.napsPerDay(ageDays: 200) == 2...3)
        #expect(AgeNorms.napsPerDay(ageDays: 425) == 1...2)
        #expect(AgeNorms.napsPerDay(ageDays: 600) == 1...1)
        var previousMax = Int.max
        for age in 0..<1500 {
            let maximum = AgeNorms.napsPerDay(ageDays: age).upperBound
            #expect(maximum <= previousMax, "max naps grew at \(age) days")
            previousMax = maximum
        }
    }

    @Test func feedIntervalsStretchWithAge() {
        #expect(AgeNorms.feedInterval(ageDays: 10) == (2 * 3600.0)...(3 * 3600.0), "newborn: 2-3 h")
        #expect(AgeNorms.feedInterval(ageDays: 90) == (3 * 3600.0)...(4 * 3600.0), "2-4 months: 3-4 h")
        var previous = AgeNorms.feedInterval(ageDays: 0)
        for age in 1..<1000 {
            let range = AgeNorms.feedInterval(ageDays: age)
            #expect(range.lowerBound >= previous.lowerBound && range.upperBound >= previous.upperBound)
            previous = range
        }
    }

    @Test func bedtimeAndNightSleepNorms() {
        #expect(AgeNorms.typicalBedtime(ageDays: 49) == nil, "no steady bedtime yet")
        #expect(AgeNorms.typicalBedtime(ageDays: 150) == 20 * 60)
        #expect(AgeNorms.typicalBedtime(ageDays: 400) == 19 * 60 + 30)
        #expect(AgeNorms.minimumNightSleep(ageDays: 49) == 2 * 3600)
        #expect(AgeNorms.minimumNightSleep(ageDays: 200) == 3 * 3600)
    }

    @Test func ageInCalendarDays() {
        let calendar = TestSupport.utcCalendar
        let birth = TestSupport.utc(2026, 1, 1, 23, 50)
        #expect(AgeNorms.ageDays(birthDate: birth, now: TestSupport.utc(2026, 1, 1, 23, 55), calendar: calendar) == 0)
        #expect(AgeNorms.ageDays(birthDate: birth, now: TestSupport.utc(2026, 1, 2, 0, 5), calendar: calendar) == 1, "calendar days, not 24-hour spans")
        #expect(AgeNorms.ageDays(birthDate: birth, now: TestSupport.utc(2026, 2, 19, 12), calendar: calendar) == 49)
        #expect(AgeNorms.ageDays(birthDate: TestSupport.utc(2026, 6, 1), now: TestSupport.utc(2026, 1, 1), calendar: calendar) == 0, "a due date in the future")
    }

    @Test func ageAcrossDST() {
        let ny = Calendar.newYork
        let birth = ny.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let now = ny.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30))!
        #expect(AgeNorms.ageDays(birthDate: birth, now: now, calendar: ny) == 8)
    }
}
