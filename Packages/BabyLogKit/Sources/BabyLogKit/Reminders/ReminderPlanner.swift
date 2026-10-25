import Foundation

// Pure scheduling logic for local reminders. No UserNotifications, no Core Data, no clock: the app's
// `ReminderScheduler` gathers the inputs (settings, each baby's latest feed, now), asks for the plan, and makes
// the notification center match it.
//
// Adding another reminder type: add its settings to `BabyReminderSettings`, whatever it needs to `ReminderBaby`,
// a `requests(...)` helper like `feedIntervalRequest` below, and one line in
// `ReminderPlanner.requests(for:now:calendar:locale:)`. Give it an identifier in `ReminderIdentifier`. The
// scheduler needs no change: it replaces by identifier and removes whatever is no longer planned. (The nap-window
// reminder was added this way.)

/// Fixed notification identifiers. A baby has at most one pending request per identifier, so scheduling the same
/// identifier again moves a reminder instead of adding a second one.
public enum ReminderIdentifier {
    public static let prefix = "lbl.reminder."
    public static let snoozePrefix = prefix + "snooze."

    public static func feedInterval(babyID: UUID) -> String { prefix + "feed." + babyID.uuidString }
    public static func napWindow(babyID: UUID) -> String { prefix + "nap." + babyID.uuidString }
    public static func daily(babyID: UUID, reminderID: UUID) -> String {
        prefix + "daily." + babyID.uuidString + "." + reminderID.uuidString
    }
    public static func snooze(babyID: UUID) -> String { snoozePrefix + babyID.uuidString }
}

/// Category and action identifiers for feed reminders (registered in the app; handled in its notification delegate).
public enum ReminderCategory {
    public static let feed = "lbl.category.feed"
    public static let startLeft = "lbl.action.startLeft"
    public static let startRight = "lbl.action.startRight"
    public static let snooze = "lbl.action.snooze15"
    public static let snoozeMinutes = 15
}

public enum ReminderUserInfoKey {
    public static let babyID = "babyID"
    /// JSON of `FeedReminderInfo`: present on reminders that are about a specific feed.
    public static let feedInfo = "feedInfo"
}

public enum ReminderUrgency: Equatable, Sendable {
    /// Normal delivery.
    case active
    /// Gets through Focus and Sleep mode (needs the time-sensitive entitlement).
    case timeSensitive
}

public enum ReminderTrigger: Equatable, Sendable {
    /// Once, at this moment (an absolute time, so a daylight-saving change or a time-zone trip can't shift it).
    case date(Date)
    /// Every day at this wall-clock time (the system follows daylight saving and time zones).
    case daily(hour: Int, minute: Int)
}

/// One notification to have pending, as plain values.
public struct ReminderRequest: Equatable, Sendable {
    public var identifier: String
    public var babyID: UUID
    public var title: String
    public var body: String
    public var categoryIdentifier: String?
    public var urgency: ReminderUrgency
    public var trigger: ReminderTrigger
    public var userInfo: [String: String]

    public init(
        identifier: String,
        babyID: UUID,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        urgency: ReminderUrgency,
        trigger: ReminderTrigger,
        userInfo: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.babyID = babyID
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.urgency = urgency
        self.trigger = trigger
        self.userInfo = userInfo
    }

    /// For a one-off request, when it fires.
    public var fireDate: Date? {
        if case .date(let date) = trigger { return date }
        return nil
    }
}

/// A baby's most recent feed (nursing or bottle; solids don't count).
public struct LastFeed: Equatable, Sendable {
    public var start: Date
    /// nil while a nursing timer is running.
    public var end: Date?
    public var kind: EventKind
    public var lastSide: BreastSide?

    public init(start: Date, end: Date?, kind: EventKind, lastSide: BreastSide? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
        self.lastSide = lastSide
    }
}

/// Everything the planner needs to know about one baby.
public struct ReminderBaby: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: BabyReminderSettings
    public var lastFeed: LastFeed?
    /// What the nap-window reminder needs to ask `SleepPredictor` for the next sleep. The adapter only fills these
    /// in when that reminder is on; a baby without a birth date has no prediction.
    public var birthDate: Date?
    public var sleeps: [SleepSession]

    public init(
        id: UUID,
        name: String,
        settings: BabyReminderSettings,
        lastFeed: LastFeed?,
        birthDate: Date? = nil,
        sleeps: [SleepSession] = []
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.lastFeed = lastFeed
        self.birthDate = birthDate
        self.sleeps = sleeps
    }
}

/// What a feed reminder remembers about the feed it is for, so a snooze can reword itself and a newer feed can
/// retire it.
public struct FeedReminderInfo: Codable, Equatable, Sendable {
    public var babyName: String
    /// `timeIntervalSince1970` of the feed's start.
    public var feedStart: Double
    /// `timeIntervalSince1970` of the moment the interval is measured from.
    public var since: Double
    public var kindRaw: String
    public var lastSideRaw: String?

    public var kind: EventKind { EventKind(rawValue: kindRaw) ?? .breastfeed }
    public var lastSide: BreastSide? { lastSideRaw.flatMap(BreastSide.init(rawValue:)) }

    public init(babyName: String, feedStart: Date, since: Date, kind: EventKind, lastSide: BreastSide?) {
        self.babyName = babyName
        self.feedStart = feedStart.timeIntervalSince1970
        self.since = since.timeIntervalSince1970
        self.kindRaw = kind.rawValue
        self.lastSideRaw = lastSide?.rawValue
    }

    public var userInfoValue: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public init?(userInfo: [String: String]) {
        guard let json = userInfo[ReminderUserInfoKey.feedInfo], let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(FeedReminderInfo.self, from: data) else { return nil }
        self = decoded
    }
}

public enum ReminderPlanner {
    // MARK: Plan

    /// The notifications that should be pending, for all babies. Sorted by baby, then feed-interval, nap window,
    /// and the daily ones. `locale` only words the clock times in the nap reminder's text.
    public static func plan(
        babies: [ReminderBaby],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> [ReminderRequest] {
        babies.flatMap { requests(for: $0, now: now, calendar: calendar, locale: locale) }
    }

    public static func requests(
        for baby: ReminderBaby,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> [ReminderRequest] {
        var result: [ReminderRequest] = []
        if let request = feedIntervalRequest(for: baby, now: now, calendar: calendar) { result.append(request) }
        if let request = napWindowRequest(for: baby, now: now, calendar: calendar, locale: locale) { result.append(request) }
        result += dailyRequests(for: baby)
        // Future reminder types append here.
        return result
    }

    // MARK: Feed every N hours

    /// When the next feed reminder should fire, or nil for none. Measured from the last feed's start or end; if
    /// that lands in quiet hours it waits for them to end. Judged on the *effective* time: a reminder that was
    /// held back by quiet hours stays planned until it fires, while one whose time has passed is dropped until
    /// the next feed is logged.
    public static func nextFeedDue(
        settings: FeedIntervalReminder,
        lastFeed: LastFeed?,
        now: Date,
        calendar: Calendar = .current
    ) -> (fire: Date, since: Date)? {
        guard settings.isEnabled, let feed = lastFeed else { return nil }
        let anchorDate: Date
        switch settings.anchor {
        case .start: anchorDate = feed.start
        case .end:
            // Still feeding: there is no end to measure from yet. The finished feed will move the reminder.
            guard let end = feed.end else { return nil }
            anchorDate = max(end, feed.start)
        }
        var due = anchorDate.addingTimeInterval(settings.interval)
        if let quiet = settings.quietHours {
            due = quiet.firstAllowedMoment(atOrAfter: due, calendar: calendar)
        }
        guard due > now else { return nil }
        return (due, anchorDate)
    }

    static func feedIntervalRequest(for baby: ReminderBaby, now: Date, calendar: Calendar) -> ReminderRequest? {
        guard let feed = baby.lastFeed,
              let (fire, since) = nextFeedDue(settings: baby.settings.feedEvery, lastFeed: feed, now: now, calendar: calendar)
        else { return nil }
        let name = displayName(baby.name)
        let info = FeedReminderInfo(babyName: name, feedStart: feed.start, since: since, kind: feed.kind, lastSide: feed.lastSide)
        return feedRequest(babyID: baby.id, identifier: ReminderIdentifier.feedInterval(babyID: baby.id), info: info, fire: fire)
    }

    private static func feedRequest(babyID: UUID, identifier: String, info: FeedReminderInfo, fire: Date) -> ReminderRequest {
        ReminderRequest(
            identifier: identifier,
            babyID: babyID,
            title: "Time to feed \(info.babyName)",
            body: feedBody(info: info, firesAt: fire),
            categoryIdentifier: ReminderCategory.feed,
            urgency: .timeSensitive,
            trigger: .date(fire),
            userInfo: [ReminderUserInfoKey.babyID: babyID.uuidString, ReminderUserInfoKey.feedInfo: info.userInfoValue ?? ""]
        )
    }

    /// "It's been 3h since Juniper's last feed (Right side). Next: Left"
    static func feedBody(info: FeedReminderInfo, firesAt fire: Date) -> String {
        let elapsed = fire.timeIntervalSince1970 - info.since
        let rounded = max(60, (elapsed / 60).rounded() * 60)
        var text = "It's been \(DurationFormat.short(rounded)) since \(info.babyName)'s last feed"
        if info.kind == .bottle {
            text += " (bottle)"
        } else if let side = info.lastSide {
            text += " (\(side.title) side). Next: \(side.other.title)"
        }
        return text
    }

    // MARK: Nap window

    /// A heads-up `lead` before the next predicted nap (or, if asked for, bedtime) window opens.
    ///
    /// Only for a prediction counted from a real wake-up: with no usable wake-up the predictor counts from "now",
    /// and a window that moves every time it is asked for would only ever produce a reminder that keeps sliding
    /// away. No prediction (the baby is asleep, or it is a night waking) means no reminder, so starting a sleep
    /// removes the pending one. A bedtime window is skipped unless `includeBedtime` is on, and a reminder whose
    /// time has already passed (including a window that is under `lead` away) is not scheduled.
    static func napWindowRequest(
        for baby: ReminderBaby,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> ReminderRequest? {
        let settings = baby.settings.napWindow
        guard settings.isEnabled, let birthDate = baby.birthDate,
              let prediction = SleepPredictor.next(birthDate: birthDate, sleeps: baby.sleeps, now: now, calendar: calendar),
              let wake = prediction.lastWake, wake <= now
        else { return nil }
        if prediction.kind == .bedtime, !settings.includeBedtime { return nil }

        let fire = prediction.window.start.addingTimeInterval(-settings.lead)
        guard fire > now else { return nil }

        let name = displayName(baby.name)
        let noun = prediction.kind == .nap ? "nap" : "bedtime"
        let minutes = Int(settings.lead / 60)
        let range = PredictionText.clockRange(of: prediction.window, calendar: calendar, locale: locale)
        return ReminderRequest(
            identifier: ReminderIdentifier.napWindow(babyID: baby.id),
            babyID: baby.id,
            title: prediction.kind == .nap ? "Nap window coming up" : "Bedtime coming up",
            body: "\(name)'s \(noun) window opens in \(minutes) min (\(range))",
            urgency: .active,
            trigger: .date(fire),
            userInfo: [ReminderUserInfoKey.babyID: baby.id.uuidString]
        )
    }

    // MARK: Daily reminders

    static func dailyRequests(for baby: ReminderBaby) -> [ReminderRequest] {
        let name = displayName(baby.name)
        return baby.settings.daily
            .filter(\.isEnabled)
            .sorted { ($0.minutesOfDay, $0.id.uuidString) < ($1.minutesOfDay, $1.id.uuidString) }
            .map { reminder in
                let body: String
                switch reminder.kind {
                case .feed: body = "Time to feed \(name)."
                case .medicine: body = "Medicine for \(name)."
                case .custom: body = "Reminder for \(name)."
                }
                return ReminderRequest(
                    identifier: ReminderIdentifier.daily(babyID: baby.id, reminderID: reminder.id),
                    babyID: baby.id,
                    title: reminder.displayLabel,
                    body: body,
                    categoryIdentifier: reminder.kind == .feed ? ReminderCategory.feed : nil,
                    urgency: reminder.kind == .custom ? .active : .timeSensitive,
                    trigger: .daily(hour: reminder.hour, minute: reminder.minute),
                    userInfo: [ReminderUserInfoKey.babyID: baby.id.uuidString]
                )
            }
    }

    // MARK: Snooze

    /// A one-off copy of a delivered reminder, `delay` seconds from `now`, under the baby's snooze identifier
    /// (snoozing again replaces it). Feed-interval reminders reword themselves so the elapsed time is right.
    public static func snooze(
        title: String,
        body: String,
        categoryIdentifier: String?,
        urgency: ReminderUrgency,
        userInfo: [String: String],
        now: Date,
        delay: TimeInterval = TimeInterval(ReminderCategory.snoozeMinutes * 60)
    ) -> ReminderRequest? {
        guard let babyID = userInfo[ReminderUserInfoKey.babyID].flatMap(UUID.init(uuidString:)) else { return nil }
        let fire = now.addingTimeInterval(delay)
        if let info = FeedReminderInfo(userInfo: userInfo) {
            return feedRequest(babyID: babyID, identifier: ReminderIdentifier.snooze(babyID: babyID), info: info, fire: fire)
        }
        return ReminderRequest(
            identifier: ReminderIdentifier.snooze(babyID: babyID),
            babyID: babyID,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            urgency: urgency,
            trigger: .date(fire),
            userInfo: userInfo
        )
    }

    /// True for a delivered or snoozed reminder that no longer applies: its baby is gone, or it was about a specific
    /// feed and a newer feed has been logged (or the feed reminder was turned off). Reminders that aren't about a
    /// specific feed (daily ones) are never stale.
    public static func isStale(userInfo: [String: String], babies: [ReminderBaby]) -> Bool {
        guard let babyID = userInfo[ReminderUserInfoKey.babyID].flatMap(UUID.init(uuidString:)) else { return false }
        guard let baby = babies.first(where: { $0.id == babyID }) else { return true }
        guard let info = FeedReminderInfo(userInfo: userInfo) else { return false }
        guard baby.settings.feedEvery.isEnabled, let feed = baby.lastFeed else { return true }
        return abs(feed.start.timeIntervalSince1970 - info.feedStart) > 0.5
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Baby" : trimmed
    }
}
