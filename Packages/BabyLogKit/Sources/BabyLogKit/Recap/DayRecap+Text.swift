import Foundation

extension DayRecap {
    /// The recap as plain text for people who do not have the app: a title, the summary, then one line per entry
    /// in time order. No notes, no names beyond the baby's.
    public func plainText(
        babyName: String,
        describer: EventDescriber,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let dateStyle = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).month(.wide).day()
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        func time(_ date: Date) -> String {
            // Newer systems put a narrow no-break space before AM/PM; plain text wants an ordinary space.
            date.formatted(timeStyle).replacingOccurrences(of: "\u{202F}", with: " ")
        }

        var lines = ["\(babyName): \(dayStart.formatted(dateStyle))", ""]

        // Summary.
        let s = summary
        var sleep = "Sleep: " + DurationFormat.short(s.sleep)
        if napCount > 0 { sleep += napCount == 1 ? " (1 nap)" : " (\(napCount) naps)" }
        lines.append(sleep)
        var feeds = "Feeds: \(s.feedCount)"
        var feedDetail: [String] = []
        if s.nursing > 0 { feedDetail.append("nursing " + DurationFormat.short(s.nursing)) }
        if s.bottleML > 0 { feedDetail.append("bottle " + describer.volumeUnit.format(milliliters: s.bottleML, locale: describer.locale)) }
        if !feedDetail.isEmpty { feeds += " (" + feedDetail.joined(separator: ", ") + ")" }
        lines.append(feeds)
        var diapers = "Diapers: \(s.diaperCount)"
        if s.diaperCount > 0 { diapers += " (\(s.wetCount) wet, \(s.dirtyCount) dirty)" }
        lines.append(diapers)
        if s.solidsCount > 0 { lines.append("Solids: \(s.solidsCount)") }
        if s.medicineCount > 0 { lines.append("Medicine: \(s.medicineCount)") }
        if s.pumpML > 0 {
            lines.append("Pumped: " + describer.volumeUnit.format(milliliters: s.pumpML, locale: describer.locale))
        }

        // Entries.
        var timeline: [String] = []
        if let carried = sleepSpans.first(where: { $0.continuesFromPreviousDay && $0.isRunning }),
           let since = carried.event.startDate {
            timeline.append("Still asleep since " + time(since) + " (from the day before)")
        }
        for hour in visibleHours {
            for entry in hour.entries {
                switch entry {
                case .event(let event):
                    let detail = describer.summary(for: event, now: now)
                    let title = event.kind.title
                    timeline.append(time(entry.time) + "  " + title + (detail.isEmpty ? "" : ": " + detail))
                case .wakeUp(let event):
                    let slept = DurationFormat.short(event.duration(at: now))
                    timeline.append(time(entry.time) + "  Woke up (slept " + slept + ")")
                }
            }
        }
        lines.append("")
        if timeline.isEmpty {
            lines.append("Nothing logged.")
        } else {
            lines.append(contentsOf: timeline)
        }
        return lines.joined(separator: "\n")
    }
}
