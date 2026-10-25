import Foundation

/// What the person picked under Settings > Appearance.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    /// Always the dim, warm, true-black Night theme.
    case night
    /// Night between two times of day, otherwise the system's Light or Dark.
    case nightSchedule

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .night: return "Night"
        case .nightSchedule: return "Night on a schedule"
        }
    }

    /// True when Night can ever be shown: the setting for dimming the screen only makes sense then.
    public var canShowNight: Bool { self == .night || self == .nightSchedule }

    /// How the app should look at `date`.
    public func resolved(schedule: NightSchedule, at date: Date, calendar: Calendar = .current) -> ResolvedAppearance {
        switch self {
        case .system: return .system
        case .light: return .light
        case .dark: return .dark
        case .night: return .night
        case .nightSchedule: return schedule.isNightActive(at: date, calendar: calendar) ? .night : .system
        }
    }

    /// When `resolved` may next change by itself: only a schedule has such moments.
    public func nextTransition(schedule: NightSchedule, after date: Date, calendar: Calendar = .current) -> Date? {
        self == .nightSchedule ? schedule.nextTransition(after: date, calendar: calendar) : nil
    }
}

/// The look the app actually wears right now.
public enum ResolvedAppearance: Equatable, Sendable {
    case system, light, dark, night

    public var isNight: Bool { self == .night }
}

/// A daily window, in minutes since midnight, that may wrap past midnight (7:00 PM to 7:00 AM).
///
/// Night is active from `startMinutes` (inclusive) up to `endMinutes` (exclusive). When both are equal the
/// window is empty and Night is never active.
public struct NightSchedule: Equatable, Sendable {
    public static let minutesPerDay = 24 * 60
    public static let defaultStartMinutes = 19 * 60
    public static let defaultEndMinutes = 7 * 60
    public static let `default` = NightSchedule(startMinutes: defaultStartMinutes, endMinutes: defaultEndMinutes)

    public let startMinutes: Int
    public let endMinutes: Int

    /// Values outside 0..<1440 are folded into a day.
    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = Self.normalized(startMinutes)
        self.endMinutes = Self.normalized(endMinutes)
    }

    private static func normalized(_ minutes: Int) -> Int {
        ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// False for an empty window (start equals end).
    public var isEmpty: Bool { startMinutes == endMinutes }

    /// True when the window runs past midnight.
    public var wrapsMidnight: Bool { startMinutes > endMinutes }

    public func isNightActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard !isEmpty else { return false }
        let now = Self.minutesOfDay(date, calendar: calendar)
        if wrapsMidnight {
            return now >= startMinutes || now < endMinutes
        }
        return now >= startMinutes && now < endMinutes
    }

    /// The next moment, strictly after `date`, at which `isNightActive` flips. Nil for an empty window.
    /// Uses the calendar's own day arithmetic, so daylight-saving changes land on the right wall-clock time.
    public func nextTransition(after date: Date, calendar: Calendar = .current) -> Date? {
        guard !isEmpty else { return nil }
        let candidates = [startMinutes, endMinutes].compactMap { minutes -> Date? in
            var components = DateComponents()
            components.hour = minutes / 60
            components.minute = minutes % 60
            components.second = 0
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
        return candidates.min()
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
