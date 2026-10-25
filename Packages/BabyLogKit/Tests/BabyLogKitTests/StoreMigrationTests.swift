import CoreData
import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct StoreMigrationTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    /// Fills a store at `directory` with sample data and closes it, leaving the -wal file as an app kill would.
    private func makeOldStore(at directory: URL) throws -> (babies: Int, events: Int) {
        let controller = PersistenceController(storeDirectory: directory)
        #expect(controller.loadError == nil)
        SampleData.populate(controller.viewContext)
        let counts = (
            try controller.viewContext.count(for: Baby.fetchRequest()),
            try controller.viewContext.count(for: LogEvent.fetchRequest())
        )
        // Detach so the files aren't held open (the next launch is a new process).
        let coordinator = controller.container.persistentStoreCoordinator
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        return counts
    }

    @Test func migratesStoreWithItsData() throws {
        let old = try tempDirectory(), new = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        let expected = try makeOldStore(at: old)
        #expect(expected.babies == 1 && expected.events > 20)

        #expect(StoreMigration.migrateIfNeeded(from: old, to: new))

        let controller = PersistenceController(storeDirectory: new)
        #expect(controller.loadError == nil)
        #expect(try controller.viewContext.count(for: Baby.fetchRequest()) == expected.babies)
        #expect(try controller.viewContext.count(for: LogEvent.fetchRequest()) == expected.events)

        // The old store is gone, and no staging folder is left behind.
        #expect(names(in: old).filter { $0.hasPrefix("private.sqlite") }.isEmpty)
        #expect(names(in: new).filter { $0.hasPrefix(".migrating") }.isEmpty)
        #expect(names(in: new).contains("private.sqlite"))
    }

    @Test func migratesSharedStoreToo() throws {
        let old = try tempDirectory(), new = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        _ = try makeOldStore(at: old)
        // Pretend a shared store exists as well (a copy of a valid store is a valid store).
        try FileManager.default.copyItem(at: old.appendingPathComponent("private.sqlite"), to: old.appendingPathComponent("shared.sqlite"))

        #expect(StoreMigration.migrateIfNeeded(from: old, to: new))
        #expect(names(in: new).isSuperset(of: ["private.sqlite", "shared.sqlite"]))
        #expect(names(in: old).filter { $0.hasSuffix(".sqlite") }.isEmpty)
    }

    @Test func doesNothingWhenNewStoreExists() throws {
        let old = try tempDirectory(), new = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        _ = try makeOldStore(at: old)
        let existing = Data("existing".utf8)
        try existing.write(to: new.appendingPathComponent("private.sqlite"))

        #expect(StoreMigration.migrateIfNeeded(from: old, to: new))
        #expect(try Data(contentsOf: new.appendingPathComponent("private.sqlite")) == existing, "never overwrites")
        #expect(names(in: old).contains("private.sqlite"), "never deletes the old store unless the copy succeeded")
    }

    @Test func doesNothingWithoutAnOldStore() throws {
        let old = try tempDirectory(), new = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        #expect(StoreMigration.migrateIfNeeded(from: old, to: new))
        #expect(names(in: new).isEmpty)
        // Same directory is a no-op too.
        #expect(StoreMigration.migrateIfNeeded(from: old, to: old))
    }

    @Test func failureKeepsTheOldStore() throws {
        let old = try tempDirectory(), new = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        // A corrupt "store" can't be copied.
        try Data("not a database".utf8).write(to: old.appendingPathComponent("private.sqlite"))
        #expect(!StoreMigration.migrateIfNeeded(from: old, to: new))
        #expect(names(in: old).contains("private.sqlite"))
        #expect(!names(in: new).contains("private.sqlite"))
        #expect(names(in: new).filter { $0.hasPrefix(".migrating") }.isEmpty)
    }
}
