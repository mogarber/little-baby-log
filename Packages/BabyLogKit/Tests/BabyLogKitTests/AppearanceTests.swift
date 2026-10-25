import Testing
import Foundation
@testable import BabyLogKit

struct AppearanceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0, month: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: Schedule

    @Test func defaultScheduleIsSevenToSeven() {
        #expect(NightSchedule.default.startMinutes == 19 * 60)
        #expect(NightSchedule.default.endMinutes == 7 * 60)
        #expect(NightSchedule.default.wrapsMidnight)
    }

    @Test func wrappingWindowIsActiveOvernight() {
        let schedule = NightSchedule.default
        #expect(schedule.isNightActive(at: date(10, 19, 0), calendar: calendar))
        #expect(schedule.isNightActive(at: date(10, 23, 59), calendar: calendar))
        #expect(schedule.isNightActive(at: date(11, 0, 0), calendar: calendar))
        #expect(schedule.isNightActive(at: date(11, 3, 30), calendar: calendar))
        #expect(schedule.isNightActive(at: date(11, 6, 59), calendar: calendar))
    }

    @Test func wrappingWindowIsInactiveByDay() {
        let schedule = NightSchedule.default
        // The end is exclusive, the start inclusive.
        #expect(!schedule.isNightActive(at: date(11, 7, 0), calendar: calendar))
        #expect(!schedule.isNightActive(at: date(11, 12, 0), calendar: calendar))
        #expect(!schedule.isNightActive(at: date(11, 18, 59), calendar: calendar))
    }

    @Test func sameDayWindow() {
        let schedule = NightSchedule(startMinutes: 13 * 60, endMinutes: 15 * 60 + 30)
        #expect(!schedule.wrapsMidnight)
        #expect(!schedule.isNightActive(at: date(10, 12, 59), calendar: calendar))
        #expect(schedule.isNightActive(at: date(10, 13, 0), calendar: calendar))
        #expect(schedule.isNightActive(at: date(10, 15, 29), calendar: calendar))
        #expect(!schedule.isNightActive(at: date(10, 15, 30), calendar: calendar))
        #expect(!schedule.isNightActive(at: date(10, 23, 0), calendar: calendar))
    }

    @Test func emptyWindowIsNeverActive() {
        let schedule = NightSchedule(startMinutes: 600, endMinutes: 600)
        #expect(schedule.isEmpty)
        #expect(!schedule.isNightActive(at: date(10, 10, 0), calendar: calendar))
        #expect(!schedule.isNightActive(at: date(10, 3, 0), calendar: calendar))
        #expect(schedule.nextTransition(after: date(10, 3, 0), calendar: calendar) == nil)
    }

    @Test func minutesAreFoldedIntoADay() {
        let schedule = NightSchedule(startMinutes: -60, endMinutes: 1440 + 30)
        #expect(schedule.startMinutes == 23 * 60)
        #expect(schedule.endMinutes == 30)
    }

    @Test func nextTransitionFromDaytimeIsTheStart() {
        let next = NightSchedule.default.nextTransition(after: date(10, 12, 0), calendar: calendar)
        #expect(next == date(10, 19, 0))
    }

    @Test func nextTransitionFromNightIsTheEnd() {
        let schedule = NightSchedule.default
        #expect(schedule.nextTransition(after: date(10, 22, 0), calendar: calendar) == date(11, 7, 0))
        #expect(schedule.nextTransition(after: date(11, 2, 0), calendar: calendar) == date(11, 7, 0))
    }

    @Test func nextTransitionIsStrictlyAfter() {
        let schedule = NightSchedule.default
        // Exactly on a boundary: the following one, not the same instant.
        #expect(schedule.nextTransition(after: date(10, 19, 0), calendar: calendar) == date(11, 7, 0))
        #expect(schedule.nextTransition(after: date(11, 7, 0), calendar: calendar) == date(11, 19, 0))
        // One second before.
        #expect(schedule.nextTransition(after: date(10, 18, 59, second: 59), calendar: calendar) == date(10, 19, 0))
    }

    @Test func nextTransitionRollsOverMonthEnd() {
        let next = NightSchedule.default.nextTransition(after: date(30, 20, 0, month: 6), calendar: calendar)
        #expect(next == date(1, 7, 0, month: 7))
    }

    @Test func nextTransitionAlwaysFlipsTheState() {
        let schedule = NightSchedule(startMinutes: 21 * 60 + 15, endMinutes: 5 * 60 + 45)
        var moment = date(10, 0, 5)
        for _ in 0..<12 {
            let before = schedule.isNightActive(at: moment, calendar: calendar)
            let next = schedule.nextTransition(after: moment, calendar: calendar)!
            #expect(next > moment)
            #expect(schedule.isNightActive(at: next.addingTimeInterval(-1), calendar: calendar) == before)
            #expect(schedule.isNightActive(at: next, calendar: calendar) == !before)
            moment = next
        }
    }

    @Test func nextTransitionFollowsWallClockAcrossDaylightSaving() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // US clocks spring forward on 2026-03-08. Evening start is still 7 PM local the day after.
        let before = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!
        let next = NightSchedule.default.nextTransition(after: before, calendar: newYork)!
        let parts = newYork.dateComponents([.month, .day, .hour, .minute], from: next)
        #expect(parts.month == 3 && parts.day == 8 && parts.hour == 19 && parts.minute == 0)
        // Overnight into the shortened day: the end is 7 AM local, 11 hours of wall clock after 7 PM minus the lost hour.
        let evening = newYork.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 20))!
        let morning = NightSchedule.default.nextTransition(after: evening, calendar: newYork)!
        let morningParts = newYork.dateComponents([.month, .day, .hour, .minute], from: morning)
        #expect(morningParts.day == 8 && morningParts.hour == 7 && morningParts.minute == 0)
        #expect(morning.timeIntervalSince(evening) == 10 * 3600)
    }

    // MARK: Modes

    @Test func fixedModesIgnoreTheClock() {
        let schedule = NightSchedule.default
        let noon = date(10, 12, 0)
        let midnight = date(11, 0, 0)
        for moment in [noon, midnight] {
            #expect(AppearanceMode.system.resolved(schedule: schedule, at: moment, calendar: calendar) == .system)
            #expect(AppearanceMode.light.resolved(schedule: schedule, at: moment, calendar: calendar) == .light)
            #expect(AppearanceMode.dark.resolved(schedule: schedule, at: moment, calendar: calendar) == .dark)
            #expect(AppearanceMode.night.resolved(schedule: schedule, at: moment, calendar: calendar) == .night)
        }
    }

    @Test func scheduledModeSwitchesBetweenNightAndSystem() {
        let schedule = NightSchedule.default
        #expect(AppearanceMode.nightSchedule.resolved(schedule: schedule, at: date(10, 12, 0), calendar: calendar) == .system)
        #expect(AppearanceMode.nightSchedule.resolved(schedule: schedule, at: date(10, 22, 0), calendar: calendar) == .night)
        #expect(AppearanceMode.nightSchedule.resolved(schedule: schedule, at: date(10, 22, 0), calendar: calendar).isNight)
    }

    @Test func onlyTheScheduledModeHasTransitions() {
        let schedule = NightSchedule.default
        let noon = date(10, 12, 0)
        #expect(AppearanceMode.nightSchedule.nextTransition(schedule: schedule, after: noon, calendar: calendar) == date(10, 19, 0))
        for mode in [AppearanceMode.system, .light, .dark, .night] {
            #expect(mode.nextTransition(schedule: schedule, after: noon, calendar: calendar) == nil)
        }
    }

    @Test func nightIsPossibleOnlyInNightModes() {
        #expect(AppearanceMode.allCases.filter(\.canShowNight) == [.night, .nightSchedule])
    }

    @Test func rawValuesAreStable() {
        // These are stored with @AppStorage; renaming one would reset people's setting.
        #expect(AppearanceMode.allCases.map(\.rawValue) == ["system", "light", "dark", "night", "nightSchedule"])
    }
}
