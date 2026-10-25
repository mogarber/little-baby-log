import CoreData

@objc(LogEvent)
public final class LogEvent: NSManagedObject {
    @NSManaged public var uuid: UUID?
    @NSManaged public var kindRaw: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // Breastfeeding
    @NSManaged public var leftSeconds: Double
    @NSManaged public var rightSeconds: Double
    @NSManaged public var activeSideRaw: String?
    @NSManaged public var activeSideStartedAt: Date?
    @NSManaged public var lastSideRaw: String?

    // Bottle
    @NSManaged public var amountML: Double
    @NSManaged public var bottleContentRaw: String?

    // Solids
    @NSManaged public var foodName: String?

    // Diaper
    @NSManaged public var diaperKindRaw: String?

    // Pump
    @NSManaged public var leftML: Double
    @NSManaged public var rightML: Double

    // Growth (0 = not measured)
    @NSManaged public var weightKg: Double
    @NSManaged public var lengthCm: Double
    @NSManaged public var headCm: Double

    // Medicine
    @NSManaged public var medicineName: String?
    @NSManaged public var dose: String?

    @NSManaged public var baby: Baby?
}

extension LogEvent {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LogEvent> {
        NSFetchRequest<LogEvent>(entityName: "LogEvent")
    }

    /// Inserts into the SAME persistent store as `baby` (required for the CloudKit shared store).
    public static func create(kind: EventKind, for baby: Baby, start: Date = .now, in context: NSManagedObjectContext) -> LogEvent {
        let model = context.persistentStoreCoordinator?.managedObjectModel ?? BabyLogModel.model
        let entity = model.entitiesByName["LogEvent"] ?? BabyLogModel.model.entitiesByName["LogEvent"]!
        let event = LogEvent(entity: entity, insertInto: context)
        if let store = baby.objectID.persistentStore {
            context.assign(event, to: store)
        }
        let now = Date()
        event.uuid = UUID()
        event.kindRaw = kind.rawValue
        event.startDate = start
        event.createdAt = now
        event.modifiedAt = now
        event.baby = baby
        return event
    }

    public var kind: EventKind {
        get { kindRaw.flatMap(EventKind.init(rawValue:)) ?? .sleep }
        set { kindRaw = newValue.rawValue }
    }

    public var bottleContent: BottleContent? {
        get { bottleContentRaw.flatMap(BottleContent.init(rawValue:)) }
        set { bottleContentRaw = newValue?.rawValue }
    }

    public var diaperKind: DiaperKind? {
        get { diaperKindRaw.flatMap(DiaperKind.init(rawValue:)) }
        set { diaperKindRaw = newValue?.rawValue }
    }

    public var activeSide: BreastSide? {
        get { activeSideRaw.flatMap(BreastSide.init(rawValue:)) }
        set { activeSideRaw = newValue?.rawValue }
    }

    public var lastSide: BreastSide? {
        get { lastSideRaw.flatMap(BreastSide.init(rawValue:)) }
        set { lastSideRaw = newValue?.rawValue }
    }

    public var isRunning: Bool { kind.isTimerBased && endDate == nil }

    /// Breastfeed: sum of both sides. Sleep/pump: (end ?? now) - start. Instant kinds: 0.
    public func duration(at now: Date = .now) -> TimeInterval {
        switch kind {
        case .breastfeed:
            return totalBreastSeconds(at: now)
        case .sleep, .pump:
            guard let start = startDate else { return 0 }
            return max(0, (endDate ?? now).timeIntervalSince(start))
        default:
            return 0
        }
    }
}

// MARK: - Fetch requests

extension LogEvent {
    private static let timerKindRaws = [EventKind.sleep.rawValue, EventKind.breastfeed.rawValue]

    private static func sortedRequest(ascending: Bool = false) -> NSFetchRequest<LogEvent> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: ascending)]
        return request
    }

    public static func requestAll(baby: Baby, kinds: [EventKind]? = nil, ascending: Bool = false) -> NSFetchRequest<LogEvent> {
        let request = sortedRequest(ascending: ascending)
        var predicates: [NSPredicate] = [NSPredicate(format: "baby == %@", baby)]
        if let kinds {
            predicates.append(NSPredicate(format: "kindRaw IN %@", kinds.map(\.rawValue)))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return request
    }

    /// Events touching [date, ∞): startDate >= date OR endDate >= date OR running timer.
    public static func requestOverlapping(baby: Baby, from date: Date) -> NSFetchRequest<LogEvent> {
        let request = sortedRequest()
        let overlap = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "startDate >= %@", date as NSDate),
            NSPredicate(format: "endDate >= %@", date as NSDate),
            runningPredicate,
        ])
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "baby == %@", baby), overlap,
        ])
        return request
    }

    public static func requestRunning(baby: Baby) -> NSFetchRequest<LogEvent> {
        let request = sortedRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "baby == %@", baby), runningPredicate,
        ])
        return request
    }

    /// fetchLimit 1. `finishedOnly` → endDate != nil.
    public static func requestLatest(baby: Baby, kinds: [EventKind], finishedOnly: Bool = false) -> NSFetchRequest<LogEvent> {
        let request = sortedRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "baby == %@", baby),
            NSPredicate(format: "kindRaw IN %@", kinds.map(\.rawValue)),
        ]
        if finishedOnly {
            predicates.append(NSPredicate(format: "endDate != nil"))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return request
    }

    /// Instant kinds also have a nil endDate, so the kind must be restricted to timer kinds.
    private static var runningPredicate: NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "kindRaw IN %@", timerKindRaws),
            NSPredicate(format: "endDate == nil"),
        ])
    }
}
