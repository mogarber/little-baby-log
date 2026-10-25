import CoreData
import Foundation

/// Core Data adapter: reads each baby's latest feed (nursing or bottle) and pairs it with the stored settings.
/// A baby with the nap-window reminder on also brings the recent sleeps and birth date `SleepPredictor` needs.
public enum ReminderInputs {
    /// One `ReminderBaby` per baby in `context`, oldest first.
    public static func load(
        in context: NSManagedObjectContext,
        settings store: ReminderSettingsStore = ReminderSettingsStore(),
        now: Date = Date()
    ) -> [ReminderBaby] {
        let settingsByBaby = store.all()
        var result: [ReminderBaby] = []
        context.performAndWait {
            let request = Baby.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let babies = (try? context.fetch(request)) ?? []
            for baby in babies {
                guard let id = baby.uuid else { continue }
                let settings = settingsByBaby[id] ?? BabyReminderSettings()
                // Sleeps are only read when the nap reminder needs them.
                let napInputs = settings.napWindow.isEnabled && baby.birthDate != nil
                result.append(ReminderBaby(
                    id: id,
                    name: baby.displayName,
                    settings: settings,
                    lastFeed: lastFeed(of: baby, in: context),
                    birthDate: napInputs ? baby.birthDate : nil,
                    sleeps: napInputs ? PredictionInputs.load(for: baby, in: context, now: now).sleeps : []
                ))
            }
        }
        return result
    }

    /// The newest feed by start time. A running nursing session that hasn't started either side yet (the timer
    /// screen's placeholder) isn't a feed.
    static func lastFeed(of baby: Baby, in context: NSManagedObjectContext) -> LastFeed? {
        let request = LogEvent.requestAll(baby: baby, kinds: [.breastfeed, .bottle])
        request.fetchLimit = 5
        let events = (try? context.fetch(request)) ?? []
        for event in events {
            guard let start = event.startDate else { continue }
            if event.kind == .breastfeed, event.endDate == nil, event.lastSide == nil, event.activeSide == nil,
               event.totalBreastSeconds(at: start) == 0 {
                continue
            }
            return LastFeed(
                start: start,
                // A bottle is over the moment it's logged; only a nursing timer can still be running.
                end: event.kind == .bottle ? (event.endDate ?? start) : event.endDate,
                kind: event.kind,
                lastSide: event.kind == .breastfeed ? event.lastSide : nil
            )
        }
        return nil
    }
}
