import CoreData
import Foundation

/// One-time move of the Core Data store files from one directory to another (the app's default Application
/// Support directory → the App Group container).
public enum StoreMigration {
    /// The store files `PersistenceController` creates, in the order they're migrated.
    public static let storeFileNames = ["private.sqlite", "shared.sqlite"]

    /// For each store file that exists in `oldDirectory` but not yet in `newDirectory`: copy it over with
    /// `replacePersistentStore` (which folds in the write-ahead log), and only then delete the old files.
    ///
    /// The copy is staged in a temporary folder inside `newDirectory` and the `.sqlite` file is moved into
    /// place last, so an interrupted migration never leaves a half-written store where the app looks for it
    /// (the next launch simply starts over). Nothing in the old location is deleted unless the new copy
    /// is in place. Returns `true` if every store file that needed migrating now lives in `newDirectory`.
    @discardableResult
    public static func migrateIfNeeded(from oldDirectory: URL, to newDirectory: URL) -> Bool {
        guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return true }
        let fileManager = FileManager.default
        var allSucceeded = true
        for name in storeFileNames {
            let oldURL = oldDirectory.appendingPathComponent(name)
            let newURL = newDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: oldURL.path), !fileManager.fileExists(atPath: newURL.path) else { continue }
            do {
                try migrate(name: name, from: oldDirectory, to: newDirectory)
                BabyLogLog.persistence.info("Migrated \(name, privacy: .public) to the shared container")
            } catch {
                allSucceeded = false
                BabyLogLog.persistence.error("Store migration of \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return allSucceeded
    }

    private enum MigrationError: Error, LocalizedError {
        case verificationFailed
        var errorDescription: String? { "The copied store doesn't match the original." }
    }

    /// (babies, events) in the store at `url`; opens and closes a throwaway coordinator.
    private static func entityCounts(at url: URL, options: [AnyHashable: Any]) throws -> [Int] {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: BabyLogModel.model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        var counts: [Int] = []
        var failure: Error?
        context.performAndWait {
            do {
                counts = [
                    try context.count(for: Baby.fetchRequest()),
                    try context.count(for: LogEvent.fetchRequest()),
                ]
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return counts
    }

    private static func migrate(name: String, from oldDirectory: URL, to newDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)

        let oldURL = oldDirectory.appendingPathComponent(name)
        let staging = newDirectory.appendingPathComponent(".migrating-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let stagedURL = staging.appendingPathComponent(name)

        let options: [AnyHashable: Any] = [
            NSPersistentHistoryTrackingKey: true,
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: true,
        ]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: BabyLogModel.model)
        try coordinator.replacePersistentStore(
            at: stagedURL,
            destinationOptions: options,
            withPersistentStoreFrom: oldURL,
            sourceOptions: options,
            type: .sqlite
        )

        // Make sure the copy holds what the original does before anything is moved or deleted.
        let expected = try entityCounts(at: oldURL, options: options)
        let actual = try entityCounts(at: stagedURL, options: options)
        guard expected == actual else { throw MigrationError.verificationFailed }

        // Move everything the copy produced next to the final location; the main file goes last because
        // its existence is what marks the migration as complete.
        let staged = try fileManager.contentsOfDirectory(atPath: staging.path)
        for fileName in staged.filter({ $0 != name }) + staged.filter({ $0 == name }) {
            let source = staging.appendingPathComponent(fileName)
            let destination = newDirectory.appendingPathComponent(fileName)
            if fileName != name, fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }

        // The new copy is in place: remove the old store (including its -wal/-shm and external-data folder).
        let newURL = newDirectory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: newURL.path) else { return }
        try? coordinator.destroyPersistentStore(at: oldURL, type: .sqlite, options: options)
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: oldURL.path + suffix)
            if fileManager.fileExists(atPath: url.path) { try? fileManager.removeItem(at: url) }
        }
    }
}
