import Foundation

/// Value-type editing buffer so Cancel discards changes.
public struct EventDraft: Equatable {
    public var kind: EventKind
    public var startDate: Date
    public var endDate: Date?
    public var notes: String
    public var leftSeconds: TimeInterval
    public var rightSeconds: TimeInterval
    public var lastSide: BreastSide?
    public var pumpDuration: TimeInterval
    public var amountML: Double
    public var bottleContent: BottleContent
    public var foodName: String
    public var diaperKind: DiaperKind
    public var leftML: Double
    public var rightML: Double
    public var weightKg: Double
    public var lengthCm: Double
    public var headCm: Double
    public var medicineName: String
    public var dose: String

    /// New-entry defaults.
    public init(kind: EventKind, now: Date = .now) {
        self.kind = kind
        self.startDate = now
        self.endDate = nil
        self.notes = ""
        self.leftSeconds = 0
        self.rightSeconds = 0
        self.lastSide = nil
        self.pumpDuration = 0
        self.amountML = 0
        self.bottleContent = .formula
        self.foodName = ""
        self.diaperKind = .wet
        self.leftML = 0
        self.rightML = 0
        self.weightKg = 0
        self.lengthCm = 0
        self.headCm = 0
        self.medicineName = ""
        self.dose = ""

        switch kind {
        case .sleep:
            startDate = now.addingTimeInterval(-3600)
            endDate = now
        case .breastfeed:
            startDate = now.addingTimeInterval(-900)
            endDate = startDate // manual entry, not a running timer
        case .pump:
            startDate = now.addingTimeInterval(-900)
            pumpDuration = 900
            endDate = startDate.addingTimeInterval(900)
        default:
            break
        }
    }

    public init(event: LogEvent) {
        let start = event.startDate ?? .now
        self.init(kind: event.kind, now: start)
        self.startDate = start
        self.endDate = event.endDate
        self.notes = event.notes ?? ""
        self.leftSeconds = event.leftSeconds
        self.rightSeconds = event.rightSeconds
        self.lastSide = event.lastSide
        if event.kind == .pump, let end = event.endDate {
            self.pumpDuration = max(0, end.timeIntervalSince(start))
        } else if event.kind == .pump {
            self.pumpDuration = 0
        }
        self.amountML = event.amountML
        self.bottleContent = event.bottleContent ?? .formula
        self.foodName = event.foodName ?? ""
        self.diaperKind = event.diaperKind ?? .wet
        self.leftML = event.leftML
        self.rightML = event.rightML
        self.weightKg = event.weightKg
        self.lengthCm = event.lengthCm
        self.headCm = event.headCm
        self.medicineName = event.medicineName ?? ""
        self.dose = event.dose ?? ""
    }

    public var isRunning: Bool { kind.isTimerBased && endDate == nil }

    /// nil when savable.
    public var validationMessage: String? {
        if startDate > Date.now.addingTimeInterval(60) {
            return "The start time can't be in the future."
        }
        switch kind {
        case .sleep:
            if let endDate {
                if endDate <= startDate { return "The end time must be after the start time." }
                if endDate.timeIntervalSince(startDate) > 24 * 3600 { return "A sleep can't be longer than 24 hours." }
            }
        case .breastfeed:
            if !isRunning, leftSeconds + rightSeconds <= 0 {
                return "Enter how long you nursed on at least one side."
            }
        case .bottle:
            if amountML <= 0 { return "Enter the amount." }
        case .pump:
            if leftML + rightML <= 0 { return "Enter the amount pumped." }
        case .growth:
            if weightKg <= 0, lengthCm <= 0, headCm <= 0 { return "Enter at least one measurement." }
        case .medicine:
            if medicineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the medicine name." }
        case .solids, .diaper:
            break
        }
        return nil
    }

    /// Writes the fields relevant to this kind into `event`.
    public func apply(to event: LogEvent, now: Date = .now) {
        event.kind = kind
        event.startDate = startDate
        event.notes = Self.trimmedOrNil(notes)
        event.modifiedAt = now

        switch kind {
        case .sleep:
            event.endDate = endDate
        case .breastfeed:
            guard !isRunning else { return } // running timer: only start + notes
            event.leftSeconds = leftSeconds
            event.rightSeconds = rightSeconds
            event.lastSide = lastSide
            event.activeSide = nil
            event.activeSideStartedAt = nil
            event.endDate = startDate.addingTimeInterval(leftSeconds + rightSeconds)
        case .bottle:
            event.endDate = nil
            event.amountML = amountML
            event.bottleContent = bottleContent
        case .solids:
            event.endDate = nil
            event.foodName = Self.trimmedOrNil(foodName)
        case .diaper:
            event.endDate = nil
            event.diaperKind = diaperKind
        case .pump:
            event.leftML = leftML
            event.rightML = rightML
            event.endDate = startDate.addingTimeInterval(pumpDuration)
        case .growth:
            event.endDate = nil
            event.weightKg = weightKg
            event.lengthCm = lengthCm
            event.headCm = headCm
        case .medicine:
            event.endDate = nil
            event.medicineName = Self.trimmedOrNil(medicineName)
            event.dose = Self.trimmedOrNil(dose)
        }
    }

    private static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
