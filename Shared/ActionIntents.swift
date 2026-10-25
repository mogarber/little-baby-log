import AppIntents
import Foundation
import BabyLogKit

// Buttons in widgets and Live Activities run these intents. They conform to `LiveActivityIntent`, so iOS
// runs `perform()` in the app's process (launching it in the background if needed) rather than in the
// widget extension. That keeps every write inside the app's one Core Data / CloudKit container, so a
// caregiver on another phone sees a widget-started timer promptly.
//
// The types compile into both the app and the extension (the extension needs them to build buttons);
// the bodies that touch Core Data exist only in the app (`LBL_APP`, see `App/Support/AppIntentActions.swift`).

enum BreastSideAppEnum: String, AppEnum {
    case left, right

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Breast Side")
    static var caseDisplayRepresentations: [BreastSideAppEnum: DisplayRepresentation] = [
        .left: "Left",
        .right: "Right",
    ]

    init(_ side: BreastSide) {
        self = side == .left ? .left : .right
    }

    var side: BreastSide { self == .left ? .left : .right }
}

enum DiaperKindAppEnum: String, AppEnum {
    case wet, dirty, mixed, dry

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Diaper")
    static var caseDisplayRepresentations: [DiaperKindAppEnum: DisplayRepresentation] = [
        .wet: "Wet",
        .dirty: "Dirty",
        .mixed: "Wet + dirty",
        .dry: "Dry",
    ]

    init(_ kind: DiaperKind) {
        self = DiaperKindAppEnum(rawValue: kind.rawValue) ?? .wet
    }

    var kind: DiaperKind { DiaperKind(rawValue: rawValue) ?? .wet }
}

/// Start nursing on `side` (nil: the suggested next side), or, when a timer is already running,
/// switch to that side / pause it (nil: pause or resume).
struct NursingSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nurse"
    static var description = IntentDescription("Starts, switches, or pauses a nursing side.")
    static var isDiscoverable = false

    @Parameter(title: "Baby ID")
    var babyID: String

    @Parameter(title: "Side")
    var side: BreastSideAppEnum?

    init() {}

    init(babyID: UUID, side: BreastSide?) {
        self.babyID = babyID.uuidString
        self.side = side.map(BreastSideAppEnum.init)
    }

    func perform() async throws -> some IntentResult {
        #if LBL_APP
        await AppIntentActions.nursing(babyID: babyID, side: side?.side)
        #endif
        return .result()
    }
}

/// Ends the running nursing session (deleting it if nothing was tracked).
struct FinishNursingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Nursing"
    static var description = IntentDescription("Ends the running nursing timer.")
    static var isDiscoverable = false

    @Parameter(title: "Baby ID")
    var babyID: String

    init() {}

    init(babyID: UUID) {
        self.babyID = babyID.uuidString
    }

    func perform() async throws -> some IntentResult {
        #if LBL_APP
        await AppIntentActions.finishNursing(babyID: babyID)
        #endif
        return .result()
    }
}

/// Starts a sleep timer, or wakes the baby up when one is running.
struct ToggleSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Sleep or Wake Up"
    static var description = IntentDescription("Starts or ends the sleep timer.")
    static var isDiscoverable = false

    @Parameter(title: "Baby ID")
    var babyID: String

    init() {}

    init(babyID: UUID) {
        self.babyID = babyID.uuidString
    }

    func perform() async throws -> some IntentResult {
        #if LBL_APP
        await AppIntentActions.toggleSleep(babyID: babyID)
        #endif
        return .result()
    }
}

/// Logs a diaper change right now.
struct LogDiaperIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Diaper"
    static var description = IntentDescription("Logs a diaper change.")
    static var isDiscoverable = false

    @Parameter(title: "Baby ID")
    var babyID: String

    @Parameter(title: "Kind")
    var kind: DiaperKindAppEnum

    init() {
        kind = .wet
    }

    init(babyID: UUID, kind: DiaperKind) {
        self.babyID = babyID.uuidString
        self.kind = DiaperKindAppEnum(kind)
    }

    func perform() async throws -> some IntentResult {
        #if LBL_APP
        await AppIntentActions.logDiaper(babyID: babyID, kind: kind.kind)
        #endif
        return .result()
    }
}
