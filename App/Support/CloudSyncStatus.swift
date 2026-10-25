import CloudKit
import CoreData
import Foundation
import Observation
import UIKit
import BabyLogKit

/// The "iCloud sync" line in Settings. Driven by events, never by polling: `NSPersistentCloudKitContainer` posts
/// `eventChangedNotification` as each setup / import / export starts and ends, and the iCloud account status is
/// read at launch, when the app comes forward, and when the account changes.
@MainActor
@Observable
final class CloudSyncStatus {
    static let shared = CloudSyncStatus()

    enum State: Equatable {
        /// This build has iCloud turned off (no container).
        case off
        /// Waiting for the account check or the first sync event.
        case checking
        case notSignedIn
        /// Signed in, but iCloud is restricted or can't be reached for a reason that isn't a normal error.
        case unavailable
        case syncing
        case upToDate(lastSync: Date?)
        case error(CloudSyncProblem)
    }

    private(set) var state: State = .checking

    @ObservationIgnored private var persistence: PersistenceController?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var accountStatus: CKAccountStatus?
    @ObservationIgnored private var inFlight = Set<UUID>()
    @ObservationIgnored private var errors: [Int: CloudSyncProblem] = [:]
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private var sawEvent = false

    /// Call once at launch. Safe to call again.
    func start(persistence: PersistenceController) {
        guard !started else { return }
        started = true
        self.persistence = persistence
        guard let cloud = persistence.cloudKitContainer else {
            state = .off
            return
        }

        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: cloud, queue: .main
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event else { return }
            // Pull out plain values before hopping to the main actor.
            let info = EventInfo(
                id: event.identifier, type: event.type.rawValue, ended: event.endDate,
                succeeded: event.succeeded, error: event.error
            )
            MainActor.assumeIsolated { self?.handle(info) }
        }
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        }
        refreshAccount()
    }

    /// Reads the iCloud account status (a cheap, cached call) and recomputes the state.
    func refreshAccount() {
        guard let identifier = persistence?.cloudKitContainerIdentifier else { return }
        Task {
            let status = try? await CKContainer(identifier: identifier).accountStatus()
            accountStatus = status
            recompute()
        }
    }

    // MARK: Events

    private struct EventInfo {
        var id: UUID
        var type: Int
        var ended: Date?
        var succeeded: Bool
        var error: Error?
    }

    private func handle(_ event: EventInfo) {
        sawEvent = true
        if let ended = event.ended {
            inFlight.remove(event.id)
            if event.succeeded {
                errors[event.type] = nil
                lastSync = ended
            } else if let error = event.error {
                errors[event.type] = CloudSyncProblem.classify(error)
            }
        } else {
            inFlight.insert(event.id)
        }
        recompute()
    }

    private func recompute() {
        guard persistence?.isCloudSyncEnabled == true else {
            state = .off
            return
        }
        switch accountStatus {
        case .noAccount?:
            state = .notSignedIn
        case .restricted?, .temporarilyUnavailable?:
            state = .unavailable
        default:
            if !inFlight.isEmpty {
                state = .syncing
            } else if let problem = errors.values.min(by: { $0.technicalDetails < $1.technicalDetails }) {
                state = .error(problem)
            } else if sawEvent || lastSync != nil {
                state = .upToDate(lastSync: lastSync)
            } else {
                state = .checking
            }
        }
    }
}
