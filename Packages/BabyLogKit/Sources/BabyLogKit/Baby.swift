import CoreData

@objc(Baby)
public final class Baby: NSManagedObject {
    @NSManaged public var uuid: UUID?
    @NSManaged public var name: String?
    @NSManaged public var birthDate: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var events: NSSet?
}

extension Baby {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Baby> {
        NSFetchRequest<Baby>(entityName: "Baby")
    }

    public static func create(name: String, birthDate: Date, in context: NSManagedObjectContext) -> Baby {
        let baby = Baby(entity: entity(in: context), insertInto: context)
        baby.uuid = UUID()
        baby.name = name
        baby.birthDate = birthDate
        baby.createdAt = Date()
        return baby
    }

    private static func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        let model = context.persistentStoreCoordinator?.managedObjectModel ?? BabyLogModel.model
        return model.entitiesByName["Baby"] ?? BabyLogModel.model.entitiesByName["Baby"]!
    }

    /// The baby's name, or "Baby" when it is empty.
    public var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Baby" : trimmed
    }
}
