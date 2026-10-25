import Foundation

public enum EventKind: String, CaseIterable, Identifiable, Sendable {
    case sleep, breastfeed, bottle, solids, diaper, pump, growth, medicine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .breastfeed: return "Nursing"
        case .bottle: return "Bottle"
        case .solids: return "Solids"
        case .diaper: return "Diaper"
        case .pump: return "Pump"
        case .growth: return "Growth"
        case .medicine: return "Medicine"
        }
    }

    public var symbolName: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .breastfeed: return "heart.fill"
        case .bottle: return "waterbottle.fill"
        case .solids: return "fork.knife"
        case .diaper: return "drop.fill"
        case .pump: return "testtube.2"
        case .growth: return "ruler.fill"
        case .medicine: return "pills.fill"
        }
    }

    /// Kinds that have an end date (sleep, breastfeed, pump).
    public var hasDuration: Bool {
        switch self {
        case .sleep, .breastfeed, .pump: return true
        default: return false
        }
    }

    /// Kinds that run as a live timer while `endDate == nil` (sleep, breastfeed).
    public var isTimerBased: Bool {
        switch self {
        case .sleep, .breastfeed: return true
        default: return false
        }
    }

    public var isFeed: Bool {
        switch self {
        case .breastfeed, .bottle: return true
        default: return false
        }
    }
}

public enum BreastSide: String, CaseIterable, Identifiable, Sendable {
    case left, right

    public var id: String { rawValue }
    public var title: String { self == .left ? "Left" : "Right" }
    public var shortLabel: String { self == .left ? "L" : "R" }
    public var other: BreastSide { self == .left ? .right : .left }
}

public enum BottleContent: String, CaseIterable, Identifiable, Sendable {
    case formula, breastMilk, other

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .formula: return "Formula"
        case .breastMilk: return "Breast milk"
        case .other: return "Other"
        }
    }
}

public enum DiaperKind: String, CaseIterable, Identifiable, Sendable {
    case wet, dirty, mixed, dry

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .mixed: return "Wet + dirty"
        case .dry: return "Dry"
        }
    }
    public var symbolName: String {
        switch self {
        case .wet: return "drop.fill"
        case .dirty: return "allergens.fill"
        case .mixed: return "drop.halffull"
        case .dry: return "sun.max.fill"
        }
    }
    public var isWet: Bool { self == .wet || self == .mixed }
    public var isDirty: Bool { self == .dirty || self == .mixed }
}
