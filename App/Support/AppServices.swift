import Combine
import CoreData
import Foundation
import UIKit
import BabyLogKit

/// Wires the app's data to the outside world: after saves, remote (iCloud) changes, and preference changes it
/// refreshes the widget snapshot, the Live Activities, the reminders, and the iCloud sync status.
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
        // Updating and ending activities works in the background (a partner finishing a timer ends mine when
        // the CloudKit push wakes the app); starting waits for the foreground, see LiveActivityManager.
        saves
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { _ in
                Task {
                    await LiveActivityManager.shared.reconcile(.change)
                    await ReminderScheduler.shared.refresh()
                }
            }
            .store(in: &cancellables)

        // The remote-change notification can arrive before the view context has merged the new rows, so hop
        // onto the main actor and queue behind the merge on the view context before fetching.
        remote
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { _ in
                Task { @MainActor in
                    await persistence.viewContext.perform {}
                    await LiveActivityManager.shared.reconcile(.change)
                    // A feed logged on a partner's phone moves my "feed every N hours" reminder too.
                    await ReminderScheduler.shared.refresh()
                }
            }
            .store(in: &cancellables)

        Publishers.Merge3(saves, remote, prefs)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { _ in WidgetSnapshotWriter.shared.refresh() }
            .store(in: &cancellables)

        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in Task { await syncNow() } }
            .store(in: &cancellables)

        CloudSyncStatus.shared.start(persistence: persistence)

        Task {
            #if DEBUG
            await DebugHooks.prepare()
            #endif
            await syncNow(.launch)
        }
    }

    /// The scene became active (launch, return from the background, unlock): the one moment Live Activities
    /// that were waiting for the foreground can start.
    static func sceneDidBecomeActive() async {
        await LiveActivityManager.shared.reconcile(.foreground)
        // Notification permission or the clock may have changed while away.
        await ReminderScheduler.shared.refresh()
        CloudSyncStatus.shared.refreshAccount()
    }

    /// Updates the snapshot, widget timelines, Live Activities, and reminders immediately.
    static func syncNow(_ trigger: LiveActivityManager.Trigger = .change) async {
        WidgetSnapshotWriter.shared.refresh()
        await LiveActivityManager.shared.reconcile(trigger)
        await ReminderScheduler.shared.refresh()
    }
}
