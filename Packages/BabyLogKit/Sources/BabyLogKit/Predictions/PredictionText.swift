import Foundation

/// The words around a prediction, kept here so they are tested and the app and widgets agree.
public enum PredictionText {
    public static let disclaimer = "Estimates from typical ranges and your logs. Not medical advice."

    public static let howItWorks = """
        Babies are usually ready to sleep after being awake for a while, and that "wake window" grows with age. \
        We start from typical wake windows for your baby's age. As you log sleeps, the app mixes in your baby's own \
        recent pattern, and after about ten matching wake-ups it mostly follows your baby. Bedtime is predicted from \
        your usual bedtime and how long since the last nap. Feeds work the same way, using the gaps between recent \
        feeds, with day and night counted separately. Everything is worked out on this device from your logs. Nothing \
        is sent anywhere.
        """

    /// "Based on Juniper's last 7 days" when the baby's own pattern dominates, "Typical for 7 weeks, tuned to
    /// Juniper's last 5 days" when mixed, "Typical for 7 weeks" when there is not enough history yet.
    public static func caption(basis: PredictionBasis, babyName: String, ageDays: Int) -> String {
        switch basis {
        case .typicalForAge:
            return "Typical for \(ageLabel(ageDays: ageDays))"
        case .blended(let days):
            return "Typical for \(ageLabel(ageDays: ageDays)), tuned to \(babyName)'s \(lastDays(days))"
        case .personal(let days):
            return "Based on \(babyName)'s \(lastDays(days))"
        }
    }

    private static func lastDays(_ days: Int) -> String {
        let days = min(max(days, 1), SleepHistory.historyDays)
        return days == 1 ? "last day" : "last \(days) days"
    }

    /// "newborns", "12 days", "7 weeks", "6 months", "2 years" (the largest unit that is at least 2, up to 12
    /// weeks and 24 months).
    public static func ageLabel(ageDays: Int) -> String {
        let ageDays = max(0, ageDays)
        if ageDays < 7 { return "newborns" }
        if ageDays < 14 { return "\(ageDays) days" }
        if ageDays < 84 { return "\(ageDays / 7) weeks" }
        let months = Int((Double(ageDays) / 30.4375).rounded(.down))
        if months < 24 { return "\(months) months" }
        return "\(months / 12) years"
    }

    /// "2:10–2:40 PM" for a window, on the clock of `calendar`'s time zone and in `locale`'s style.
    public static func clockRange(of window: DateInterval, calendar: Calendar, locale: Locale) -> String {
        (window.start..<window.end).formatted(
            Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        )
    }

    /// Where `now` stands against a prediction window.
    public enum Timing: Equatable, Sendable {
        case upcoming(TimeInterval)
        case now
        case overdue

        /// "in 25m", "in 1h 5m", "now", "overdue". Rounds up to whole minutes.
        public var text: String {
            switch self {
            case .upcoming(let seconds):
                let minutes = max(1, Int((seconds / 60).rounded(.up)))
                return "in " + DurationFormat.short(TimeInterval(minutes * 60))
            case .now: return "now"
            case .overdue: return "overdue"
            }
        }
    }

    public static func timing(of window: DateInterval, at now: Date) -> Timing {
        if now < window.start { return .upcoming(window.start.timeIntervalSince(now)) }
        return now <= window.end ? .now : .overdue
    }
}
