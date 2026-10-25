import CoreData
import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct WidgetSnapshotTests {
    /// 15:00 local time, so "earlier today" events don't cross local midnight in any time zone.
    let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 15))!

    private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    private func make(_ babies: [Baby], _ ctx: NSManagedObjectContext, selected: UUID? = nil, unit: VolumeUnit = .milliliters) -> WidgetSnapshot {
        WidgetSnapshot.make(babies: babies, context: ctx, selectedBabyID: selected, volumeUnit: unit, unitSystem: .metric, now: now)
    }

    @Test func emptyBabyHasNoDerivedFields() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let snapshot = make([baby], ctx)
        let summary = try #require(snapshot.babies.first)
        #expect(summary.id == baby.uuid)
        #expect(summary.name == "Ada")
        #expect(summary.lastFeed == nil)
        #expect(summary.nextSide == nil)
        #expect(summary.lastDiaperAt == nil)
        #expect(summary.lastSleepEndedAt == nil)
        #expect(summary.runningSleepStartedAt == nil)
        #expect(summary.runningNursing == nil)
        #expect(summary.today == .init())
        #expect(snapshot.generatedAt == now)
    }

    @Test func sampleDataSnapshot() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = SampleData.populate(ctx, now: now)
        let snapshot = make([baby], ctx, selected: baby.uuid, unit: .ounces)
        let summary = try #require(snapshot.babies.first)
        #expect(summary.name == "Juniper")
        #expect(snapshot.selectedBabyID == baby.uuid)
        #expect(snapshot.volumeUnit == .ounces)
        #expect(summary.lastFeed != nil)
        #expect(summary.lastDiaperAt != nil)
        #expect(summary.lastDiaperKind != nil)
        #expect(summary.lastSleepEndedAt != nil)
        #expect(summary.runningNursing == nil)
        #expect(summary.runningSleepStartedAt == nil)

        // Today's numbers agree with DaySummary.
        let start = Calendar.current.startOfDay(for: now)
        let events = try ctx.fetch(LogEvent.requestOverlapping(baby: baby, from: start))
        let day = DaySummary(events: events, interval: DateInterval(start: start, duration: 86_400), now: now)
        #expect(summary.today.feeds == day.feedCount)
        #expect(summary.today.diapers == day.diaperCount)
        #expect(summary.today.sleep == day.sleep)
    }

    @Test func lastFeedNextSideAndDetails() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)

        let nursing = LogEvent.create(kind: .breastfeed, for: baby, start: minutesAgo(200), in: ctx)
        nursing.startSide(.left, at: minutesAgo(200))
        nursing.startSide(.right, at: minutesAgo(192))
        nursing.finishNursing(at: minutesAgo(186))
        // lastSide is .right → next is .left
        var summary = try #require(make([baby], ctx).babies.first)
        #expect(summary.nextSide == .left)
        let feed = try #require(summary.lastFeed)
        #expect(feed.kind == .breastfeed)
        #expect(feed.detail == "L 8m · R 6m")
        #expect(feed.startedAt == minutesAgo(200))
        #expect(feed.endedAt == minutesAgo(186))
        #expect(feed.referenceDate == minutesAgo(186))

        let bottle = LogEvent.create(kind: .bottle, for: baby, start: minutesAgo(90), in: ctx)
        bottle.amountML = 120
        bottle.bottleContent = .formula
        summary = try #require(make([baby], ctx).babies.first)
        #expect(summary.lastFeed?.kind == .bottle)
        #expect(summary.lastFeed?.detail == "120 ml formula")
        #expect(summary.lastFeed?.endedAt == nil)
        #expect(summary.lastFeed?.referenceDate == minutesAgo(90))
        #expect(summary.nextSide == .left, "a bottle doesn't change the suggested side")

        let oz = try #require(make([baby], ctx, unit: .ounces).babies.first)
        #expect(oz.lastFeed?.detail == "4.1 oz formula")
    }

    @Test func diapersAndSleep() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let wet = LogEvent.create(kind: .diaper, for: baby, start: minutesAgo(80), in: ctx)
        wet.diaperKind = .wet
        let dirty = LogEvent.create(kind: .diaper, for: baby, start: minutesAgo(20), in: ctx)
        dirty.diaperKind = .dirty
        let nap = LogEvent.create(kind: .sleep, for: baby, start: minutesAgo(150), in: ctx)
        nap.endDate = minutesAgo(100)

        var summary = try #require(make([baby], ctx).babies.first)
        #expect(summary.lastDiaperAt == minutesAgo(20))
        #expect(summary.lastDiaperKind == .dirty)
        #expect(summary.lastSleepEndedAt == minutesAgo(100))
        #expect(summary.runningSleepStartedAt == nil)
        #expect(summary.today.diapers == 2)
        #expect(summary.today.sleep == 50 * 60)

        let sleeping = LogEvent.create(kind: .sleep, for: baby, start: minutesAgo(30), in: ctx)
        summary = try #require(make([baby], ctx).babies.first)
        #expect(sleeping.isRunning)
        #expect(summary.runningSleepStartedAt == minutesAgo(30))
        #expect(summary.lastSleepEndedAt == minutesAgo(100), "a running sleep isn't a finished one")
        #expect(summary.today.sleep == 80 * 60, "running sleep counts up to now")
    }

    @Test func runningNursing() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: minutesAgo(10), in: ctx)
        event.startSide(.left, at: minutesAgo(10))
        event.startSide(.right, at: minutesAgo(6))   // left banks 240s, right active since 6m ago

        let summary = try #require(make([baby], ctx).babies.first)
        let nursing = try #require(summary.runningNursing)
        #expect(nursing.startedAt == minutesAgo(10))
        #expect(nursing.leftSeconds == 240)
        #expect(nursing.rightSeconds == 0)
        #expect(nursing.activeSide == .right)
        #expect(nursing.activeSideStartedAt == minutesAgo(6))
        #expect(nursing.seconds(.left, at: now) == 240)
        #expect(nursing.seconds(.right, at: now) == 360)
        #expect(nursing.total(at: now) == 600)
        #expect(nursing.total(at: now.addingTimeInterval(60)) == 660)

        // timerInterval reference: now - reference == total
        let reference = try #require(nursing.liveTotalReferenceStart)
        #expect(now.timeIntervalSince(reference) == 600)
        #expect(now.addingTimeInterval(60).timeIntervalSince(reference) == 660)

        // The running session is the last feed, with no end yet.
        #expect(summary.lastFeed?.kind == .breastfeed)
        #expect(summary.lastFeed?.endedAt == nil)
        #expect(summary.nextSide == nil, "no finished nursing yet")

        // Paused → no live reference, static total.
        event.pauseNursing(at: minutesAgo(1))
        let paused = try #require(make([baby], ctx).babies.first?.runningNursing)
        #expect(paused.activeSide == nil)
        #expect(paused.liveTotalReferenceStart == nil)
        #expect(paused.total(at: now) == 540)
    }

    @Test func multipleBabiesAndLookup() throws {
        let (_, ctx) = TestSupport.makeContext()
        let a = Baby.create(name: "Ada", birthDate: now, in: ctx)
        let b = Baby.create(name: "Bo", birthDate: now, in: ctx)
        let snapshot = make([a, b], ctx, selected: b.uuid)
        #expect(snapshot.babies.map(\.name) == ["Ada", "Bo"])
        #expect(snapshot.baby(id: a.uuid)?.name == "Ada")
        #expect(snapshot.baby(id: nil)?.name == "Bo", "nil follows the app's selected baby")
        #expect(snapshot.baby(id: UUID())?.name == "Bo", "unknown id falls back too")
        var noSelection = snapshot
        noSelection.selectedBabyID = nil
        #expect(noSelection.baby(id: nil)?.name == "Ada")
        #expect(WidgetSnapshot().baby(id: nil) == nil)
    }

    @Test func jsonRoundTripAndAtomicFile() throws {
        let (_, ctx) = TestSupport.makeContext()
        let baby = SampleData.populate(ctx, now: now)
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: minutesAgo(5), in: ctx)
        event.startSide(.right, at: minutesAgo(5))
        let snapshot = make([baby], ctx, selected: baby.uuid, unit: .ounces)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.write(to: url)
        let read = try #require(WidgetSnapshot.read(from: url))
        #expect(read == snapshot)

        // Overwrite works and leaves no temp files behind.
        var changed = snapshot
        changed.volumeUnit = .milliliters
        try changed.write(to: url)
        #expect(WidgetSnapshot.read(from: url) == changed)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(url.lastPathComponent) && $0 != url.lastPathComponent }
        #expect(leftovers.isEmpty)
    }

    @Test func readFailuresReturnNil() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(WidgetSnapshot.read(from: missing) == nil)
        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: garbage) }
        try Data("{not json".utf8).write(to: garbage)
        #expect(WidgetSnapshot.read(from: garbage) == nil)
    }

    @Test func equivalenceIgnoresGeneratedAt() {
        let id = UUID()
        let a = WidgetSnapshot(generatedAt: now, babies: [.init(id: id, name: "Ada")])
        var b = a
        b.generatedAt = now.addingTimeInterval(60)
        #expect(a != b)
        #expect(a.isEquivalent(to: b))
        b.babies[0].name = "Bea"
        #expect(!a.isEquivalent(to: b))
    }

    @Test func enumsAreCodableByRawValue() throws {
        let kinds = try JSONDecoder().decode([EventKind].self, from: Data(#"["sleep","breastfeed"]"#.utf8))
        #expect(kinds == [.sleep, .breastfeed])
        #expect(String(decoding: try JSONEncoder().encode(BreastSide.left), as: UTF8.self) == "\"left\"")
        #expect(String(decoding: try JSONEncoder().encode(DiaperKind.mixed), as: UTF8.self) == "\"mixed\"")
        #expect(String(decoding: try JSONEncoder().encode(VolumeUnit.ounces), as: UTF8.self) == "\"ounces\"")
    }
}
