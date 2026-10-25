import Foundation

// Reminder settings: plain Codable values, stored per device (never synced) and keyed by baby uuid.
// Decoding is forgiving (every field has a default) so a later build can add a reminder type, as the nap-window
// reminder did, without losing what an older build saved.

/// What the "feed every N hours" interval is measured from.
public enum FeedIntervalAnchor: String, Codable, CaseIterable, Identifiable, Sendable {
    /// From when the last feed began (the usual "every 3 hours" schedule).
    case start
    /// From when the last feed finished.
    case end

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .start: return "Start of last feed"
        case .end: return "End of last feed"
        }
    }
}

/// A daily window in which the feed reminder stays quiet. A reminder that would fall inside it waits for the
/// window to end. May wrap past midnight (10 PM to 7 AM). Equal start and end is an empty window.
public struct QuietHours: Codable, Equatable, Sendable {
    public static let defaultStartMinutes = 22 * 60
    public static let defaultEndMinutes = 7 * 60

    /// Minutes since midnight, 0..<1440.
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int = QuietHours.defaultStartMinutes, endMinutes: Int = QuietHours.defaultEndMinutes) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public var schedule: NightSchedule { NightSchedule(startMinutes: startMinutes, endMinutes: endMinutes) }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        schedule.isNightActive(at: date, calendar: calendar)
    }

    /// If `date` is inside the window, the moment the window ends (never before `date`); otherwise `date`.
    public func firstAllowedMoment(atOrAfter date: Date, calendar: Calendar = .current) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        // While the window is active, its next transition is its end.
        return schedule.nextTransition(after: date, calendar: calendar) ?? date
    }
}

/// "Feed every N hours" for one baby.
public struct FeedIntervalReminder: Codable, Equatable, Sendable {
    /// 1h to 6h in 15-minute steps. (Planning accepts any length from 1 minute, which debug builds use.)
    public static let allowedMinutes: [Int] = Array(stride(from: 60, through: 360, by: 15))
    public static let defaultMinutes = 180
    public static let maxMinutes = 24 * 60

    public var isEnabled: Bool
    public var intervalMinutes: Int
    public var anchor: FeedIntervalAnchor
    /// nil = no quiet hours.
    public var quietHours: QuietHours?

    public init(
        isEnabled: Bool = false,
        intervalMinutes: Int = FeedIntervalReminder.defaultMinutes,
        anchor: FeedIntervalAnchor = .start,
        quietHours: QuietHours? = nil
    ) {
        self.isEnabled = isEnabled
        self.intervalMinutes = intervalMinutes
        self.anchor = anchor
        self.quietHours = quietHours
    }

    /// The interval, kept to a sane range.
    public var interval: TimeInterval {
        TimeInterval(min(max(intervalMinutes, 1), Self.maxMinutes) * 60)
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, intervalMinutes, anchor, quietHours }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? Self.defaultMinutes
        anchor = (try? c.decodeIfPresent(FeedIntervalAnchor.self, forKey: .anchor)) ?? .start
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours)
    }
}

public enum DailyReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case feed, medicine, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feed: return "Feed"
        case .medicine: return "Medicine"
        case .custom: return "Custom"
        }
    }

    public var symbolName: String {
        switch self {
        case .feed: return "heart.fill"
        case .medicine: return "pills.fill"
        case .custom: return "bell.fill"
        }
    }
}

/// A reminder that repeats at the same time every day.
public struct DailyReminder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Minutes since midnight, 0..<1440.
    public var minutesOfDay: Int
    public var label: String
    public var kind: DailyReminderKind
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        minutesOfDay: Int = 9 * 60,
        label: String = "",
        kind: DailyReminderKind = .medicine,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.minutesOfDay = minutesOfDay
        self.label = label
        self.kind = kind
        self.isEnabled = isEnabled
    }

    public var hour: Int { min(max(minutesOfDay, 0), 1439) / 60 }
    public var minute: Int { min(max(minutesOfDay, 0), 1439) % 60 }

    /// What the notification (and the list row) is called: the label, or a generic name for the kind.
    public var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch kind {
        case .feed: return "Feeding time"
        case .medicine: return "Medicine time"
        case .custom: return "Reminder"
        }
    }

    private enum CodingKeys: String, CodingKey { case id, minutesOfDay, label, kind, isEnabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        minutesOfDay = try c.decodeIfPresent(Int.self, forKey: .minutesOfDay) ?? 9 * 60
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = (try? c.decodeIfPresent(DailyReminderKind.self, forKey: .kind)) ?? .custom
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// "Nap window opens in 10 min" for one baby: a heads-up shortly before the predicted nap window
/// (`SleepPredictor`). Off by default.
public struct NapWindowReminder: Codable, Equatable, Sendable {
    /// How long before the window opens the reminder fires, in the picker.
    public static let allowedLeadMinutes: [Int] = [5, 10, 15, 20]
    public static let defaultLeadMinutes = 10
    public static let maxLeadMinutes = 60

    public var isEnabled: Bool
    public var leadMinutes: Int
    /// Also remind before a predicted bedtime window (the default is naps only).
    public var includeBedtime: Bool

    public init(
        isEnabled: Bool = false,
        leadMinutes: Int = NapWindowReminder.defaultLeadMinutes,
        includeBedtime: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.leadMinutes = leadMinutes
        self.includeBedtime = includeBedtime
    }

    /// The lead time, kept to a sane range. (Planning accepts any length from 1 minute, which debug builds use.)
    public var lead: TimeInterval {
        TimeInterval(min(max(leadMinutes, 1), Self.maxLeadMinutes) * 60)
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, leadMinutes, includeBedtime }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        leadMinutes = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? Self.defaultLeadMinutes
        includeBedtime = try c.decodeIfPresent(Bool.self, forKey: .includeBedtime) ?? false
    }
}

/// Everything one baby has set up on this device.
public struct BabyReminderSettings: Codable, Equatable, Sendable {
    public var feedEvery: FeedIntervalReminder
    public var napWindow: NapWindowReminder
    public var daily: [DailyReminder]

    public init(
        feedEvery: FeedIntervalReminder = FeedIntervalReminder(),
        napWindow: NapWindowReminder = NapWindowReminder(),
        daily: [DailyReminder] = []
    ) {
        self.feedEvery = feedEvery
        self.napWindow = napWindow
        self.daily = daily
    }

    /// True when at least one reminder would schedule something.
    public var hasAnythingEnabled: Bool {
        feedEvery.isEnabled || napWindow.isEnabled || daily.contains(where: \.isEnabled)
    }

    private enum CodingKeys: String, CodingKey { case feedEvery, napWindow, daily }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedEvery = try c.decodeIfPresent(FeedIntervalReminder.self, forKey: .feedEvery) ?? FeedIntervalReminder()
        napWindow = (try? c.decodeIfPresent(NapWindowReminder.self, forKey: .napWindow)) ?? NapWindowReminder()
        daily = try c.decodeIfPresent([DailyReminder].self, forKey: .daily) ?? []
    }
}

/// Per-device storage for `BabyReminderSettings`: one JSON blob in `UserDefaults`, keyed by baby uuid string.
/// Never goes to iCloud, so each caregiver chooses their own reminders.
public struct ReminderSettingsStore {
    public static let defaultsKey = "reminderSettings"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = ReminderSettingsStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func all() -> [UUID: BabyReminderSettings] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: BabyReminderSettings].self, from: data) else { return [:] }
        var result: [UUID: BabyReminderSettings] = [:]
        for (string, settings) in decoded {
            if let id = UUID(uuidString: string) { result[id] = settings }
        }
        return result
    }

    public func settings(for babyID: UUID) -> BabyReminderSettings {
        all()[babyID] ?? BabyReminderSettings()
    }

    public func save(_ settings: BabyReminderSettings, for babyID: UUID) {
        var map = all()
        map[babyID] = settings
        write(map)
    }

    public func remove(babyID: UUID) {
        var map = all()
        map[babyID] = nil
        write(map)
    }

    /// True when any baby has a reminder switched on.
    public var hasAnythingEnabled: Bool {
        all().values.contains(where: \.hasAnythingEnabled)
    }

    private func write(_ map: [UUID: BabyReminderSettings]) {
        let encodable = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: key)
        }
    }
}
