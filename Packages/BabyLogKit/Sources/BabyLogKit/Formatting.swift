import Foundation

public enum DurationFormat {
    /// "1h 5m", "2h", "12m", "45s"
    public static func short(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// "5:09", "1:05:09"
    public static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public enum BabyAge {
    /// "Born today", "5 days old", "3 weeks, 2 days", "4 months, 1 week", "2 years, 3 months", "Due in 3 days"
    public static func description(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let birthDay = calendar.startOfDay(for: birthDate)
        let today = calendar.startOfDay(for: now)

        if birthDay > today {
            let days = calendar.dateComponents([.day], from: today, to: birthDay).day ?? 0
            return "Due in \(plural(days, "day"))"
        }

        let parts = calendar.dateComponents([.year, .month, .day], from: birthDay, to: today)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        let days = parts.day ?? 0

        if years >= 1 {
            return join(plural(years, "year"), months > 0 ? plural(months, "month") : nil)
        }
        if months >= 1 {
            let weeks = days / 7
            return join(plural(months, "month"), weeks > 0 ? plural(weeks, "week") : nil)
        }
        if days == 0 { return "Born today" }
        if days < 7 { return "\(plural(days, "day")) old" }
        let weeks = days / 7
        let rest = days % 7
        return join(plural(weeks, "week"), rest > 0 ? plural(rest, "day") : nil)
    }

    private static func plural(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s")"
    }

    private static func join(_ first: String, _ second: String?) -> String {
        second.map { "\(first), \($0)" } ?? first
    }
}

public struct EventDescriber {
    public var volumeUnit: VolumeUnit
    public var unitSystem: UnitSystem
    public var locale: Locale

    public init(volumeUnit: VolumeUnit, unitSystem: UnitSystem, locale: Locale = .current) {
        self.volumeUnit = volumeUnit
        self.unitSystem = unitSystem
        self.locale = locale
    }

    /// One-line detail for timeline rows.
    public func summary(for event: LogEvent, now: Date = .now) -> String {
        switch event.kind {
        case .sleep:
            let text = DurationFormat.short(event.duration(at: now))
            return event.isRunning ? "Asleep for \(text)" : text

        case .breastfeed:
            var parts: [String] = []
            for side in BreastSide.allCases {
                let seconds = event.breastSeconds(side, at: now)
                if seconds > 0 { parts.append("\(side.shortLabel) \(DurationFormat.short(seconds))") }
            }
            if parts.isEmpty { return event.isRunning ? "Timer running" : "" }
            return parts.joined(separator: " · ")

        case .bottle:
            var text = volumeUnit.format(milliliters: event.amountML, locale: locale)
            if let content = event.bottleContent, content != .other {
                text += " " + content.title.lowercased()
            }
            return text

        case .solids:
            return event.foodName ?? ""

        case .diaper:
            return event.diaperKind?.title ?? ""

        case .pump:
            var parts: [String] = []
            if event.leftML > 0 { parts.append("L " + volumeUnit.format(milliliters: event.leftML, locale: locale)) }
            if event.rightML > 0 { parts.append("R " + volumeUnit.format(milliliters: event.rightML, locale: locale)) }
            return parts.joined(separator: " · ")

        case .growth:
            var parts: [String] = []
            if event.weightKg > 0 { parts.append(unitSystem.formatWeight(kilograms: event.weightKg, locale: locale)) }
            if event.lengthCm > 0 { parts.append(unitSystem.formatLength(centimeters: event.lengthCm, locale: locale)) }
            if event.headCm > 0 { parts.append("head " + unitSystem.formatLength(centimeters: event.headCm, locale: locale)) }
            return parts.joined(separator: " · ")

        case .medicine:
            return [event.medicineName, event.dose]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }
}
