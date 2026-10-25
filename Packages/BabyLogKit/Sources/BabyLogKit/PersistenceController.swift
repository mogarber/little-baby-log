import CloudKit
import CoreData
import os

public enum SharingError: Error, LocalizedError {
    case cloudSyncDisabled
    case storeUnavailable

    public var errorDescription: String? {
        switch self {
        case .cloudSyncDisabled: return "iCloud sync is turned off in this build."
        case .storeUnavailable: return "The data store isn't available."
        }
    }
}

public final class PersistenceController {
    public let container: NSPersistentContainer
    public private(set) var privateStore: NSPersistentStore?
    public private(set) var sharedStore: NSPersistentStore?
    public private(set) var loadError: Error?
    public let cloudKitContainerIdentifier: String?

    public var viewContext: NSManagedObjectContext { container.viewContext }

    /// Non-nil only in iCloud mode.
    public var cloudKitContainer: NSPersistentCloudKitContainer? { container as? NSPersistentCloudKitContainer }

    public var isCloudSyncEnabled: Bool { cloudKitContainer != nil }

    private static let storeName = "LittleBabyLog"

    /// `cloudKitContainerIdentifier` nil/empty → plain local `NSPersistentContainer` (no CloudKit types are touched,
    /// so it builds and runs without the iCloud entitlement). `inMemory` also forces local mode.
    public init(cloudKitContainerIdentifier: String? = nil, inMemory: Bool = false, storeDirectory: URL? = nil) {
        let trimmedID = cloudKitContainerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cloudID = (trimmedID?.isEmpty == false && !inMemory) ? trimmedID : nil
        self.cloudKitContainerIdentifier = cloudID

        let model = BabyLogModel.model
        let directory = storeDirectory ?? NSPersistentContainer.defaultDirectoryURL()
        let privateURL: URL
        let sharedURL = directory.appendingPathComponent("shared.sqlite")
        if inMemory {
            privateURL = URL(fileURLWithPath: "/dev/null")
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            privateURL = directory.appendingPathComponent("private.sqlite")
        }

        func makeDescription(url: URL) -> NSPersistentStoreDescription {
            let description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            return description
        }

        let privateDescription = makeDescription(url: privateURL)
        var descriptions = [privateDescription]

        if let cloudID {
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            let sharedDescription = makeDescription(url: sharedURL)
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
            descriptions.append(sharedDescription)

            container = NSPersistentCloudKitContainer(name: Self.storeName, managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: Self.storeName, managedObjectModel: model)
        }
        container.persistentStoreDescriptions = descriptions

        let isCloud = cloudID != nil
        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                BabyLogLog.persistence.error("Store load failed: \(error.localizedDescription, privacy: .public)")
                self.loadError = error
                return
            }
            guard let url = description.url,
                  let store = self.container.persistentStoreCoordinator.persistentStore(for: url) else { return }
            if isCloud && url == sharedURL {
                self.sharedStore = store
            } else {
                self.privateStore = store
            }
        }

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.name = "viewContext"
    }

    // MARK: - Sharing

    /// True when the object lives in the shared store, i.e. it was shared WITH me.
    public func isInSharedStore(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore === sharedStore
    }

    public func existingShare(for object: NSManagedObject) -> CKShare? {
        guard let cloud = cloudKitContainer else { return nil }
        let shares = try? cloud.fetchShares(matching: [object.objectID])
        return shares?[object.objectID]
    }

    public func isShared(_ object: NSManagedObject) -> Bool {
        existingShare(for: object) != nil
    }

    public func canEdit(_ object: NSManagedObject) -> Bool {
        guard let cloud = cloudKitContainer else { return true }
        return cloud.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    /// Returns the existing share or creates one.
    public func share(_ baby: Baby) async throws -> (CKShare, CKContainer) {
        guard let cloud = cloudKitContainer, let identifier = cloudKitContainerIdentifier else {
            throw SharingError.cloudSyncDisabled
        }
        if let existing = existingShare(for: baby) {
            return (existing, CKContainer(identifier: identifier))
        }
        let name = baby.displayName
        let (_, share, ckContainer) = try await cloud.share([baby], to: nil)
        share[CKShare.SystemFieldKey.title] = name
        return (share, ckContainer)
    }

    public func acceptShareInvitations(from metadata: [CKShare.Metadata]) async throws {
        guard let cloud = cloudKitContainer else { throw SharingError.cloudSyncDisabled }
        guard let sharedStore else { throw SharingError.storeUnavailable }
        guard !metadata.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cloud.acceptShareInvitations(from: metadata, into: sharedStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Persists a share that was modified by the system sharing UI into the private store.
    public func persistUpdatedShare(_ share: CKShare) {
        guard let cloud = cloudKitContainer, let privateStore else { return }
        cloud.persistUpdatedShare(share, in: privateStore) { _, error in
            if let error {
                BabyLogLog.persistence.error("persistUpdatedShare failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A participant left a share: purge its zone from the shared store.
    public func purgeSharedZone(of share: CKShare) {
        guard let cloud = cloudKitContainer, let sharedStore else { return }
        cloud.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore) { _, error in
            if let error {
                BabyLogLog.persistence.error("purgeSharedZone failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
