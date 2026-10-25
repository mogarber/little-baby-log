import CoreData
import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct PersistenceTests {
    let base = TestSupport.utc(2026, 3, 10, 12)

    @Test func inMemoryStoreLoads() {
        let p = PersistenceController(inMemory: true)
        #expect(p.loadError == nil)
        #expect(p.privateStore != nil)
        #expect(p.sharedStore == nil)
        #expect(!p.isCloudSyncEnabled)
        #expect(p.cloudKitContainer == nil)
        #expect(p.cloudKitContainerIdentifier == nil)
        #expect(p.viewContext.automaticallyMergesChangesFromParent)
    }

    @Test func emptyIdentifierStaysLocal() {
        let p = PersistenceController(cloudKitContainerIdentifier: "  ", inMemory: true)
        #expect(!p.isCloudSyncEnabled)
        #expect(p.privateStore != nil)
    }

    @Test func localSharingAPIsAreInert() async {
        let p = PersistenceController(inMemory: true)
        let baby = Baby.create(name: "Ada", birthDate: base, in: p.viewContext)
        #expect(!p.isInSharedStore(baby))
        #expect(!p.isShared(baby))
        #expect(p.existingShare(for: baby) == nil)
        #expect(p.canEdit(baby))
        do {
            _ = try await p.share(baby)
            Issue.record("expected cloudSyncDisabled")
        } catch let error as SharingError {
            #expect(error == .cloudSyncDisabled || error.errorDescription != nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func fetchRequests() throws {
        let p = PersistenceController(inMemory: true)
        let ctx = p.viewContext
        let baby = Baby.create(name: "Ada", birthDate: base, in: ctx)
        let other = Baby.create(name: "Bo", birthDate: base, in: ctx)

        // Finished sleep fully before the cutoff.
        let oldSleep = LogEvent.create(kind: .sleep, for: baby, start: base.addingTimeInterval(-10 * 3600), in: ctx)
        oldSleep.endDate = base.addingTimeInterval(-9 * 3600)
        // Sleep that started before the cutoff but ended after: overlaps.
        let crossing = LogEvent.create(kind: .sleep, for: baby, start: base.addingTimeInterval(-3 * 3600), in: ctx)
        crossing.endDate = base.addingTimeInterval(1800)
        // Running sleep that started long before: overlaps.
        let runningSleep = LogEvent.create(kind: .sleep, for: baby, start: base.addingTimeInterval(-20 * 3600), in: ctx)
        // Instant events (endDate nil) before and after the cutoff.
        let oldDiaper = LogEvent.create(kind: .diaper, for: baby, start: base.addingTimeInterval(-5 * 3600), in: ctx)
        oldDiaper.diaperKind = .wet
        let newDiaper = LogEvent.create(kind: .diaper, for: baby, start: base.addingTimeInterval(3600), in: ctx)
        newDiaper.diaperKind = .dirty
        // Running nursing and a finished one.
        let runningNurse = LogEvent.create(kind: .breastfeed, for: baby, start: base.addingTimeInterval(7200), in: ctx)
        let doneNurse = LogEvent.create(kind: .breastfeed, for: baby, start: base.addingTimeInterval(-7200), in: ctx)
        doneNurse.endDate = base.addingTimeInterval(-6600)
        // Other baby's data must never leak.
        let otherSleep = LogEvent.create(kind: .sleep, for: other, start: base, in: ctx)
        _ = otherSleep
        #expect(ctx.saveIfNeeded())

        // requestAll
        let all = try ctx.fetch(LogEvent.requestAll(baby: baby))
        #expect(all.count == 7)
        #expect(all.first === runningNurse, "sorted newest first")
        let ascending = try ctx.fetch(LogEvent.requestAll(baby: baby, ascending: true))
        #expect(ascending.first === runningSleep)
        let diapersOnly = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.diaper]))
        #expect(Set(diapersOnly.map(\.objectID)) == Set([oldDiaper, newDiaper].map(\.objectID)))

        // requestOverlapping
        let cutoff = base.addingTimeInterval(-3600)
        let overlapping = try ctx.fetch(LogEvent.requestOverlapping(baby: baby, from: cutoff))
        let overlapIDs = Set(overlapping.map(\.objectID))
        #expect(overlapIDs == Set([crossing, runningSleep, newDiaper, runningNurse].map(\.objectID)))
        #expect(!overlapIDs.contains(oldSleep.objectID))
        #expect(!overlapIDs.contains(oldDiaper.objectID), "instant event before cutoff must not count as running")
        #expect(!overlapIDs.contains(doneNurse.objectID))

        // requestRunning
        let running = try ctx.fetch(LogEvent.requestRunning(baby: baby))
        #expect(Set(running.map(\.objectID)) == Set([runningSleep, runningNurse].map(\.objectID)))

        // requestLatest
        let latestDiaper = try ctx.fetch(LogEvent.requestLatest(baby: baby, kinds: [.diaper]))
        #expect(latestDiaper.count == 1)
        #expect(latestDiaper.first === newDiaper)

        let latestFeed = try ctx.fetch(LogEvent.requestLatest(baby: baby, kinds: [.breastfeed, .bottle]))
        #expect(latestFeed.first === runningNurse)
        let latestFinishedFeed = try ctx.fetch(LogEvent.requestLatest(baby: baby, kinds: [.breastfeed, .bottle], finishedOnly: true))
        #expect(latestFinishedFeed.count == 1)
        #expect(latestFinishedFeed.first === doneNurse)

        let latestFinishedSleep = try ctx.fetch(LogEvent.requestLatest(baby: baby, kinds: [.sleep], finishedOnly: true))
        #expect(latestFinishedSleep.first === crossing)

        let none = try ctx.fetch(LogEvent.requestLatest(baby: baby, kinds: [.growth]))
        #expect(none.isEmpty)
    }

    @Test func eventsAreInSameStoreAsBaby() throws {
        let p = PersistenceController(inMemory: true)
        let ctx = p.viewContext
        let baby = Baby.create(name: "Ada", birthDate: base, in: ctx)
        ctx.assign(baby, to: p.privateStore!)
        let event = LogEvent.create(kind: .diaper, for: baby, in: ctx)
        #expect(event.objectID.persistentStore === baby.objectID.persistentStore)
        #expect(event.uuid != nil && event.createdAt != nil && event.modifiedAt != nil)
        #expect(event.baby === baby)
        #expect(ctx.saveIfNeeded())
        #expect(!p.isInSharedStore(event))
    }

    @Test func cascadeDeleteAndDefaults() throws {
        let p = PersistenceController(inMemory: true)
        let ctx = p.viewContext
        let baby = Baby.create(name: "", birthDate: base, in: ctx)
        #expect(baby.displayName == "Baby")
        #expect(baby.uuid != nil && baby.createdAt != nil)
        let event = LogEvent.create(kind: .pump, for: baby, in: ctx)
        #expect(event.leftML == 0 && event.weightKg == 0 && event.leftSeconds == 0)
        event.kindRaw = "bogus"
        #expect(event.kind == .sleep)
        ctx.saveIfNeeded()
        ctx.delete(baby)
        ctx.saveIfNeeded()
        #expect(try ctx.fetch(LogEvent.fetchRequest()).isEmpty)
    }

    @Test func fileBackedStoreReopens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let p = PersistenceController(storeDirectory: dir)
            #expect(p.loadError == nil)
            _ = Baby.create(name: "Ada", birthDate: base, in: p.viewContext)
            #expect(p.viewContext.saveIfNeeded())
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("private.sqlite").path))
        }
        let again = PersistenceController(storeDirectory: dir)
        let babies = try again.viewContext.fetch(Baby.fetchRequest())
        #expect(babies.map(\.name) == ["Ada"])
    }

    @Test func sampleDataPopulates() throws {
        let p = PersistenceController(inMemory: true)
        let ctx = p.viewContext
        let now = Date.now
        let baby = SampleData.populate(ctx, now: now)
        #expect(baby.name == "Juniper")
        #expect(!ctx.hasChanges)
        let events = try ctx.fetch(LogEvent.requestAll(baby: baby))
        #expect(events.count > 40)
        #expect(Set(events.map(\.kind)).isSuperset(of: [.sleep, .breastfeed, .bottle, .diaper, .pump, .growth]))
        #expect(events.allSatisfy { ($0.startDate ?? .distantFuture) <= now })
        #expect(try ctx.fetch(LogEvent.requestRunning(baby: baby)).isEmpty)
        let age = BabyAge.description(birthDate: baby.birthDate!, now: now)
        #expect(age == "1 month, 2 weeks" || age.contains("week"))
        let summary = DaySummary(events: events, interval: DateInterval(start: Calendar.current.startOfDay(for: now).addingTimeInterval(-86400), duration: 86400), now: now)
        #expect(summary.diaperCount > 0 && summary.sleep > 3600)
    }
}
