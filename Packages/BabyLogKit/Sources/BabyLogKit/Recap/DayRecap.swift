import CoreData
import Foundation

/// One calendar day laid out hour by hour, for the daily recap: the day's summary, one bucket per real clock hour
/// holding the events that START in it, and the sleeps clipped to the day (so a night that crosses midnight shows
/// on both days, and a running sleep ends at `now`).
///
/// Pure and clock-free: pass the day, the events, the calendar and `now`. Hours are walked with the calendar, so a
/// daylight-saving day has 23 or 25 of them and the repeated hour stays two distinct buckets.
public struct DayRecap {
    /// A sleep clipped to the day.
    public struct SleepSpan: Identifiable {
        public let event: LogEvent
        /// Clipped to the day.
        public let start: Date
        /// Clipped to the day; a running sleep ends at `now` (or the end of the day, on a past day).
        public let end: Date
        public let continuesFromPreviousDay: Bool
        public let continuesIntoNextDay: Bool
        public let isRunning: Bool

        public var id: NSManagedObjectID { event.objectID }
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The part of a sleep span inside one hour, as fractions (0...1) of that hour.
    public struct SleepSlice {
        public let span: SleepSpan
        public let from: Double
        public let to: Double
        /// The sleep really begins in this hour (not clipped by the start of the day): draw a rounded top.
        public let startsHere: Bool
        /// The sleep really ends in this hour (not clipped by the end of the day; a running sleep ends at the
        /// "now" line): draw a rounded bottom.
        public let endsHere: Bool
    }

    /// One line of an hour: an event that starts in it, or a wake-up (a sleep that began in an earlier hour and
    /// ended in this one).
    public enum Entry: Identifiable {
        case event(LogEvent)
        case wakeUp(LogEvent)

        public var id: String {
            switch self {
            case .event(let event): return "e-" + event.objectID.uriRepresentation().absoluteString
            case .wakeUp(let event): return "w-" + event.objectID.uriRepresentation().absoluteString
            }
        }

        public var event: LogEvent {
            switch self {
            case .event(let event), .wakeUp(let event): return event
            }
        }

        public var time: Date {
            switch self {
            case .event(let event): return event.startDate ?? .distantPast
            case .wakeUp(let event): return event.endDate ?? .distantPast
            }
        }
    }

    /// One real clock hour of the day.
    public struct Hour: Identifiable {
        /// Position in the day (0-based). On a DST day this is not the clock hour.
        public let index: Int
        public let start: Date
        public let end: Date
        /// The clock hour, 0...23.
        public let hourOfDay: Int
        /// The second pass through a clock hour on a fall-back day.
        public let isRepeated: Bool
        /// Events that start in [start, end), oldest first.
        public let events: [LogEvent]
        /// Sleeps that began before this hour and ended in it, oldest first.
        public let wakeUps: [LogEvent]
        public let sleepSlices: [SleepSlice]

        public var id: Int { index }

        /// Events and wake-ups together, in time order.
        public var entries: [Entry] {
            let all = events.map(Entry.event) + wakeUps.map(Entry.wakeUp)
            return all.enumerated().sorted { lhs, rhs in
                lhs.element.time != rhs.element.time ? lhs.element.time < rhs.element.time : lhs.offset < rhs.offset
            }.map(\.element)
        }

        public var hasEntries: Bool { !events.isEmpty || !wakeUps.isEmpty }

        /// A sleep covers the whole hour.
        public var isFullyAsleep: Bool {
            sleepSlices.contains { $0.from <= 0.0001 && $0.to >= 0.9999 }
        }
    }

    /// A run of consecutive hours with nothing in them, shown as one short row.
    public struct QuietRun {
        public let hours: [Hour]
        /// A sleep covers the whole run (the sleep bar passes through it).
        public let isAsleep: Bool

        public var first: Hour { hours[0] }
        public var last: Hour { hours[hours.count - 1] }
        public var asleepDuration: TimeInterval {
            isAsleep ? hours.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } : 0
        }
    }

    public enum Row: Identifiable {
        case hour(Hour)
        case quiet(QuietRun)

        /// Index of the first hour in the row, which is unique across rows.
        public var id: Int {
            switch self {
            case .hour(let hour): return hour.index
            case .quiet(let run): return run.first.index
            }
        }
    }

    public let dayStart: Date
    public let dayEnd: Date
    public let now: Date
    public let summary: DaySummary
    /// Daytime sleeps that start in this day. See `isNap`.
    public let napCount: Int
    /// Every real hour of the day, including future ones when the day is today.
    public let hours: [Hour]
    /// Sleeps overlapping the day, clipped to it, oldest first.
    public let sleepSpans: [SleepSpan]

    public init(day: Date, events: [LogEvent], calendar: Calendar, now: Date = .now) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.now = now
        self.summary = DaySummary(events: events, interval: DateInterval(start: dayStart, end: dayEnd), now: now)

        // Sleeps, clipped to the day.
        var spans: [SleepSpan] = []
        for event in events where event.kind == .sleep {
            guard let start = event.startDate else { continue }
            let rawEnd = event.endDate ?? now
            let from = max(start, dayStart)
            let to = min(rawEnd, dayEnd)
            guard to > from else { continue }
            spans.append(SleepSpan(
                event: event,
                start: from,
                end: to,
                continuesFromPreviousDay: start < dayStart,
                continuesIntoNextDay: rawEnd > dayEnd,
                isRunning: event.endDate == nil
            ))
        }
        spans.sort { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        self.sleepSpans = spans

        // Hour boundaries, walked with the calendar.
        var bounds: [(start: Date, end: Date)] = []
        var cursor = dayStart
        while cursor < dayEnd {
            var next = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? cursor.addingTimeInterval(3600)
            if next <= cursor { next = cursor.addingTimeInterval(3600) }
            if next > dayEnd { next = dayEnd }
            bounds.append((cursor, next))
            cursor = next
        }

        // Events that start in the day go in the hour they start in.
        var buckets = [[LogEvent]](repeating: [], count: bounds.count)
        var wakeBuckets = [[LogEvent]](repeating: [], count: bounds.count)
        func hourIndex(of date: Date) -> Int? {
            guard date >= dayStart, date < dayEnd else { return nil }
            return bounds.lastIndex { $0.start <= date }
        }
        for event in events {
            guard let start = event.startDate else { continue }
            if let index = hourIndex(of: start) { buckets[index].append(event) }
            if event.kind == .sleep, let end = event.endDate, end > start, let index = hourIndex(of: end),
               start < bounds[index].start {
                wakeBuckets[index].append(event)
            }
        }
        let kindOrder = Dictionary(uniqueKeysWithValues: EventKind.allCases.enumerated().map { ($1, $0) })
        func sorted(_ events: [LogEvent]) -> [LogEvent] {
            events.sorted { lhs, rhs in
                let l = lhs.startDate ?? .distantPast, r = rhs.startDate ?? .distantPast
                if l != r { return l < r }
                let lk = kindOrder[lhs.kind] ?? 0, rk = kindOrder[rhs.kind] ?? 0
                if lk != rk { return lk < rk }
                return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
            }
        }

        var built: [Hour] = []
        for (index, bound) in bounds.enumerated() {
            let hourOfDay = calendar.component(.hour, from: bound.start)
            let length = bound.end.timeIntervalSince(bound.start)
            var slices: [SleepSlice] = []
            for span in spans {
                let from = max(span.start, bound.start)
                let to = min(span.end, bound.end)
                guard to > from, length > 0 else { continue }
                slices.append(SleepSlice(
                    span: span,
                    from: from.timeIntervalSince(bound.start) / length,
                    to: to.timeIntervalSince(bound.start) / length,
                    startsHere: !span.continuesFromPreviousDay && span.start >= bound.start && span.start < bound.end,
                    endsHere: !span.continuesIntoNextDay && span.end > bound.start && span.end <= bound.end
                ))
            }
            built.append(Hour(
                index: index,
                start: bound.start,
                end: bound.end,
                hourOfDay: hourOfDay,
                isRepeated: index > 0 && built[index - 1].hourOfDay == hourOfDay,
                events: sorted(buckets[index]),
                wakeUps: wakeBuckets[index].sorted { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) },
                sleepSlices: slices
            ))
        }
        self.hours = built

        self.napCount = events.reduce(0) { count, event in
            guard event.kind == .sleep, let start = event.startDate, start >= dayStart, start < dayEnd else { return count }
            return Self.isNap(start: start, end: event.endDate, calendar: calendar, now: now) ? count + 1 : count
        }
    }

    // MARK: Today

    /// `now` falls in this day.
    public var isToday: Bool { now >= dayStart && now < dayEnd }

    /// The hour `now` is in, for today.
    public var currentHourIndex: Int? {
        isToday ? hours.lastIndex { $0.start <= now } : nil
    }

    /// The hour has not started yet.
    public func isFuture(_ hour: Hour) -> Bool { hour.start > now }

    /// Hours to list: all of them on a past day, up to and including the current one today.
    public var visibleHours: [Hour] { hours.filter { !isFuture($0) } }

    /// Nothing to show: no event starts in the day and no sleep touches it.
    public var isEmpty: Bool {
        sleepSpans.isEmpty && hours.allSatisfy { !$0.hasEntries }
    }

    /// Events that start in the day.
    public var eventCount: Int { hours.reduce(0) { $0 + $1.events.count } }

    // MARK: Layout

    /// The visible hours as rows: an hour with something in it (or the current hour) is a row of its own, and
    /// consecutive empty hours with the same sleep state collapse into one `QuietRun`.
    public var rows: [Row] {
        let current = currentHourIndex
        var result: [Row] = []
        var run: [Hour] = []
        func flush() {
            guard !run.isEmpty else { return }
            result.append(.quiet(QuietRun(hours: run, isAsleep: run[0].isFullyAsleep)))
            run = []
        }
        for hour in visibleHours {
            let collapsible = !hour.hasEntries && hour.index != current
                && (hour.sleepSlices.isEmpty || hour.isFullyAsleep)
            if collapsible {
                if let first = run.first, first.isFullyAsleep != hour.isFullyAsleep { flush() }
                run.append(hour)
            } else {
                flush()
                result.append(.hour(hour))
            }
        }
        flush()
        return result
    }

    // MARK: Naps

    /// A sleep that is not the night's: it starts after 5:30 AM, and either before 5:30 PM, or before 7:00 PM and
    /// shorter than three hours. Age-independent on purpose, so the recap does not need the baby's birthday.
    public static func isNap(start: Date, end: Date?, calendar: Calendar, now: Date) -> Bool {
        let length = (end ?? now).timeIntervalSince(start)
        guard length > 0 else { return false }
        let minute = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        if minute < 5 * 60 + 30 { return false }
        if minute < 17 * 60 + 30 { return true }
        return minute < 19 * 60 && length < 3 * 3600
    }
}

// MARK: - Fetching

extension LogEvent {
    /// Events that touch the interval: starting in it, or starting before its end and either ending at or after
    /// its start or still running. Oldest first, so a recap needs no re-sort.
    public static func requestDay(baby: Baby, interval: DateInterval) -> NSFetchRequest<LogEvent> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        let start = interval.start as NSDate, end = interval.end as NSDate
        let startsInside = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "startDate >= %@", start), NSPredicate(format: "startDate < %@", end),
        ])
        let reachesIn = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "startDate < %@", end),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "endDate >= %@", start),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "kindRaw IN %@", [EventKind.sleep.rawValue, EventKind.breastfeed.rawValue]),
                    NSPredicate(format: "endDate == nil"),
                ]),
            ]),
        ])
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "baby == %@", baby),
            NSCompoundPredicate(orPredicateWithSubpredicates: [startsInside, reachesIn]),
        ])
        return request
    }
}
