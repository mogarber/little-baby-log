import CoreData
import BabyLogKit

extension PersistenceController {
    /// The app-wide store. CloudKit-backed when the build has a container identifier, otherwise local only.
    static let shared = PersistenceController(cloudKitContainerIdentifier: AppConfig.cloudKitContainerIdentifier)

    /// In-memory store filled with sample data, for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleData.populate(controller.viewContext)
        return controller
    }()
}

extension Baby {
    /// All babies, oldest first. Used with `@FetchRequest(fetchRequest:)`.
    static func lblAllByCreation() -> NSFetchRequest<Baby> {
        let request: NSFetchRequest<Baby> = Baby.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }
}
