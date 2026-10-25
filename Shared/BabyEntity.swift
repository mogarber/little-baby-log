import AppIntents
import Foundation
import BabyLogKit

/// A baby as the widget configuration sees it. Read from the snapshot file, never from Core Data.
struct BabyEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Baby")
    static var defaultQuery = BabyEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    var uuid: UUID? { UUID(uuidString: id) }
}

struct BabyEntityQuery: EntityQuery {
    private func babies() -> [BabyEntity] {
        guard let url = AppGroup.snapshotURL, let snapshot = WidgetSnapshot.read(from: url) else { return [] }
        return snapshot.babies.map { BabyEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [BabyEntity] {
        babies().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BabyEntity] {
        babies()
    }

    /// The app's current baby.
    func defaultResult() async -> BabyEntity? {
        guard let url = AppGroup.snapshotURL,
              let snapshot = WidgetSnapshot.read(from: url),
              let baby = snapshot.baby(id: nil) else { return nil }
        return BabyEntity(id: baby.id.uuidString, name: baby.name)
    }
}

/// Widget configuration: which baby to show. Leave it empty to follow the baby selected in the app.
struct SelectBabyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Baby"
    static var description = IntentDescription("Pick which baby this widget shows. Leave it empty to follow the baby selected in the app.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    init() {}

    init(baby: BabyEntity?) {
        self.baby = baby
    }
}
