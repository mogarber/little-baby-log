import CoreData

/// The Core Data model, built in code. A single shared instance is used everywhere:
/// multiple models claiming the same managed object classes cause warnings and bugs.
public enum BabyLogModel {
    public static let model: NSManagedObjectModel = build()

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        default defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = true
        if let defaultValue { attr.defaultValue = defaultValue }
        return attr
    }

    private static func build() -> NSManagedObjectModel {
        let babyEntity = NSEntityDescription()
        babyEntity.name = "Baby"
        babyEntity.managedObjectClassName = NSStringFromClass(Baby.self)

        let eventEntity = NSEntityDescription()
        eventEntity.name = "LogEvent"
        eventEntity.managedObjectClassName = NSStringFromClass(LogEvent.self)

        babyEntity.properties = [
            attribute("uuid", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("birthDate", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        eventEntity.properties = [
            attribute("uuid", .UUIDAttributeType),
            attribute("kindRaw", .stringAttributeType),
            attribute("startDate", .dateAttributeType),
            attribute("endDate", .dateAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("modifiedAt", .dateAttributeType),
            attribute("leftSeconds", .doubleAttributeType, default: 0.0),
            attribute("rightSeconds", .doubleAttributeType, default: 0.0),
            attribute("activeSideRaw", .stringAttributeType),
            attribute("activeSideStartedAt", .dateAttributeType),
            attribute("lastSideRaw", .stringAttributeType),
            attribute("amountML", .doubleAttributeType, default: 0.0),
            attribute("bottleContentRaw", .stringAttributeType),
            attribute("foodName", .stringAttributeType),
            attribute("diaperKindRaw", .stringAttributeType),
            attribute("leftML", .doubleAttributeType, default: 0.0),
            attribute("rightML", .doubleAttributeType, default: 0.0),
            attribute("weightKg", .doubleAttributeType, default: 0.0),
            attribute("lengthCm", .doubleAttributeType, default: 0.0),
            attribute("headCm", .doubleAttributeType, default: 0.0),
            attribute("medicineName", .stringAttributeType),
            attribute("dose", .stringAttributeType),
        ]

        let events = NSRelationshipDescription()
        events.name = "events"
        events.destinationEntity = eventEntity
        events.minCount = 0
        events.maxCount = 0 // to-many
        events.deleteRule = .cascadeDeleteRule
        events.isOptional = true

        let baby = NSRelationshipDescription()
        baby.name = "baby"
        baby.destinationEntity = babyEntity
        baby.minCount = 0
        baby.maxCount = 1
        baby.deleteRule = .nullifyDeleteRule
        baby.isOptional = true

        events.inverseRelationship = baby
        baby.inverseRelationship = events

        babyEntity.properties.append(events)
        eventEntity.properties.append(baby)

        let model = NSManagedObjectModel()
        model.entities = [babyEntity, eventEntity]
        return model
    }
}
