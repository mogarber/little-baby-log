import CoreData
import Testing
import Foundation
@testable import BabyLogKit

struct RemindersSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "RemindersSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func settingsRoundTripThroughTheStorePerBaby() {
        let store = ReminderSettingsStore(defaults: makeDefaults())
        let a = UUID(), b = UUID()
        #expect(store.settings(for: a) == BabyReminderSettings())
        #expect(!store.hasAnythingEnabled)

        var settings = BabyReminderSettings()
        settings.feedEvery = FeedIntervalReminder(isEnabled: true, intervalMinutes: 150, anchor: .end,
                                                  quietHours: QuietHours(startMinutes: 1320, endMinutes: 420))
        settings.daily = [DailyReminder(minutesOfDay: 540, label: "Vitamin D", kind: .medicine)]
        store.save(settings, for: a)

        #expect(store.settings(for: a) == settings)
        #expect(store.settings(for: b) == BabyReminderSettings(), "other babies are untouched")
        #expect(store.hasAnythingEnabled)

        store.remove(babyID: a)
        #expect(store.settings(for: a) == BabyReminderSettings())
        #expect(!store.hasAnythingEnabled)
    }

    @Test func decodingToleratesMissingAndUnknownFields() throws {
        let json = #"{"feedEvery":{"isEnabled":true},"daily":[{"minutesOfDay":600,"kind":"surprise","extra":1}],"napWindow":{"x":1}}"#
        let decoded = try JSONDecoder().decode(BabyReminderSettings.self, from: Data(json.utf8))
        #expect(decoded.feedEvery.isEnabled)
        #expect(decoded.feedEvery.intervalMinutes == FeedIntervalReminder.defaultMinutes)
        #expect(decoded.feedEvery.anchor == .start)
        #expect(decoded.feedEvery.quietHours == nil)
        #expect(decoded.daily.count == 1)
        #expect(decoded.daily[0].kind == .custom, "an unknown kind from a newer build falls back")
        #expect(decoded.daily[0].isEnabled)
        let empty = try JSONDecoder().decode(BabyReminderSettings.self, from: Data("{}".utf8))
        #expect(empty == BabyReminderSettings())
    }

    @Test func corruptStoredDataReadsAsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: ReminderSettingsStore.defaultsKey)
        #expect(ReminderSettingsStore(defaults: defaults).all().isEmpty)
    }

    @Test func hasAnythingEnabledLooksAtDailyRemindersToo() {
        var settings = BabyReminderSettings()
        #expect(!settings.hasAnythingEnabled)
        settings.daily = [DailyReminder(isEnabled: false)]
        #expect(!settings.hasAnythingEnabled)
        settings.daily[0].isEnabled = true
        #expect(settings.hasAnythingEnabled)
    }

    // MARK: Core Data adapter

    @MainActor
    @Test func inputsPickTheLatestFeedForEachBaby() throws {
        let (_, ctx) = TestSupport.makeContext()
        let t0 = TestSupport.utc(2026, 6, 10, 8)
        let ada = Baby.create(name: "Ada", birthDate: t0, in: ctx)
        let ben = Baby.create(name: "Ben", birthDate: t0, in: ctx)
        ben.createdAt = t0.addingTimeInterval(1)
        ada.createdAt = t0

        // Ada: a finished left-side nursing, then a later bottle, then solids (don't count) and a diaper.
        let nursing = LogEvent.create(kind: .breastfeed, for: ada, start: t0, in: ctx)
        nursing.startSide(.left, at: t0)
        nursing.finishNursing(at: t0.addingTimeInterval(600))
        _ = LogEvent.create(kind: .bottle, for: ada, start: t0.addingTimeInterval(4000), in: ctx)
        _ = LogEvent.create(kind: .solids, for: ada, start: t0.addingTimeInterval(9000), in: ctx)
        _ = LogEvent.create(kind: .diaper, for: ada, start: t0.addingTimeInterval(9500), in: ctx)

        // Ben: nursing still running on the right.
        let running = LogEvent.create(kind: .breastfeed, for: ben, start: t0.addingTimeInterval(100), in: ctx)
        running.startSide(.right, at: t0.addingTimeInterval(100))
        ctx.saveIfNeeded()

        let defaults = makeDefaults()
        let store = ReminderSettingsStore(defaults: defaults)
        store.save(BabyReminderSettings(feedEvery: FeedIntervalReminder(isEnabled: true)), for: try #require(ada.uuid))

        let babies = ReminderInputs.load(in: ctx, settings: store)
        #expect(babies.map(\.name) == ["Ada", "Ben"])
        let adaFeed = try #require(babies[0].lastFeed)
        #expect(adaFeed.kind == .bottle)
        #expect(adaFeed.start == t0.addingTimeInterval(4000))
        #expect(adaFeed.end == adaFeed.start, "a bottle is instant")
        #expect(babies[0].settings.feedEvery.isEnabled)
        let benFeed = try #require(babies[1].lastFeed)
        #expect(benFeed.kind == .breastfeed)
        #expect(benFeed.end == nil)
        #expect(benFeed.lastSide == .right)
        #expect(!babies[1].settings.hasAnythingEnabled)
    }

    @MainActor
    @Test func aNursingPlaceholderWithNothingStartedIsNotAFeed() throws {
        let (_, ctx) = TestSupport.makeContext()
        let t0 = TestSupport.utc(2026, 6, 10, 8)
        let baby = Baby.create(name: "Ada", birthDate: t0, in: ctx)
        let real = LogEvent.create(kind: .bottle, for: baby, start: t0, in: ctx)
        real.amountML = 100
        _ = LogEvent.create(kind: .breastfeed, for: baby, start: t0.addingTimeInterval(3600), in: ctx)
        ctx.saveIfNeeded()
        let feed = try #require(ReminderInputs.load(in: ctx, settings: ReminderSettingsStore(defaults: makeDefaults())).first?.lastFeed)
        #expect(feed.kind == .bottle)
        #expect(feed.start == t0)
    }

    @MainActor
    @Test func inputsForABabyWithNoFeedsHaveNone() {
        let (_, ctx) = TestSupport.makeContext()
        _ = Baby.create(name: "Ada", birthDate: .now, in: ctx)
        ctx.saveIfNeeded()
        let babies = ReminderInputs.load(in: ctx, settings: ReminderSettingsStore(defaults: makeDefaults()))
        #expect(babies.count == 1)
        #expect(babies[0].lastFeed == nil)
    }
}
