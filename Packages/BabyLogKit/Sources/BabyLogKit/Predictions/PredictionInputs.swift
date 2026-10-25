import CoreData
import Foundation

/// Reads the logs the predictors need out of Core Data. The predictors themselves never see Core Data.
public enum PredictionInputs {
    /// How far back the fetch reaches: the sleep history plus a day of margin.
    public static let lookbackDays = SleepHistory.historyDays + 1

    /// Sleeps and breastfeeds / bottles that start or end on or after `date`, plus any sleep still running.
    /// SwiftUI views use it directly as a `FetchRequest`, with a start-of-day `date` so the request stays equal
    /// all day; pass the events to `samples(from:now:)`.
    public static func fetchRequest(for baby: Baby, from date: Date) -> NSFetchRequest<LogEvent> {
        let request = LogEvent.requestAll(baby: baby, kinds: [.sleep, .breastfeed, .bottle], ascending: true)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate ?? NSPredicate(value: true),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "startDate >= %@", date as NSDate),
                NSPredicate(format: "endDate >= %@", date as NSDate),
                NSPredicate(format: "kindRaw == %@ AND endDate == nil", EventKind.sleep.rawValue),
            ]),
        ])
        return request
    }

    /// Plain values for the predictors: all the sleeps given, and the feeds of the last 4 days.
    public static func samples<Events: Sequence>(
        from events: Events,
        now: Date
    ) -> (sleeps: [SleepSession], feeds: [FeedSample]) where Events.Element == LogEvent {
        let feedFrom = now.addingTimeInterval(-TimeInterval(FeedPredictor.historyDays + 1) * 86_400)
        var sleeps: [SleepSession] = []
        var feeds: [FeedSample] = []
        for event in events {
            guard let start = event.startDate else { continue }
            switch event.kind {
            case .sleep:
                sleeps.append(SleepSession(start: start, end: event.endDate))
            case .breastfeed, .bottle:
                if start >= feedFrom { feeds.append(FeedSample(start: start, kind: event.kind)) }
            default:
                break
            }
        }
        sleeps.sort { $0.start < $1.start }
        feeds.sort { $0.start < $1.start }
        return (sleeps, feeds)
    }

    /// Sleeps from the last 14 days (plus any still running) and breastfeeds / bottles from the last 4 days.
    public static func load(
        for baby: Baby,
        in context: NSManagedObjectContext,
        now: Date
    ) -> (sleeps: [SleepSession], feeds: [FeedSample]) {
        var result: (sleeps: [SleepSession], feeds: [FeedSample]) = ([], [])
        context.performAndWait {
            let from = now.addingTimeInterval(-TimeInterval(lookbackDays) * 86_400)
            let events = (try? context.fetch(fetchRequest(for: baby, from: from))) ?? []
            result = samples(from: events, now: now)
        }
        return result
    }

    /// Both predictions for a baby right now. Nil parts are simply omitted. Used by the widget snapshot.
    public static func predictions(
        for baby: Baby,
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar = .current
    ) -> (sleep: SleepPrediction?, feed: FeedPrediction?) {
        var birthDate: Date?
        context.performAndWait { birthDate = baby.birthDate }
        guard let birthDate else { return (nil, nil) }
        let inputs = load(for: baby, in: context, now: now)
        return (
            SleepPredictor.next(birthDate: birthDate, sleeps: inputs.sleeps, now: now, calendar: calendar),
            FeedPredictor.next(birthDate: birthDate, feeds: inputs.feeds, now: now, calendar: calendar)
        )
    }
}
