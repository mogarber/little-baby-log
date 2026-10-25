import Combine
import CoreData
import Foundation
import UIKit
import BabyLogKit

/// Wires the app's data to the outside world: after saves, remote (iCloud) changes, and preference changes it
/// refreshes the widget snapshot and the Live Activities.
@MainActor
enum AppServices {
    private static var cancellables = Set<AnyCancellable>()
    private static var started = false

    /// Call once at launch. Safe to call again.
    static func start(persistence: PersistenceController = .shared) {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        let coordinator = persistence.container.persistentStoreCoordinator

        let saves = center.publisher(for: .NSManagedObjectContextDidSave)
            .filter { ($0.object as? NSManagedObjectContext)?.persistentStoreCoordinator === coordinator }
            .map { _ in () }
        let remote = center.publisher(for: .NSPersistentStoreRemoteChange)
            .filter { ($0.object as? NSPersistentStoreCoordinator) === coordinator }
            .map { _ in () }
        // Selected baby and units are part of the snapshot. UserDefaults posts for every key, so only pass on
        // a change of one of those three values.
        func currentPrefs() -> [String] {
            [Prefs.selectedBabyID, Prefs.volumeUnit, Prefs.unitSystem].map { UserDefaults.standard.string(forKey: $0) ?? "" }
        }
        let prefs = center.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in currentPrefs() }
            .prepend(currentPrefs())
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        // Live Activities follow quickly; widgets can wait a second and coalesce bursts of saves.
        Publishers.Merge(saves, remote)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { _ in Task { await LiveActivityManager.shared.reconcile() } }
            .store(in: &cancellables)

        Publishers.Merge3(saves, remote, prefs)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { _ in WidgetSnapshotWriter.shared.refresh() }
            .store(in: &cancellables)

        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in Task { await syncNow() } }
            .store(in: &cancellables)

        Task { await syncNow() }
    }

    /// Updates the snapshot, widget timelines, and Live Activities immediately.
    static func syncNow() async {
        WidgetSnapshotWriter.shared.refresh()
        await LiveActivityManager.shared.reconcile()
    }
}
