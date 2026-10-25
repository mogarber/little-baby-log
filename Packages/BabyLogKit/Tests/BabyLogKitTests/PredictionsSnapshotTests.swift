import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct PredictionsSnapshotTests {
    let calendar = Calendar.current
    /// 2026-03-10 at 10:15 local.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 10, minute: 15))! }
    var scenario: Scenario {
        Scenario(
            calendar: calendar,
            firstDay: calendar.date(from: DateComponents(year: 2026, month: 2, day: 24))!,
            today: calendar.startOfDay(for: now),
            days: 15
        )
    }

    private func baby(ageDays: Int, in ctx: NSManagedObjectContext) -> Baby {
        Baby.create(name: "Ada", birthDate: calendar.date(byAdding: .day, value: -ageDays, to: calendar.startOfDay(for: now))!, in: ctx)
    }

    private func insert(_ sleeps: [SleepSession], for baby: Baby, in ctx: NSManagedObjectContext) {
        for sleep in sleeps {
            let event = LogEvent.create(kind: .sleep, for: baby, start: sleep.start, in: ctx)
            event.endDate = sleep.end
        }
    }

    private func make(_ babies: [Baby], _ ctx: NSManagedObjectContext) -> WidgetSnapshot {
        WidgetSnapshot.make(babies: babies, context: ctx, selectedBabyID: nil, volumeUnit: .milliliters, unitSystem: .metric, now: now)
    }

    // MARK: Loading

    @Test func loadReadsRecentSleepsAndFeedsOfThatBabyOnly() throws {
        let (_, ctx) = TestSupport.makeContext()
        let ada = baby(ageDays: 190, in: ctx)
        let other = baby(ageDays: 190, in: ctx)
        let hour = 3600.0

        func event(_ kind: EventKind, hoursAgo: Double, length: Double? = nil, _ baby: Baby) {
            let e = LogEvent.create(kind: kind, for: baby, start: now.addingTimeInterval(-hoursAgo * hour), in: ctx)
            if let length { e.endDate = e.startDate!.addingTimeInterval(length * hour) }
        }
        event(.sleep, hoursAgo: 24 * 20, length: 1, ada)       // too old
        event(.sleep, hoursAgo: 24 * 5, length: 1, ada)
        event(.sleep, hoursAgo: 3, length: 1, ada)
        event(.sleep, hoursAgo: 1, ada)                        // running
        event(.sleep, hoursAgo: 2, length: 1, other)           // another baby
        event(.breastfeed, hoursAgo: 24 * 6, length: 0.2, ada) // too old for feeds
        event(.breastfeed, hoursAgo: 30, length: 0.2, ada)
        event(.bottle, hoursAgo: 4, ada)
        event(.solids, hoursAgo: 5, ada)
        event(.pump, hoursAgo: 6, length: 0.3, ada)
        event(.diaper, hoursAgo: 2, ada)
        ctx.saveIfNeeded()

        let inputs = PredictionInputs.load(for: ada, in: ctx, now: now)
        #expect(inputs.sleeps.count == 3)
        #expect(inputs.sleeps.filter { $0.end == nil }.count == 1)
        #expect(inputs.sleeps.map(\.start) == inputs.sleeps.map(\.start).sorted())
        #expect(inputs.feeds.map(\.kind) == [.breastfeed, .bottle])
    }

    // MARK: Snapshot

    @Test func snapshotCarriesTheNextNapAndFeed() throws {
        let (_, ctx) = TestSupport.makeContext()
        let ada = baby(ageDays: 190, in: ctx)
        insert(scenario.sleeps(.sixMonths, now: now), for: ada, in: ctx)
        for feed in Synthetic.feeds(calendar: calendar, firstDay: scenario.firstDay, days: 15, dayGap: 210, nightGap: 270)
        where feed.start <= now {
            _ = LogEvent.create(kind: feed.kind, for: ada, start: feed.start, in: ctx)
        }
        ctx.saveIfNeeded()

        let summary = try #require(make([ada], ctx).babies.first)
        let sleep = try #require(summary.nextSleep)
        #expect(sleep.kind == .nap)
        #expect(sleep.start > now.addingTimeInterval(30 * 60) && sleep.end < now.addingTimeInterval(3 * 3600))
        #expect(sleep.end.timeIntervalSince(sleep.start) == 30 * 60)
        let feed = try #require(summary.nextFeed)
        #expect(feed.end.timeIntervalSince(feed.start) == 30 * 60)
        #expect(feed.centre > calendar.startOfDay(for: now))
        #expect(sleep.expiresAt == sleep.end.addingTimeInterval(3600))
        #expect(feed.expiresAt == feed.end.addingTimeInterval(3600))

        // Matches the predictor run directly on the same inputs.
        let direct = PredictionInputs.predictions(for: ada, in: ctx, now: now)
        #expect(direct.sleep.map(WidgetSnapshot.NextSleep.init) == sleep)
        #expect(direct.feed.map(WidgetSnapshot.NextFeed.init) == feed)
    }

    @Test func noNapWindowWhileAsleepOrWithoutAWakeUp() throws {
        let (_, ctx) = TestSupport.makeContext()
        let ada = baby(ageDays: 190, in: ctx)
        // Nothing logged: a window counted from "now" would move on every rewrite, so none is written.
        #expect(try #require(make([ada], ctx).babies.first).nextSleep == nil)

        insert(scenario.sleeps(.sixMonths, now: now), for: ada, in: ctx)
        ctx.saveIfNeeded()
        #expect(try #require(make([ada], ctx).babies.first).nextSleep != nil)

        _ = LogEvent.create(kind: .sleep, for: ada, start: now.addingTimeInterval(-10 * 60), in: ctx)
        ctx.saveIfNeeded()
        #expect(try #require(make([ada], ctx).babies.first).nextSleep == nil, "asleep now")
    }

    @Test func aBabyWithoutABirthDateGetsNoPredictions() throws {
        let (_, ctx) = TestSupport.makeContext()
        let ada = baby(ageDays: 190, in: ctx)
        ada.birthDate = nil
        _ = LogEvent.create(kind: .bottle, for: ada, start: now.addingTimeInterval(-3600), in: ctx)
        let summary = try #require(make([ada], ctx).babies.first)
        #expect(summary.nextSleep == nil && summary.nextFeed == nil)
    }

    @Test func predictionsParticipateInEquivalence() {
        let id = UUID()
        let window = NextSleepFixture.sleep(now)
        var a = WidgetSnapshot(generatedAt: now, babies: [.init(id: id, name: "Ada", nextSleep: window)])
        var b = a
        b.generatedAt = now.addingTimeInterval(60)
        #expect(a.isEquivalent(to: b))
        b.babies[0].nextSleep = NextSleepFixture.sleep(now.addingTimeInterval(1800))
        #expect(!a.isEquivalent(to: b))
        a.babies[0].nextSleep = nil
        b.babies[0].nextSleep = nil
        b.babies[0].nextFeed = .init(start: now, end: now.addingTimeInterval(1800))
        #expect(!a.isEquivalent(to: b))
    }

    // MARK: JSON

    @Test func snapshotsWrittenByOlderVersionsStillDecode() throws {
        let json = """
        {"generatedAt": 794800000, "volumeUnit": "milliliters", "selectedBabyID": "6B29FC40-CA47-1067-B31D-00DD010662DA",
         "babies": [{"id": "6B29FC40-CA47-1067-B31D-00DD010662DA", "name": "Juniper",
                     "lastSleepEndedAt": 794799000, "nextSide": "right",
                     "today": {"feeds": 3, "diapers": 4, "sleep": 5400}}]}
        """
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        let baby = try #require(snapshot.babies.first)
        #expect(baby.name == "Juniper")
        #expect(baby.nextSide == .right)
        #expect(baby.today.feeds == 3)
        #expect(baby.nextSleep == nil)
        #expect(baby.nextFeed == nil)

        // And through the file reader.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("old-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        #expect(WidgetSnapshot.read(from: url)?.babies.first?.name == "Juniper")
    }

    @Test func predictionsRoundTripThroughJSON() throws {
        let id = UUID()
        let snapshot = WidgetSnapshot(generatedAt: now, babies: [
            .init(
                id: id, name: "Ada",
                nextSleep: .init(kind: .bedtime, start: now, end: now.addingTimeInterval(1800)),
                nextFeed: .init(start: now.addingTimeInterval(600), end: now.addingTimeInterval(2400))
            ),
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pred-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.write(to: url)
        let read = try #require(WidgetSnapshot.read(from: url))
        #expect(read == snapshot)
        #expect(read.babies[0].nextSleep?.kind == .bedtime)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"bedtime\""), "the kind is stored as a readable raw value")
    }
}

private enum NextSleepFixture {
    static func sleep(_ start: Date) -> WidgetSnapshot.NextSleep {
        .init(kind: .nap, start: start, end: start.addingTimeInterval(1800))
    }
}
