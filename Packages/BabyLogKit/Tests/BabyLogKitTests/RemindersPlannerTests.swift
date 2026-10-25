import Testing
import Foundation
@testable import BabyLogKit

struct RemindersPlannerTests {
    private let babyID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let utc = TestSupport.utcCalendar

    private func t(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestSupport.utc(2026, 6, day, hour, minute)
    }

    private func feed(_ start: Date, end: Date? = nil, kind: EventKind = .breastfeed, side: BreastSide? = .right) -> LastFeed {
        LastFeed(start: start, end: end, kind: kind, lastSide: side)
    }

    private func baby(
        name: String = "Juniper",
        every: FeedIntervalReminder = FeedIntervalReminder(isEnabled: true),
        daily: [DailyReminder] = [],
        lastFeed: LastFeed?
    ) -> ReminderBaby {
        ReminderBaby(id: babyID, name: name, settings: BabyReminderSettings(feedEvery: every, daily: daily), lastFeed: lastFeed)
    }

    private func plan(_ baby: ReminderBaby, now: Date, calendar: Calendar? = nil) -> [ReminderRequest] {
        ReminderPlanner.plan(babies: [baby], now: now, calendar: calendar ?? utc)
    }

    // MARK: Feed every N hours

    @Test func intervalFromStartOfLastFeed() throws {
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, anchor: .start),
                     lastFeed: feed(t(10, 8, 0), end: t(10, 8, 25)))
        let request = try #require(plan(b, now: t(10, 8, 30)).first)
        #expect(request.fireDate == t(10, 11, 0))
        #expect(request.identifier == ReminderIdentifier.feedInterval(babyID: babyID))
        #expect(request.categoryIdentifier == ReminderCategory.feed)
        #expect(request.urgency == .timeSensitive)
        #expect(request.babyID == babyID)
    }

    @Test func intervalFromEndOfLastFeed() throws {
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, anchor: .end),
                     lastFeed: feed(t(10, 8, 0), end: t(10, 8, 25)))
        let request = try #require(plan(b, now: t(10, 8, 30)).first)
        #expect(request.fireDate == t(10, 11, 25))
    }

    @Test func runningNursingMeasuresFromStartButNotFromEnd() throws {
        let running = feed(t(10, 8, 0), end: nil)
        let fromStart = baby(every: FeedIntervalReminder(isEnabled: true, anchor: .start), lastFeed: running)
        #expect(plan(fromStart, now: t(10, 8, 10)).first?.fireDate == t(10, 11, 0))
        let fromEnd = baby(every: FeedIntervalReminder(isEnabled: true, anchor: .end), lastFeed: running)
        #expect(plan(fromEnd, now: t(10, 8, 10)).isEmpty, "no end to measure from until the feed finishes")
    }

    @Test func bottleCountsAsInstantForEndAnchor() throws {
        let bottle = feed(t(10, 8, 0), end: t(10, 8, 0), kind: .bottle, side: nil)
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 120, anchor: .end), lastFeed: bottle)
        #expect(plan(b, now: t(10, 8, 5)).first?.fireDate == t(10, 10, 0))
    }

    @Test func pastDueSchedulesNothing() {
        let b = baby(lastFeed: feed(t(10, 8, 0), end: t(10, 8, 20)))
        #expect(plan(b, now: t(10, 11, 0)).isEmpty, "due exactly now is already past")
        #expect(plan(b, now: t(10, 14, 0)).isEmpty)
        #expect(!plan(b, now: t(10, 10, 59)).isEmpty)
    }

    @Test func disabledOrNoFeedSchedulesNothing() {
        let off = baby(every: FeedIntervalReminder(isEnabled: false), lastFeed: feed(t(10, 8, 0)))
        #expect(plan(off, now: t(10, 8, 5)).isEmpty)
        #expect(plan(baby(lastFeed: nil), now: t(10, 8, 5)).isEmpty)
    }

    @Test func intervalIsClampedToSaneRange() {
        let short = FeedIntervalReminder(isEnabled: true, intervalMinutes: 0)
        #expect(short.interval == 60)
        let long = FeedIntervalReminder(isEnabled: true, intervalMinutes: 99_999)
        #expect(long.interval == 24 * 3600)
        let oneMinute = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 1), lastFeed: feed(t(10, 8, 0)))
        #expect(plan(oneMinute, now: t(10, 8, 0)).first?.fireDate == t(10, 8, 1))
    }

    @Test func allowedIntervalsAreOneToSixHoursInQuarterHours() {
        let allowed = FeedIntervalReminder.allowedMinutes
        #expect(allowed.first == 60)
        #expect(allowed.last == 360)
        #expect(allowed.count == 21)
        #expect(allowed.contains(FeedIntervalReminder.defaultMinutes))
        #expect(allowed.allSatisfy { $0 % 15 == 0 })
    }

    @Test func bodyNamesElapsedTimeAndSides() throws {
        let b = baby(lastFeed: feed(t(10, 8, 0), side: .right))
        let request = try #require(plan(b, now: t(10, 8, 30)).first)
        #expect(request.title == "Time to feed Juniper")
        #expect(request.body == "It's been 3h since Juniper's last feed (Right side). Next: Left")

        let left = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 135), lastFeed: feed(t(10, 8, 0), side: .left))
        #expect(try #require(plan(left, now: t(10, 8, 30)).first).body
                == "It's been 2h 15m since Juniper's last feed (Left side). Next: Right")

        let bottle = baby(lastFeed: feed(t(10, 8, 0), end: t(10, 8, 0), kind: .bottle, side: nil))
        #expect(try #require(plan(bottle, now: t(10, 8, 30)).first).body == "It's been 3h since Juniper's last feed (bottle)")

        let noSide = baby(lastFeed: feed(t(10, 8, 0), side: nil))
        #expect(try #require(plan(noSide, now: t(10, 8, 30)).first).body == "It's been 3h since Juniper's last feed")

        let unnamed = baby(name: "  ", lastFeed: feed(t(10, 8, 0), side: nil))
        #expect(try #require(plan(unnamed, now: t(10, 8, 30)).first).title == "Time to feed Baby")
    }

    @Test func bodyUsesRealElapsedTimeWhenQuietHoursHoldItBack() throws {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, quietHours: quiet),
                     lastFeed: feed(t(10, 22, 0), side: nil))
        let request = try #require(plan(b, now: t(10, 22, 5)).first)
        #expect(request.fireDate == t(11, 7, 0))
        #expect(request.body == "It's been 9h since Juniper's last feed")
    }

    // MARK: Quiet hours

    @Test func quietHoursWrappingMidnightDeferToTheEnd() throws {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        func fire(feedAt: Date, now: Date) -> Date? {
            let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, quietHours: quiet), lastFeed: feed(feedAt))
            return plan(b, now: now).first?.fireDate
        }
        // Due 23:00 and 02:00 are inside 22:00-07:00, due 21:00 and 07:00 are not.
        #expect(fire(feedAt: t(10, 20, 0), now: t(10, 20, 5)) == t(11, 7, 0))
        #expect(fire(feedAt: t(10, 23, 0), now: t(10, 23, 5)) == t(11, 7, 0))
        #expect(fire(feedAt: t(10, 18, 0), now: t(10, 18, 5)) == t(10, 21, 0))
        #expect(fire(feedAt: t(11, 4, 0), now: t(11, 4, 5)) == t(11, 7, 0), "due exactly when quiet hours end fires then")
        #expect(fire(feedAt: t(11, 3, 59), now: t(11, 4, 5)) == t(11, 7, 0))
        #expect(fire(feedAt: t(11, 4, 1), now: t(11, 4, 5)) == t(11, 7, 1))
    }

    @Test func quietHoursSameDayWindow() {
        let quiet = QuietHours(startMinutes: 13 * 60, endMinutes: 15 * 60)
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 60, quietHours: quiet), lastFeed: feed(t(10, 12, 30)))
        #expect(plan(b, now: t(10, 12, 31)).first?.fireDate == t(10, 15, 0))
    }

    @Test func emptyQuietWindowNeverHolds() {
        let quiet = QuietHours(startMinutes: 300, endMinutes: 300)
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 60, quietHours: quiet), lastFeed: feed(t(10, 4, 30)))
        #expect(plan(b, now: t(10, 4, 31)).first?.fireDate == t(10, 5, 30))
    }

    @Test func reminderHeldByQuietHoursSurvivesLaterRefreshes() {
        // Fed 21:00, due 00:00 (quiet until 07:00). At 01:00 the original time is past but the reminder is still
        // waiting for 07:00, so it must stay planned (a refresh must not cancel it).
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, quietHours: quiet), lastFeed: feed(t(10, 21, 0)))
        #expect(plan(b, now: t(11, 1, 0)).first?.fireDate == t(11, 7, 0))
        #expect(plan(b, now: t(11, 7, 0)).isEmpty, "once 07:00 has passed it's past due")
        #expect(plan(b, now: t(11, 8, 0)).isEmpty)
    }

    @Test func quietHoursContainsAndFirstAllowedMoment() {
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(quiet.contains(t(10, 22, 0), calendar: utc))
        #expect(quiet.contains(t(11, 6, 59), calendar: utc))
        #expect(!quiet.contains(t(11, 7, 0), calendar: utc))
        #expect(!quiet.contains(t(10, 21, 59), calendar: utc))
        #expect(quiet.firstAllowedMoment(atOrAfter: t(10, 12, 0), calendar: utc) == t(10, 12, 0))
        #expect(quiet.firstAllowedMoment(atOrAfter: t(10, 23, 0), calendar: utc) == t(11, 7, 0))
        #expect(quiet.firstAllowedMoment(atOrAfter: t(11, 2, 0), calendar: utc) == t(11, 7, 0))
    }

    // MARK: Daylight saving

    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func intervalIsAbsoluteAcrossSpringForward() throws {
        // 2026-03-08 02:00 EST jumps to 03:00 EDT. A feed at 00:30 EST + 3h is 04:30 EDT on the wall clock.
        let ny = newYork
        let fed = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 30))!
        let b = baby(lastFeed: feed(fed))
        let request = try #require(plan(b, now: fed.addingTimeInterval(60), calendar: ny).first)
        let fire = try #require(request.fireDate)
        #expect(fire == fed.addingTimeInterval(3 * 3600))
        let parts = ny.dateComponents([.hour, .minute], from: fire)
        #expect(parts.hour == 4 && parts.minute == 30)
    }

    @Test func intervalIsAbsoluteAcrossFallBack() throws {
        // 2026-11-01 02:00 EDT falls back to 01:00 EST. 00:30 EDT + 3h is 02:30 EST.
        let ny = newYork
        let fed = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))!
        let b = baby(lastFeed: feed(fed))
        let fire = try #require(plan(b, now: fed.addingTimeInterval(60), calendar: ny).first?.fireDate)
        #expect(fire == fed.addingTimeInterval(3 * 3600))
        let parts = ny.dateComponents([.hour, .minute], from: fire)
        #expect(parts.hour == 2 && parts.minute == 30)
    }

    @Test func quietHoursEndLandsOnWallClockAcrossSpringForward() throws {
        // Quiet 22:00-07:00. Fed 23:30 EST on Mar 7, due 02:30 EST-ish (after the jump: 03:30 EDT), in quiet hours,
        // so it waits for 07:00 EDT on Mar 8, which is 11:00 UTC (not 12:00 UTC).
        let ny = newYork
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let fed = ny.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 30))!
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, quietHours: quiet), lastFeed: feed(fed))
        let fire = try #require(plan(b, now: fed.addingTimeInterval(60), calendar: ny).first?.fireDate)
        #expect(fire == TestSupport.utc(2026, 3, 8, 11, 0))
        let parts = ny.dateComponents([.hour, .minute], from: fire)
        #expect(parts.hour == 7 && parts.minute == 0)
    }

    @Test func quietHoursEndLandsOnWallClockAcrossFallBack() throws {
        // Quiet 22:00-07:00, fed 23:30 EDT Oct 31. Fall back happens at 02:00 on Nov 1; 07:00 is EST = 12:00 UTC.
        let ny = newYork
        let quiet = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let fed = ny.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!
        let b = baby(every: FeedIntervalReminder(isEnabled: true, intervalMinutes: 180, quietHours: quiet), lastFeed: feed(fed))
        let fire = try #require(plan(b, now: fed.addingTimeInterval(60), calendar: ny).first?.fireDate)
        #expect(fire == TestSupport.utc(2026, 11, 1, 12, 0))
    }

    @Test func dailyReminderUsesWallClockTrigger() throws {
        // A daily reminder is a repeating calendar trigger: the system keeps it at 02:30 / 09:00 local through DST.
        let reminder = DailyReminder(minutesOfDay: 9 * 60, label: "Vitamin D", kind: .medicine)
        let b = baby(every: FeedIntervalReminder(), daily: [reminder], lastFeed: nil)
        let request = try #require(plan(b, now: TestSupport.utc(2026, 3, 8, 6), calendar: newYork).first)
        #expect(request.trigger == .daily(hour: 9, minute: 0))
    }

    // MARK: Daily reminders

    @Test func dailyRemindersMapKindsToContentAndUrgency() throws {
        let medicine = DailyReminder(minutesOfDay: 9 * 60, label: "Vitamin D drops", kind: .medicine)
        let feedReminder = DailyReminder(minutesOfDay: 7 * 60 + 30, label: "", kind: .feed)
        let custom = DailyReminder(minutesOfDay: 20 * 60 + 5, label: "Bath", kind: .custom)
        let b = baby(every: FeedIntervalReminder(), daily: [medicine, custom, feedReminder], lastFeed: nil)
        let requests = plan(b, now: t(10, 6))
        #expect(requests.map(\.trigger) == [.daily(hour: 7, minute: 30), .daily(hour: 9, minute: 0), .daily(hour: 20, minute: 5)],
                "sorted by time of day")

        let feedRequest = requests[0]
        #expect(feedRequest.title == "Feeding time")
        #expect(feedRequest.body == "Time to feed Juniper.")
        #expect(feedRequest.categoryIdentifier == ReminderCategory.feed)
        #expect(feedRequest.urgency == .timeSensitive)
        #expect(feedRequest.identifier == ReminderIdentifier.daily(babyID: babyID, reminderID: feedReminder.id))

        let medicineRequest = requests[1]
        #expect(medicineRequest.title == "Vitamin D drops")
        #expect(medicineRequest.body == "Medicine for Juniper.")
        #expect(medicineRequest.categoryIdentifier == nil)
        #expect(medicineRequest.urgency == .timeSensitive)

        let customRequest = requests[2]
        #expect(customRequest.title == "Bath")
        #expect(customRequest.urgency == .active)
    }

    @Test func disabledDailyRemindersAreSkippedAndIdentifiersAreUnique() {
        let on = DailyReminder(minutesOfDay: 540, label: "A")
        var off = DailyReminder(minutesOfDay: 540, label: "B")
        off.isEnabled = false
        let b = baby(every: FeedIntervalReminder(), daily: [on, off, DailyReminder(minutesOfDay: 540, label: "C")], lastFeed: nil)
        let requests = plan(b, now: t(10, 6))
        #expect(requests.count == 2)
        #expect(Set(requests.map(\.identifier)).count == 2)
    }

    @Test func dailyReminderTimeAndLabelFallbacks() {
        #expect(DailyReminder(minutesOfDay: 23 * 60 + 59).hour == 23)
        #expect(DailyReminder(minutesOfDay: 23 * 60 + 59).minute == 59)
        #expect(DailyReminder(minutesOfDay: 5000).hour == 23, "out-of-range values are clamped")
        #expect(DailyReminder(minutesOfDay: -5).hour == 0)
        #expect(DailyReminder(label: "  ", kind: .custom).displayLabel == "Reminder")
        #expect(DailyReminder(label: "  ", kind: .medicine).displayLabel == "Medicine time")
    }

    // MARK: Several babies

    @Test func eachBabyGetsItsOwnIdentifiersAndNames() throws {
        let otherID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let ada = ReminderBaby(id: babyID, name: "Ada", settings: BabyReminderSettings(feedEvery: FeedIntervalReminder(isEnabled: true)),
                               lastFeed: feed(t(10, 8, 0)))
        let ben = ReminderBaby(id: otherID, name: "Ben",
                               settings: BabyReminderSettings(feedEvery: FeedIntervalReminder(isEnabled: true, intervalMinutes: 120),
                                                              daily: [DailyReminder(minutesOfDay: 600, label: "Drops")]),
                               lastFeed: feed(t(10, 9, 0)))
        let off = ReminderBaby(id: UUID(), name: "Cy", settings: BabyReminderSettings(), lastFeed: feed(t(10, 9, 0)))
        let requests = ReminderPlanner.plan(babies: [ada, ben, off], now: t(10, 9, 30), calendar: utc)
        #expect(requests.count == 3)
        #expect(Set(requests.map(\.identifier)).count == 3)
        #expect(requests[0].title == "Time to feed Ada")
        #expect(requests[0].fireDate == t(10, 11, 0))
        #expect(requests[1].title == "Time to feed Ben")
        #expect(requests[1].fireDate == t(10, 11, 0))
        #expect(requests[2].title == "Drops")
        #expect(requests[2].babyID == otherID)
    }

    // MARK: Snooze and stale reminders

    @Test func snoozeRewordsAFeedReminderAndUsesTheSnoozeIdentifier() throws {
        let b = baby(lastFeed: feed(t(10, 8, 0), side: .right))
        let original = try #require(plan(b, now: t(10, 8, 30)).first)
        let snoozed = try #require(ReminderPlanner.snooze(
            title: original.title, body: original.body, categoryIdentifier: original.categoryIdentifier,
            urgency: original.urgency, userInfo: original.userInfo, now: t(10, 11, 2)
        ))
        #expect(snoozed.identifier == ReminderIdentifier.snooze(babyID: babyID))
        #expect(snoozed.fireDate == t(10, 11, 17))
        #expect(snoozed.body == "It's been 3h 17m since Juniper's last feed (Right side). Next: Left")
        #expect(snoozed.categoryIdentifier == ReminderCategory.feed)
        #expect(snoozed.urgency == .timeSensitive)
    }

    @Test func snoozeKeepsDailyReminderContent() throws {
        let reminder = DailyReminder(minutesOfDay: 540, label: "Vitamin D", kind: .medicine)
        let b = baby(every: FeedIntervalReminder(), daily: [reminder], lastFeed: nil)
        let original = try #require(plan(b, now: t(10, 6)).first)
        let snoozed = try #require(ReminderPlanner.snooze(
            title: original.title, body: original.body, categoryIdentifier: nil,
            urgency: original.urgency, userInfo: original.userInfo, now: t(10, 9), delay: 600
        ))
        #expect(snoozed.title == "Vitamin D")
        #expect(snoozed.body == original.body)
        #expect(snoozed.fireDate == t(10, 9, 10))
        #expect(ReminderPlanner.snooze(title: "x", body: "y", categoryIdentifier: nil, urgency: .active, userInfo: [:], now: t(10, 9)) == nil)
    }

    @Test func staleDetectionRetiresOutdatedFeedReminders() throws {
        let first = baby(lastFeed: feed(t(10, 8, 0)))
        let request = try #require(plan(first, now: t(10, 8, 30)).first)
        #expect(!ReminderPlanner.isStale(userInfo: request.userInfo, babies: [first]))

        let newerFeed = baby(lastFeed: feed(t(10, 10, 0)))
        #expect(ReminderPlanner.isStale(userInfo: request.userInfo, babies: [newerFeed]), "a newer feed retires it")

        var turnedOff = first
        turnedOff.settings.feedEvery.isEnabled = false
        #expect(ReminderPlanner.isStale(userInfo: request.userInfo, babies: [turnedOff]))
        #expect(ReminderPlanner.isStale(userInfo: request.userInfo, babies: []), "its baby is gone")
        #expect(ReminderPlanner.isStale(userInfo: request.userInfo, babies: [baby(lastFeed: nil)]))
    }

    @Test func dailyRemindersAreNeverStaleWhileTheirBabyExists() throws {
        let reminder = DailyReminder(minutesOfDay: 540, label: "Drops", kind: .medicine)
        let b = baby(every: FeedIntervalReminder(), daily: [reminder], lastFeed: feed(t(10, 8, 0)))
        let request = try #require(plan(b, now: t(10, 6)).first)
        #expect(!ReminderPlanner.isStale(userInfo: request.userInfo, babies: [b]))
        #expect(ReminderPlanner.isStale(userInfo: request.userInfo, babies: []))
        #expect(!ReminderPlanner.isStale(userInfo: ["unrelated": "x"], babies: [b]))
    }
}
