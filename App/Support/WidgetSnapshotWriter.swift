import CoreData
import Foundation
import WidgetKit
import os
import BabyLogKit

/// Builds the `WidgetSnapshot` for every baby and writes it into the App Group container, then reloads the
/// widget timelines. The widget extension never opens Core Data; this file is all it reads.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private static let log = Logger(subsystem: "app.littlebabylog", category: "widgets")

    private var lastWritten: WidgetSnapshot?
    private var readContext: NSManagedObjectContext?

    /// Builds and writes the snapshot now. Does nothing (no write, no timeline reload) when it matches
    /// what's already on disk apart from the timestamp.
    func refresh(persistence: PersistenceController = .shared) {
        guard persistence.loadError == nil, let url = AppGroup.snapshotURL else { return }

        let snapshot = makeSnapshot(persistence: persistence)
        if lastWritten == nil { lastWritten = WidgetSnapshot.read(from: url) }
        if let lastWritten, lastWritten.isEquivalent(to: snapshot) { return }

        do {
            try snapshot.write(to: url)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.log.error("Couldn't write the widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeSnapshot(persistence: PersistenceController) -> WidgetSnapshot {
        // A separate context, so the snapshot reflects what's saved and never half-edited objects in the UI.
        // It's reset before each read: a long-lived context would keep serving cached rows.
        let context: NSManagedObjectContext
        if let existing = readContext {
            context = existing
        } else {
            context = persistence.container.newBackgroundContext()
            context.name = "widgetSnapshot"
            readContext = context
        }
        let defaults = UserDefaults.standard
        let selected = defaults.string(forKey: Prefs.selectedBabyID).flatMap(UUID.init(uuidString:))
        let volumeUnit = defaults.string(forKey: Prefs.volumeUnit).flatMap(VolumeUnit.init(rawValue:)) ?? Prefs.defaultVolumeUnit
        let unitSystem = defaults.string(forKey: Prefs.unitSystem).flatMap(UnitSystem.init(rawValue:)) ?? Prefs.defaultUnitSystem

        var snapshot = WidgetSnapshot()
        context.performAndWait {
            context.reset()
            let request: NSFetchRequest<Baby> = Baby.lblAllByCreation()
            let babies = (try? context.fetch(request)) ?? []
            snapshot = WidgetSnapshot.make(
                babies: babies,
                context: context,
                selectedBabyID: selected,
                volumeUnit: volumeUnit,
                unitSystem: unitSystem
            )
            context.reset()
        }
        return snapshot
    }
}
