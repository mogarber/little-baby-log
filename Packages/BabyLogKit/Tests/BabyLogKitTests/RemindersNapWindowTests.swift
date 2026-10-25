import Testing
import Foundation
@testable import BabyLogKit

/// The nap-window reminder: planned from `SleepPredictor`, so these use the same synthetic histories as the
/// prediction tests (a 7-week-old and a 6-month-old, 15 days of logs, UTC).
struct RemindersNapWindowTests {
    private let s = Scenario()
    private let enUS = TestSupport.enUS
    private let juniperID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let rowanID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func baby(
        _ plan: SleepPlan = .sevenWeeks,
        ageDays: Int = 49,
        at now: Date,
        id: UUID? = nil,
        name: String = "Juniper",
        nap: NapWindowReminder = NapWindowReminder(isEnabled: true),
        sleeps: [SleepSession]? = nil
    ) -> ReminderBaby {
        ReminderBaby(
            id: id ?? juniperID,
            name: name,
            settings: BabyReminderSettings(napWindow: nap),
            lastFeed: nil,
            birthDate: s.birthDate(ageDays: ageDays, now: now),
            sleeps: sleeps ?? s.sleeps(plan, now: now)
        )
    }

    private func plan(_ babies: ReminderBaby..., now: Date) -> [ReminderRequest] {
        ReminderPlanner.plan(babies: babies, now: now, calendar: s.calendar, locale: enUS)
    }

    private func prediction(of baby: ReminderBaby, now: Date) -> SleepPrediction? {
        SleepPredictor.next(birthDate: baby.birthDate!, sleeps: baby.sleeps, now: now, calendar: s.calendar)
    }

    /// A moment on the 7-week-old's morning when she is awake with a nap window still 30+ minutes away.
    private var napNow: Date {
        let probe = baby(at: s.now(7))
        for minute in stride(from: 8 * 60, to: 12 * 60, by: 5) {
            let now = s.now(minute / 60, minute % 60)
            let log = baby(at: now)
            if let predicted = prediction(of: log, now: now), predicted.kind == .nap, predicted.lastWake != nil,
               predicted.window.start.timeIntervalSince(now) >= 30 * 60 { return now }
        }
        Issue.record("no usable moment found for \(probe.name)")
        return s.now(10)
    }

    /// Spaces in formatted times can be narrow no-break spaces; compare with plain ones.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: Scheduling

    @Test func firesTheLeadTimeBeforeTheWindowOpens() throws {
        let now = napNow
        let b = baby(at: now)
        let window = try #require(prediction(of: b, now: now)).window
        let request = try #require(plan(b, now: now).first)
        #expect(request.fireDate == window.start.addingTimeInterval(-10 * 60), "default lead is 10 minutes")
        #expect(request.identifier == ReminderIdentifier.napWindow(babyID: juniperID))
        #expect(request.urgency == .active, "not time sensitive")
        #expect(request.categoryIdentifier == nil, "a tap opens Today; no actions")
        #expect(request.babyID == juniperID)
        #expect(request.userInfo == [ReminderUserInfoKey.babyID: juniperID.uuidString])
    }

    @Test func everyLeadInThePickerMovesTheReminder() throws {
        let now = napNow
        let window = try #require(prediction(of: baby(at: now), now: now)).window
        for lead in NapWindowReminder.allowedLeadMinutes {
            let b = baby(at: now, nap: NapWindowReminder(isEnabled: true, leadMinutes: lead))
            let request = try #require(plan(b, now: now).first)
            #expect(request.fireDate == window.start.addingTimeInterval(-TimeInterval(lead * 60)))
            #expect(request.body.contains("opens in \(lead) min"))
        }
    }

    @Test func bodyNamesTheBabyAndTheWindow() throws {
        let now = napNow
        let b = baby(at: now)
        let window = try #require(prediction(of: b, now: now)).window
        let request = try #require(plan(b, now: now).first)
        let range = plain(PredictionText.clockRange(of: window, calendar: s.calendar, locale: enUS))
        #expect(plain(request.body) == "Juniper's nap window opens in 10 min (\(range))")
        #expect(range.contains("–") && (range.contains("AM") || range.contains("PM")), "got \(range)")
        #expect(request.title == "Nap window coming up")
    }

    @Test func clockTimesFollowTheCalendarsTimeZone() throws {
        var newYork = Calendar.newYork
        newYork.locale = enUS
        let window = DateInterval(start: TestSupport.utc(2026, 3, 15, 18, 10), end: TestSupport.utc(2026, 3, 15, 18, 40))
        // 18:10 UTC is 2:10 PM in New York (daylight time from March 8).
        let text = plain(PredictionText.clockRange(of: window, calendar: newYork, locale: enUS)); #expect(text == "2:10 – 2:40 PM", "got \(text)")
    }

    @Test func nothingWhenTurnedOffOrWithoutABirthDate() {
        let now = napNow
        #expect(plan(baby(at: now, nap: NapWindowReminder(isEnabled: false)), now: now).isEmpty)
        var noBirthDate = baby(at: now)
        noBirthDate.birthDate = nil
        #expect(plan(noBirthDate, now: now).isEmpty)
    }

    // MARK: Past due

    @Test func pastDueSchedulesNothing() throws {
        let start = napNow
        let b = baby(at: start)
        let window = try #require(prediction(of: b, now: start)).window
        let fire = window.start.addingTimeInterval(-10 * 60)

        let justBefore = fire.addingTimeInterval(-60)
        let later = baby(at: justBefore)
        #expect(plan(later, now: justBefore).first?.fireDate == fire, "a minute to go still schedules")

        for now in [fire, fire.addingTimeInterval(60), window.start, window.start.addingTimeInterval(5 * 60)] {
            let b = baby(at: now)
            #expect(plan(b, now: now).isEmpty, "time to fire is gone at \(now)")
        }
    }

    @Test func aWindowCloserThanTheLeadSchedulesNothing() throws {
        let now = napNow
        let window = try #require(prediction(of: baby(at: now), now: now)).window
        let tooLate = window.start.addingTimeInterval(-4 * 60)
        #expect(plan(baby(at: tooLate), now: tooLate).isEmpty, "4 minutes away, but the lead is 10")
    }

    // MARK: Filters

    @Test func bedtimeIsSkippedUnlessAskedFor() throws {
        // A 6-month-old who has had her three naps: the next sleep is bedtime.
        let now = s.now(17, 10)
        let off = baby(.sixMonths, ageDays: 190, at: now)
        let predicted = try #require(prediction(of: off, now: now))
        #expect(predicted.kind == .bedtime)
        #expect(plan(off, now: now).isEmpty, "bedtime reminders are off by default")

        let on = baby(.sixMonths, ageDays: 190, at: now, nap: NapWindowReminder(isEnabled: true, includeBedtime: true))
        let request = try #require(plan(on, now: now).first)
        #expect(request.fireDate == predicted.window.start.addingTimeInterval(-10 * 60))
        #expect(request.identifier == ReminderIdentifier.napWindow(babyID: juniperID), "the same identifier, so it replaces")
        #expect(request.title == "Bedtime coming up")
        #expect(plain(request.body).hasPrefix("Juniper's bedtime window opens in 10 min ("))
        #expect(request.urgency == .active)
    }

    @Test func includeBedtimeStillRemindsForNaps() throws {
        let now = napNow
        let b = baby(at: now, nap: NapWindowReminder(isEnabled: true, includeBedtime: true))
        let request = try #require(plan(b, now: now).first)
        #expect(request.body.contains("nap window"))
    }

    @Test func aWindowCountedFromNowIsNeverRemindedAbout() throws {
        // Nothing logged: the predictor answers, but from "now", typical for age.
        let now = napNow
        let empty = baby(at: now, sleeps: [])
        let predicted = try #require(prediction(of: empty, now: now))
        #expect(predicted.lastWake == nil)
        #expect(predicted.kind == .nap)
        #expect(plan(empty, now: now).isEmpty)
    }

    @Test func aStaleWindowIsCountedFromNowSoItGetsNoReminder() throws {
        // The log ends with a morning wake-up; three hours past its window, that window closed long ago, so the log is probably
        // missing a sleep and the predictor starts counting from now.
        let wakeLog = baby(at: napNow)
        let fresh = try #require(prediction(of: wakeLog, now: napNow))
        let later = fresh.window.end.addingTimeInterval(3 * 3600)
        let stale = baby(at: later, sleeps: wakeLog.sleeps)
        let predicted = try #require(prediction(of: stale, now: later))
        #expect(fresh.lastWake != nil && predicted.lastWake == nil)
        #expect(plan(stale, now: later).isEmpty)
    }

    @Test func anOverdueWindowSchedulesNothing() throws {
        let start = napNow
        let b = baby(at: start)
        let window = try #require(prediction(of: b, now: start)).window
        let overdue = window.end.addingTimeInterval(20 * 60)
        let predicted = try #require(prediction(of: b, now: overdue))
        #expect(predicted.lastWake != nil, "still anchored, shown as overdue")
        #expect(plan(b, now: overdue).isEmpty)
    }

    // MARK: Asleep

    @Test func startingASleepRemovesTheReminder() throws {
        let now = napNow
        let awake = baby(at: now)
        #expect(plan(awake, now: now).count == 1)

        // The baby falls asleep: the plan has no nap reminder, so the scheduler removes the pending request.
        let asleepNow = now.addingTimeInterval(5 * 60)
        let asleep = baby(at: now, sleeps: awake.sleeps + [SleepSession(start: asleepNow, end: nil)])
        #expect(prediction(of: asleep, now: asleepNow) == nil)
        #expect(plan(asleep, now: asleepNow).isEmpty)
    }

    @Test func aNightWakingGetsNoReminder() throws {
        // Up at 2 AM between night sleeps: no prediction, so no reminder.
        let now = s.now(2, 30)
        let b = baby(at: now)
        #expect(prediction(of: b, now: now) == nil)
        #expect(plan(b, now: now).isEmpty)
    }

    // MARK: Two babies

    @Test func eachBabyGetsItsOwnReminderUnderItsOwnIdentifier() throws {
        let now = napNow
        let juniper = baby(at: now)
        let rowan = baby(.fourteenMonths, ageDays: 425, at: now, id: rowanID, name: "Rowan",
                         nap: NapWindowReminder(isEnabled: true, leadMinutes: 15))
        var off = baby(at: now, id: UUID(), name: "Sky")
        off.settings.napWindow.isEnabled = false

        let requests = plan(juniper, rowan, off, now: now)
        #expect(requests.count == 2)
        let j = try #require(requests.first { $0.babyID == juniperID })
        let r = try #require(requests.first { $0.babyID == rowanID })
        #expect(j.identifier != r.identifier)
        #expect(r.identifier == ReminderIdentifier.napWindow(babyID: rowanID))
        #expect(j.body.hasPrefix("Juniper's nap window opens in 10 min"))
        #expect(r.body.hasPrefix("Rowan's nap window opens in 15 min"))
        let rowanWindow = try #require(prediction(of: rowan, now: now)).window
        #expect(r.fireDate == rowanWindow.start.addingTimeInterval(-15 * 60))
    }

    @Test func oneBabyAsleepDoesNotAffectTheOther() throws {
        let now = napNow
        let juniper = baby(at: now)
        let rowan = baby(at: now, id: rowanID, name: "Rowan",
                         sleeps: juniper.sleeps + [SleepSession(start: now.addingTimeInterval(-60), end: nil)])
        let requests = plan(juniper, rowan, now: now)
        #expect(requests.map(\.babyID) == [juniperID])
    }

    @Test func napReminderSitsBetweenFeedAndDailyInThePlan() throws {
        let now = napNow
        var b = baby(at: now)
        b.settings.feedEvery = FeedIntervalReminder(isEnabled: true)
        b.settings.daily = [DailyReminder(minutesOfDay: 540, label: "Drops", kind: .medicine)]
        b.lastFeed = LastFeed(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-3000), kind: .bottle)
        let ids = plan(b, now: now).map(\.identifier)
        #expect(ids.count == 3)
        #expect(ids[0].hasPrefix("lbl.reminder.feed."))
        #expect(ids[1] == ReminderIdentifier.napWindow(babyID: juniperID))
        #expect(ids[2].hasPrefix("lbl.reminder.daily."))
        #expect(ids.allSatisfy { $0.hasPrefix(ReminderIdentifier.prefix) }, "so the scheduler cleans them up")
    }

    // MARK: Settings

    @Test func napDefaults() {
        let nap = NapWindowReminder()
        #expect(!nap.isEnabled && !nap.includeBedtime)
        #expect(nap.leadMinutes == 10)
        #expect(NapWindowReminder.allowedLeadMinutes == [5, 10, 15, 20])
        #expect(BabyReminderSettings().napWindow == nap)
    }

    @Test func olderSettingsBlobsWithoutNapFieldsStillDecode() throws {
        let old = #"{"feedEvery":{"isEnabled":true,"intervalMinutes":150},"daily":[{"minutesOfDay":540,"label":"Drops","kind":"medicine"}]}"#
        let decoded = try JSONDecoder().decode(BabyReminderSettings.self, from: Data(old.utf8))
        #expect(decoded.napWindow == NapWindowReminder(), "off, 10 minutes, no bedtime")
        #expect(decoded.feedEvery.isEnabled && decoded.feedEvery.intervalMinutes == 150)
        #expect(decoded.daily.count == 1)
    }

    @Test func partialAndOddNapSettingsDecodeForgivingly() throws {
        let partial = try JSONDecoder().decode(BabyReminderSettings.self, from: Data(#"{"napWindow":{"isEnabled":true}}"#.utf8))
        #expect(partial.napWindow == NapWindowReminder(isEnabled: true, leadMinutes: 10, includeBedtime: false))
        let someFields = try JSONDecoder().decode(BabyReminderSettings.self, from: Data(#"{"napWindow":{"leadMinutes":20,"includeBedtime":true,"future":1}}"#.utf8))
        #expect(someFields.napWindow == NapWindowReminder(isEnabled: false, leadMinutes: 20, includeBedtime: true))
        let wrongShape = try JSONDecoder().decode(BabyReminderSettings.self, from: Data(#"{"feedEvery":{"isEnabled":true},"napWindow":"nope"}"#.utf8))
        #expect(wrongShape.napWindow == NapWindowReminder(), "a field of the wrong shape doesn't lose the rest")
        #expect(wrongShape.feedEvery.isEnabled)
    }

    @Test func leadTimeIsKeptToASaneRange() {
        #expect(NapWindowReminder(leadMinutes: 0).lead == 60)
        #expect(NapWindowReminder(leadMinutes: -5).lead == 60)
        #expect(NapWindowReminder(leadMinutes: 15).lead == 15 * 60)
        #expect(NapWindowReminder(leadMinutes: 9999).lead == TimeInterval(NapWindowReminder.maxLeadMinutes * 60))
    }

    @Test func napSettingsRoundTripAndCountAsSomethingEnabled() {
        let name = "RemindersNapWindowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ReminderSettingsStore(defaults: defaults)
        #expect(!store.hasAnythingEnabled)

        var settings = BabyReminderSettings()
        settings.napWindow = NapWindowReminder(isEnabled: true, leadMinutes: 20, includeBedtime: true)
        store.save(settings, for: juniperID)
        #expect(store.settings(for: juniperID) == settings)
        #expect(store.settings(for: rowanID).napWindow == NapWindowReminder())
        #expect(store.hasAnythingEnabled)
        #expect(settings.hasAnythingEnabled)
    }
}
