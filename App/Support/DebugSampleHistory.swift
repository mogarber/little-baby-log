#if DEBUG
import CoreData
import Foundation
import os
import BabyLogKit

/// Debug-only: fills the first baby with about ten days of plausible sleeps and feeds, so Up next, the widgets,
/// and the predictions have something to work from in the simulator (not compiled in Release).
///
/// - `-lblSeedHistory`: replace any earlier seeded history with a fresh one that ends right now.
/// - `-lblSeedAgeDays N`: age of the baby in days (default 49, i.e. 7 weeks). Creates "Juniper" if there is no baby.
/// - `-lblSeedAsleep`: leave a sleep running, to check that the nap line hides.
/// - `-lblSeedWindowInMinutes N`: replace today's seeded sleeps with one nap whose wake-up is placed so that the
///   predicted next window opens N minutes from now (for trying the nap window reminder without waiting).
///
/// Seeded events carry a note marker, so running it again replaces them and leaves anything else alone. The
/// schedule is built from `AgeNorms` (wake windows and feed gaps at the middle of the age range, a little noise),
/// so it behaves like an average baby of that age.
@MainActor
enum DebugSampleHistory {
    private static let marker = "lbl-debug-seed"
    private static let log = Logger(subsystem: "app.littlebabylog", category: "debug")

    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-lblSeedHistory") else { return }
        let requestedAge = UserDefaults.standard.string(forKey: "lblSeedAgeDays").flatMap(Int.init)
        let windowIn = UserDefaults.standard.string(forKey: "lblSeedWindowInMinutes").flatMap(Int.init)
        seed(ageDays: requestedAge, asleep: arguments.contains("-lblSeedAsleep"), windowInMinutes: windowIn)
    }

    private struct Noise {
        var state: UInt64 = 0x9E3779B97F4A7C15
        mutating func minutes(_ plusMinus: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(2 * plusMinus + 1)) - plusMinus
        }
    }

    /// Adds one nap today whose wake-up makes `SleepPredictor` open its next window `minutes` from now.
    private static func placeWindow(
        in minutes: Int,
        sleeps: [(start: Date, end: Date)],
        birthDate: Date,
        now: Date,
        calendar: Calendar
    ) -> [(start: Date, end: Date)] {
        let target = now.addingTimeInterval(TimeInterval(minutes * 60))
        var wake = now.addingTimeInterval(-20 * 60)
        var result = sleeps
        for _ in 0..<5 {
            let nap = (start: wake.addingTimeInterval(-40 * 60), end: wake)
            result = sleeps + [nap]
            let input = result.map { SleepSession(start: $0.start, end: $0.end) }
            guard let prediction = SleepPredictor.next(birthDate: birthDate, sleeps: input, now: now, calendar: calendar) else { break }
            let delta = target.timeIntervalSince(prediction.window.start)
            if abs(delta) < 5 { break }
            wake = min(wake.addingTimeInterval(delta), now.addingTimeInterval(-60))
        }
        return result
    }

    private static func seed(ageDays requestedAge: Int?, asleep: Bool, windowInMinutes: Int?) {
        let persistence = PersistenceController.shared
        guard persistence.loadError == nil else { return }
        let context = persistence.viewContext
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let baby: Baby
        var age = requestedAge
        if let existing = (try? context.fetch(Baby.lblAllByCreation()))?.first {
            baby = existing
        } else {
            baby = Baby.create(name: "Juniper", birthDate: today, in: context)
            UserDefaults.standard.set(baby.uuid?.uuidString, forKey: Prefs.selectedBabyID)
            age = age ?? 49
        }
        if let age {
            baby.birthDate = calendar.date(byAdding: .day, value: -age, to: today)
        }
        let ageDays = AgeNorms.ageDays(birthDate: baby.birthDate ?? today, now: now, calendar: calendar)

        let old = LogEvent.requestAll(baby: baby)
        old.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            old.predicate ?? NSPredicate(value: true), NSPredicate(format: "notes == %@", marker),
        ])
        for event in (try? context.fetch(old)) ?? [] { context.delete(event) }

        var noise = Noise()
        func at(_ day: Int, minute: Int) -> Date {
            let start = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start) ?? start
        }

        // Sleep.
        let wakeWindow = Int(AgeNorms.midpoint(AgeNorms.wakeWindow(ageDays: ageDays)) / 60)
        let bed = AgeNorms.typicalBedtime(ageDays: ageDays) ?? 21 * 60
        let napMinutes = ageDays < 120 ? 50 : 75
        var sleeps: [(start: Date, end: Date)] = []
        for day in -10...0 {
            let wake = at(day, minute: 7 * 60 - 15 + noise.minutes(10))
            var cursor = wake
            var naps = 0
            let maxNaps = AgeNorms.napsPerDay(ageDays: ageDays).upperBound
            let bedStart = at(day, minute: bed + noise.minutes(10))
            while naps < maxNaps {
                let start = cursor.addingTimeInterval(TimeInterval((wakeWindow + noise.minutes(8)) * 60))
                if start.addingTimeInterval(TimeInterval(wakeWindow * 30)) > bedStart { break }
                let end = start.addingTimeInterval(TimeInterval((napMinutes + noise.minutes(15)) * 60))
                sleeps.append((start, end))
                cursor = end
                naps += 1
            }
            // The night after this day: one or two stretches.
            let nextWake = at(day + 1, minute: 7 * 60 - 15 + noise.minutes(10))
            if ageDays < 180 {
                let first = bedStart.addingTimeInterval(TimeInterval((200 + noise.minutes(20)) * 60))
                sleeps.append((bedStart, first))
                sleeps.append((first.addingTimeInterval(40 * 60), nextWake))
            } else {
                sleeps.append((bedStart, nextWake))
            }
        }

        if let minutes = windowInMinutes, !asleep {
            sleeps = placeWindow(
                in: minutes, sleeps: sleeps.filter { $0.start < today }, birthDate: baby.birthDate ?? today, now: now, calendar: calendar
            )
        }

        // Feeds.
        let feedGap = Int(AgeNorms.midpoint(AgeNorms.feedInterval(ageDays: ageDays)) / 60)
        var feeds: [(start: Date, kind: EventKind)] = []
        var cursor = at(-10, minute: 6 * 60 + 40)
        var count = 0
        while cursor < now {
            feeds.append((cursor, count % 6 == 5 ? .bottle : .breastfeed))
            let minute = calendar.component(.hour, from: cursor) * 60 + calendar.component(.minute, from: cursor)
            let night = minute < 7 * 60 || minute >= 19 * 60
            cursor = cursor.addingTimeInterval(TimeInterval((feedGap + (night ? 30 : 0) + noise.minutes(10)) * 60))
            count += 1
        }

        for sleep in sleeps where sleep.start < now {
            let event = LogEvent.create(kind: .sleep, for: baby, start: sleep.start, in: context)
            event.notes = marker
            if sleep.end > now {
                if asleep { continue }
                event.endDate = now.addingTimeInterval(-5 * 60)
                if event.endDate! <= sleep.start { context.delete(event) }
            } else {
                event.endDate = sleep.end
            }
        }
        if asleep {
            let event = LogEvent.create(kind: .sleep, for: baby, start: now.addingTimeInterval(-20 * 60), in: context)
            event.notes = marker
        }
        for (index, feed) in feeds.enumerated() {
            let event = LogEvent.create(kind: feed.kind, for: baby, start: feed.start, in: context)
            event.notes = marker
            if feed.kind == .bottle {
                event.amountML = 90
                event.bottleContent = .formula
            } else {
                event.startSide(index % 2 == 0 ? .left : .right, at: feed.start)
                event.finishNursing(at: feed.start.addingTimeInterval(14 * 60))
            }
        }
        context.saveIfNeeded()
        log.notice("debug: seeded \(sleeps.count) sleeps and \(feeds.count) feeds for a baby \(ageDays) days old")
    }
}
#endif
