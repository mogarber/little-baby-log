import Testing
import CoreData
import Foundation
@testable import BabyLogKit

@MainActor
struct DayRecapTests {
    // MARK: Fixtures

    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// A wall-clock time in New York.
    static func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, year: Int = 2026) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute; parts.second = second
        return newYork.date(from: parts)!
    }

    let calendar = DayRecapTests.newYork
    let context: NSManagedObjectContext
    let baby: Baby

    init() {
        let (_, ctx) = TestSupport.makeContext()
        context = ctx
        baby = Baby.create(name: "Ada", birthDate: Self.ny(1, 1, 0), in: ctx)
    }

    func sleep(_ start: Date, _ end: Date?) -> LogEvent {
        let event = LogEvent.create(kind: .sleep, for: baby, start: start, in: context)
        event.endDate = end
        return event
    }

    func diaper(_ start: Date, _ kind: DiaperKind = .wet) -> LogEvent {
        let event = LogEvent.create(kind: .diaper, for: baby, start: start, in: context)
        event.diaperKind = kind
        return event
    }

    func bottle(_ start: Date, ml: Double = 90) -> LogEvent {
        let event = LogEvent.create(kind: .bottle, for: baby, start: start, in: context)
        event.amountML = ml
        return event
    }

    func recap(_ day: Date, _ events: [LogEvent], now: Date) -> DayRecap {
        DayRecap(day: day, events: events, calendar: calendar, now: now)
    }

    // MARK: Overnight sleep

    @Test func overnightSleepIsSplitAcrossTwoDays() {
        let night = sleep(Self.ny(3, 9, 21, 30), Self.ny(3, 10, 6, 10))
        let now = Self.ny(3, 10, 18)
        let first = recap(Self.ny(3, 9, 12), [night], now: now)
        let second = recap(Self.ny(3, 10, 12), [night], now: now)

        #expect(first.sleepSpans.count == 1)
        #expect(first.sleepSpans[0].start == Self.ny(3, 9, 21, 30))
        #expect(first.sleepSpans[0].end == Self.ny(3, 10, 0))
        #expect(first.sleepSpans[0].continuesIntoNextDay)
        #expect(!first.sleepSpans[0].continuesFromPreviousDay)
        #expect(first.summary.sleep == 2.5 * 3600)

        #expect(second.sleepSpans.count == 1)
        #expect(second.sleepSpans[0].start == Self.ny(3, 10, 0))
        #expect(second.sleepSpans[0].end == Self.ny(3, 10, 6, 10))
        #expect(second.sleepSpans[0].continuesFromPreviousDay)
        #expect(!second.sleepSpans[0].continuesIntoNextDay)
        #expect(second.summary.sleep == 6 * 3600 + 10 * 60)

        // The sleep is an entry only on the day it started, and the wake-up shows on the second day.
        #expect(first.hours[21].events.count == 1)
        #expect(second.eventCount == 0)
        #expect(second.hours[6].wakeUps.count == 1)
        #expect(first.hours.allSatisfy { $0.wakeUps.isEmpty })

        // The bar: starts mid-hour on day one, runs the whole of hours 0-5 on day two, ends 10 minutes into hour 6.
        let evening = first.hours[21].sleepSlices
        #expect(evening.count == 1 && evening[0].from == 0.5 && evening[0].to == 1 && evening[0].startsHere && !evening[0].endsHere)
        #expect(first.hours[23].sleepSlices[0].to == 1 && !first.hours[23].sleepSlices[0].endsHere)
        #expect(second.hours[0].sleepSlices[0].from == 0 && !second.hours[0].sleepSlices[0].startsHere)
        #expect(second.hours[3].isFullyAsleep)
        let morning = second.hours[6].sleepSlices[0]
        #expect(abs(morning.to - 10.0 / 60.0) < 1e-9 && morning.endsHere)
        #expect(second.hours[7].sleepSlices.isEmpty)
        #expect(!second.isEmpty)
    }

    @Test func sleepEndingExactlyAtMidnightShowsItsWakeUpOnTheNextDay() {
        let night = sleep(Self.ny(3, 9, 22), Self.ny(3, 10, 0))
        let now = Self.ny(3, 11, 9)
        let first = recap(Self.ny(3, 9, 12), [night], now: now)
        let second = recap(Self.ny(3, 10, 12), [night], now: now)
        #expect(first.sleepSpans[0].end == Self.ny(3, 10, 0))
        #expect(!first.sleepSpans[0].continuesIntoNextDay)
        #expect(second.sleepSpans.isEmpty)
        #expect(second.hours[0].wakeUps.count == 1)
        #expect(!second.isEmpty)
    }

    @Test func shortSleepInsideOneHourHasNoWakeUpEntry() {
        let nap = sleep(Self.ny(3, 10, 14, 5), Self.ny(3, 10, 14, 50))
        let day = recap(Self.ny(3, 10, 12), [nap], now: Self.ny(3, 10, 20))
        #expect(day.hours[14].events.count == 1)
        #expect(day.hours[14].wakeUps.isEmpty)
        let slice = day.hours[14].sleepSlices[0]
        #expect(slice.startsHere && slice.endsHere)
        #expect(slice.from == 5.0 / 60.0 && slice.to == 50.0 / 60.0)
    }

    // MARK: Running timers

    @Test func runningSleepAndNursingTodayEndAtNow() {
        let now = Self.ny(3, 10, 14, 30)
        let asleep = sleep(Self.ny(3, 10, 13, 10), nil)
        let nursing = LogEvent.create(kind: .breastfeed, for: baby, start: Self.ny(3, 10, 14, 5), in: context)
        nursing.startSide(.left, at: Self.ny(3, 10, 14, 5))
        let day = recap(Self.ny(3, 10, 9), [asleep, nursing], now: now)

        #expect(day.isToday)
        #expect(day.currentHourIndex == 14)
        #expect(day.sleepSpans[0].isRunning)
        #expect(day.sleepSpans[0].end == now)
        #expect(day.summary.sleep == 80 * 60)
        #expect(day.summary.nursing == 25 * 60)
        #expect(day.hours[13].events.map(\.kind) == [.sleep])
        #expect(day.hours[14].events.map(\.kind) == [.breastfeed])
        let slice = day.hours[14].sleepSlices[0]
        #expect(slice.to == 0.5 && slice.endsHere)
        #expect(day.hours[13].sleepSlices[0].from == 10.0 / 60.0)
        #expect(day.hours[13].wakeUps.isEmpty && day.hours[14].wakeUps.isEmpty)
        // A running sleep has no wake-up, and the quiet hours before it are collapsed.
        #expect(day.napCount == 1)
    }

    @Test func runningTimersOnPastDays() {
        let now = Self.ny(3, 12, 10)
        let asleep = sleep(Self.ny(3, 10, 20), nil)
        let nursing = LogEvent.create(kind: .breastfeed, for: baby, start: Self.ny(3, 10, 21), in: context)
        nursing.startSide(.right, at: Self.ny(3, 10, 21))
        let events = [asleep, nursing]

        let started = recap(Self.ny(3, 10, 12), events, now: now)
        #expect(started.sleepSpans[0].end == Self.ny(3, 11, 0))
        #expect(started.sleepSpans[0].continuesIntoNextDay && started.sleepSpans[0].isRunning)
        #expect(started.summary.sleep == 4 * 3600)
        #expect(started.hours[21].events.map(\.kind) == [.breastfeed])
        #expect(!started.isToday)
        #expect(started.currentHourIndex == nil)
        #expect(started.visibleHours.count == 24)

        let middle = recap(Self.ny(3, 11, 12), events, now: now)
        #expect(middle.summary.sleep == 24 * 3600)
        #expect(middle.eventCount == 0)
        #expect(middle.hours.allSatisfy { $0.isFullyAsleep })
        #expect(middle.rows.count == 1)
        if case .quiet(let run) = middle.rows[0] {
            #expect(run.hours.count == 24 && run.isAsleep && run.asleepDuration == 24 * 3600)
        } else {
            Issue.record("expected one quiet asleep row")
        }

        let today = recap(Self.ny(3, 12, 9), events, now: now)
        #expect(today.sleepSpans[0].end == now)
        #expect(today.summary.sleep == 10 * 3600)
        #expect(today.napCount == 0)   // started the day before
        #expect(today.hours[9].sleepSlices[0].to == 1 && today.hours[9].sleepSlices[0].endsHere)
        #expect(today.hours[10].sleepSlices.isEmpty)
    }

    // MARK: Empty day, boundaries, ordering

    @Test func emptyDay() {
        let past = recap(Self.ny(3, 9, 12), [], now: Self.ny(3, 10, 12))
        #expect(past.isEmpty)
        #expect(past.hours.count == 24)
        #expect(past.napCount == 0)
        #expect(past.summary == DaySummary())
        #expect(past.rows.count == 1)

        // Today: one collapsed run up to the current hour, which stays a row of its own; later hours are not listed.
        let today = recap(Self.ny(3, 10, 0), [], now: Self.ny(3, 10, 9, 30))
        #expect(today.isEmpty)
        #expect(today.visibleHours.count == 10)
        #expect(today.isFuture(today.hours[10]) && !today.isFuture(today.hours[9]))
        #expect(today.rows.count == 2)
        if case .quiet(let run) = today.rows[0] {
            #expect(run.hours.count == 9 && !run.isAsleep && run.first.hourOfDay == 0 && run.last.hourOfDay == 8)
        } else {
            Issue.record("expected a quiet row first")
        }
        if case .hour(let hour) = today.rows[1] {
            #expect(hour.index == 9)
        } else {
            Issue.record("expected the current hour")
        }
    }

    @Test func eventsOnHourBoundaries() {
        let at900 = diaper(Self.ny(3, 10, 9, 0, 0))
        let at859 = diaper(Self.ny(3, 10, 8, 59, 59))
        let at1000 = diaper(Self.ny(3, 10, 10, 0, 0))
        let midnight = diaper(Self.ny(3, 10, 0, 0, 0))
        let nextMidnight = diaper(Self.ny(3, 11, 0, 0, 0))
        let day = recap(Self.ny(3, 10, 15), [at900, at859, at1000, midnight, nextMidnight], now: Self.ny(3, 11, 8))
        #expect(day.hours[9].events == [at900])
        #expect(day.hours[8].events == [at859])
        #expect(day.hours[10].events == [at1000])
        #expect(day.hours[0].events == [midnight])
        #expect(day.eventCount == 4)   // the one at the next midnight belongs to the next day
        #expect(day.summary.diaperCount == 4)
    }

    @Test func severalEventsInOneHourAreSorted() {
        let late = diaper(Self.ny(3, 10, 9, 50))
        let early = bottle(Self.ny(3, 10, 9, 5))
        let middle = diaper(Self.ny(3, 10, 9, 20), .dirty)
        let sameTimeBottle = bottle(Self.ny(3, 10, 9, 20))
        let day = recap(Self.ny(3, 10, 0), [late, sameTimeBottle, early, middle], now: Self.ny(3, 10, 22))
        let nine = day.hours[9]
        #expect(nine.events.count == 4)
        #expect(nine.events.first == early)
        #expect(nine.events.last == late)
        // Two at 9:20: the order is fixed by kind (bottle before diaper), whatever order they came in.
        #expect(nine.events[1] == sameTimeBottle && nine.events[2] == middle)
        let reversed = recap(Self.ny(3, 10, 0), [middle, early, sameTimeBottle, late], now: Self.ny(3, 10, 22))
        #expect(reversed.hours[9].events == nine.events)
        #expect(nine.entries.count == 4)
        #expect(day.summary.feedCount == 2)
    }

    @Test func collapsingEmptyEmptyHoursAndKeepTheSleepBar() {
        let night = sleep(Self.ny(3, 9, 22), Self.ny(3, 10, 6, 10))
        let morning = diaper(Self.ny(3, 10, 7, 15))
        let noon = bottle(Self.ny(3, 10, 12, 0))
        let day = recap(Self.ny(3, 10, 0), [night, morning, noon], now: Self.ny(3, 11, 7))
        // 0-5 asleep (one run), 6 wake-up, 7 diaper, 8-11 awake and empty, 12 bottle, 13-23 empty.
        let shape = day.rows.map { row -> String in
            switch row {
            case .hour(let hour): return "h\(hour.hourOfDay)"
            case .quiet(let run): return "q\(run.first.hourOfDay)-\(run.last.hourOfDay)" + (run.isAsleep ? "z" : "")
            }
        }
        #expect(shape == ["q0-5z", "h6", "h7", "q8-11", "h12", "q13-23"])
        if case .quiet(let run) = day.rows[0] {
            #expect(run.asleepDuration == 6 * 3600)
        }
        #expect(Set(day.rows.map(\.id)).count == day.rows.count)
    }

    // MARK: Naps

    @Test func napCount() {
        let earlyMorning = sleep(Self.ny(3, 10, 4, 0), Self.ny(3, 10, 6, 30))   // the night's
        let nap1 = sleep(Self.ny(3, 10, 9, 30), Self.ny(3, 10, 10, 30))
        let nap2 = sleep(Self.ny(3, 10, 13, 0), Self.ny(3, 10, 14, 30))
        let catnap = sleep(Self.ny(3, 10, 18, 0), Self.ny(3, 10, 18, 40))        // a short early-evening nap
        let bedtime = sleep(Self.ny(3, 10, 20, 0), Self.ny(3, 11, 6, 0))
        let yesterdayNight = sleep(Self.ny(3, 9, 20, 0), Self.ny(3, 10, 3, 0))
        let day = recap(Self.ny(3, 10, 0), [earlyMorning, nap1, nap2, catnap, bedtime, yesterdayNight], now: Self.ny(3, 11, 8))
        #expect(day.napCount == 3)
        // Running bedtime just started is not a nap; a running afternoon sleep is.
        let startedBedtime = sleep(Self.ny(3, 12, 19, 30), nil)
        #expect(recap(Self.ny(3, 12, 0), [startedBedtime], now: Self.ny(3, 12, 19, 40)).napCount == 0)
        let running = sleep(Self.ny(3, 12, 15, 0), nil)
        #expect(recap(Self.ny(3, 12, 0), [running], now: Self.ny(3, 12, 15, 20)).napCount == 1)
    }

    // MARK: Daylight saving time

    @Test func springForwardDayHasTwentyThreeHours() {
        // 2026-03-08: 2:00 AM EST jumps to 3:00 AM EDT.
        let beforeJump = diaper(Self.ny(3, 8, 1, 59, 59))
        let afterJump = diaper(Self.ny(3, 8, 3, 0, 0))
        let night = sleep(Self.ny(3, 8, 1, 30), Self.ny(3, 8, 5, 30))
        let day = recap(Self.ny(3, 8, 12), [beforeJump, afterJump, night], now: Self.ny(3, 9, 8))

        #expect(day.hours.count == 23)
        #expect(day.hours.map(\.hourOfDay) == [0, 1] + Array(3...23))
        #expect(day.hours.allSatisfy { !$0.isRepeated })
        #expect(day.hours[1].events.contains(beforeJump))
        #expect(day.hours[2].hourOfDay == 3 && day.hours[2].events == [afterJump])
        #expect(day.dayEnd.timeIntervalSince(day.dayStart) == 23 * 3600)
        // 1:30 EST to 5:30 EDT is three real hours.
        #expect(day.summary.sleep == 3 * 3600)
        #expect(day.sleepSpans[0].duration == 3 * 3600)
        #expect(day.hours[2].sleepSlices.count == 1 && day.hours[2].isFullyAsleep)
        // The hour after the jump follows straight on from the 1 AM hour.
        #expect(day.hours[1].end == day.hours[2].start)
    }

    @Test func fallBackDayHasTwentyFiveHoursAndTheRepeatedHourStaysDistinct() {
        // 2026-11-01: 2:00 AM EDT falls back to 1:00 AM EST, so 1:00-2:00 happens twice.
        let firstPass = diaper(Date(timeIntervalSince1970: Self.ny(11, 1, 0).timeIntervalSince1970 + 5400))    // 1:30 EDT
        let secondPass = diaper(Date(timeIntervalSince1970: Self.ny(11, 1, 0).timeIntervalSince1970 + 9000))   // 1:30 EST
        let night = sleep(Self.ny(11, 1, 0, 30), Date(timeIntervalSince1970: Self.ny(11, 1, 0).timeIntervalSince1970 + 4 * 3600 + 3600 * 3))
        let day = recap(Self.ny(11, 1, 12), [firstPass, secondPass, night], now: Self.ny(11, 2, 8))

        #expect(day.hours.count == 25)
        #expect(day.hours.map(\.hourOfDay) == [0, 1, 1] + Array(2...23))
        #expect(day.hours.map(\.isRepeated) == [false, false, true] + Array(repeating: false, count: 22))
        #expect(day.hours[1].events == [firstPass])
        #expect(day.hours[2].events == [secondPass])
        #expect(day.hours[1].id != day.hours[2].id)
        #expect(day.dayEnd.timeIntervalSince(day.dayStart) == 25 * 3600)
        #expect(day.summary.diaperCount == 2)
        // 12:30 AM EDT to 7 real hours after midnight is 6:30 AM EST.
        #expect(day.sleepSpans[0].duration == 6.5 * 3600)
        #expect(day.hours[1].isFullyAsleep && day.hours[2].isFullyAsleep)
        #expect(day.hours[0].sleepSlices[0].from == 0.5)
    }

    // MARK: Plain text

    @Test func plainTextHasSummaryAndOneLinePerEntry() {
        let describer = EventDescriber(volumeUnit: .milliliters, unitSystem: .metric, locale: TestSupport.enUS)
        let night = sleep(Self.ny(3, 9, 22), Self.ny(3, 10, 6, 10))
        let feed = bottle(Self.ny(3, 10, 7, 5), ml: 120)
        feed.bottleContent = .formula
        let wet = diaper(Self.ny(3, 10, 7, 40), .mixed)
        let nap = sleep(Self.ny(3, 10, 9, 0), Self.ny(3, 10, 10, 15))
        let day = recap(Self.ny(3, 10, 0), [wet, night, nap, feed], now: Self.ny(3, 10, 21))
        let text = day.plainText(babyName: "Ada", describer: describer, calendar: calendar, locale: TestSupport.enUS)
        let lines = text.components(separatedBy: "\n")

        #expect(lines[0] == "Ada: Tuesday, March 10")
        #expect(lines.contains("Sleep: 7h 25m (1 nap)"))
        #expect(lines.contains("Feeds: 1 (bottle 120 ml)"))
        #expect(lines.contains("Diapers: 1 (1 wet, 1 dirty)"))
        #expect(!lines.contains { $0.hasPrefix("Pumped") || $0.hasPrefix("Solids") || $0.hasPrefix("Medicine") })
        let timeline = lines.drop { !$0.contains("Woke up") }
        #expect(Array(timeline) == [
            "6:10 AM  Woke up (slept 8h 10m)",
            "7:05 AM  Bottle: 120 ml formula",
            "7:40 AM  Diaper: Wet + dirty",
            "9:00 AM  Sleep: 1h 15m",
            "10:15 AM  Woke up (slept 1h 15m)",
        ])
        #expect(!text.contains("\u{202F}"))
    }

    @Test func plainTextForAnEmptyDayAndAStillSleepingBaby() {
        let describer = EventDescriber(volumeUnit: .ounces, unitSystem: .imperial, locale: TestSupport.enUS)
        let empty = recap(Self.ny(3, 10, 0), [], now: Self.ny(3, 11, 8))
        let text = empty.plainText(babyName: "Ada", describer: describer, calendar: calendar, locale: TestSupport.enUS)
        #expect(text.hasSuffix("Nothing logged."))
        #expect(text.contains("Sleep: 0s") || text.contains("Sleep: 0m"))

        let asleep = sleep(Self.ny(3, 9, 21, 30), nil)
        let today = recap(Self.ny(3, 10, 0), [asleep], now: Self.ny(3, 10, 3))
        let todayText = today.plainText(babyName: "Ada", describer: describer, calendar: calendar, locale: TestSupport.enUS)
        #expect(todayText.contains("Still asleep since 9:30 PM"))
    }

    // MARK: Fetching

    @Test func requestDayFindsEventsTouchingTheDay() throws {
        let day = DateInterval(start: Self.ny(3, 10, 0), end: Self.ny(3, 11, 0))
        let inside = diaper(Self.ny(3, 10, 12))
        let overnightIn = sleep(Self.ny(3, 9, 22), Self.ny(3, 10, 6))
        let overnightOut = sleep(Self.ny(3, 10, 22), Self.ny(3, 11, 6))
        let runningOld = sleep(Self.ny(3, 8, 22), nil)
        let tooEarly = sleep(Self.ny(3, 9, 12), Self.ny(3, 9, 13))
        let tooLate = diaper(Self.ny(3, 11, 0))
        let startsExactlyAtStart = diaper(Self.ny(3, 10, 0))
        let otherBaby = Baby.create(name: "Other", birthDate: .now, in: context)
        _ = LogEvent.create(kind: .diaper, for: otherBaby, start: Self.ny(3, 10, 9), in: context)
        try context.save()

        let found = try context.fetch(LogEvent.requestDay(baby: baby, interval: day))
        let ids = Set(found.map(\.objectID))
        #expect(ids == Set([inside, overnightIn, overnightOut, runningOld, startsExactlyAtStart].map(\.objectID)))
        #expect(!ids.contains(tooEarly.objectID) && !ids.contains(tooLate.objectID))
        #expect(found.map { $0.startDate ?? .distantPast } == found.map { $0.startDate ?? .distantPast }.sorted())
    }
}
