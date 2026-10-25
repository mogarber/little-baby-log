import Foundation

/// One sleep, as the predictors see it. `end == nil` means the baby is asleep right now.
public struct SleepSession: Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }
}

/// One breastfeed or bottle, as the feed predictor sees it. Only the start matters.
public struct FeedSample: Equatable, Sendable {
    public var start: Date
    public var kind: EventKind

    public init(start: Date, kind: EventKind) {
        self.start = start
        self.kind = kind
    }
}

/// How much of a prediction comes from this baby's own logs. Shown to the parent as a one-line caption.
public enum PredictionBasis: Equatable, Sendable {
    /// Not enough history yet (fewer than 3 usable samples): age norms only.
    case typicalForAge
    /// Age norms mixed with this baby's last `days` days (3 to 9 samples).
    case blended(days: Int)
    /// 10 or more samples, so the baby's own pattern dominates (the age norms only bound the result).
    case personal(days: Int)

    /// The number of days of logs behind the estimate, nil for `typicalForAge`.
    public var days: Int? {
        switch self {
        case .typicalForAge: return nil
        case .blended(let days), .personal(let days): return days
        }
    }
}

public struct SleepPrediction: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case nap, bedtime
    }

    public var kind: Kind
    /// When sleep is likely to start, e.g. 2:10 to 2:40 PM.
    public var window: DateInterval
    public var basis: PredictionBasis
    /// The wake-up the window was counted from. nil when there was none to anchor on (nothing logged, or the
    /// last wake-up is too old to trust): the window then counts from "now" and `basis` is `typicalForAge`.
    public var lastWake: Date?

    public init(kind: Kind, window: DateInterval, basis: PredictionBasis, lastWake: Date? = nil) {
        self.kind = kind
        self.window = window
        self.basis = basis
        self.lastWake = lastWake
    }

    /// The middle of the window.
    public var centre: Date { window.start.addingTimeInterval(window.duration / 2) }
}

public struct FeedPrediction: Equatable, Sendable {
    /// When the next feed is likely to start, e.g. 4:15 to 4:45 PM.
    public var around: DateInterval
    public var basis: PredictionBasis

    public init(around: DateInterval, basis: PredictionBasis) {
        self.around = around
        self.basis = basis
    }

    /// The middle of the window.
    public var centre: Date { around.start.addingTimeInterval(around.duration / 2) }
}
