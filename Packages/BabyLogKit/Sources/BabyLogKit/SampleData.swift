import CoreData
import Foundation

/// Realistic data for SwiftUI previews and tests.
public enum SampleData {
    /// Creates "Juniper", born 7 weeks ago, with ~3 days of events and a growth entry; saves.
    @discardableResult
    public static func populate(_ context: NSManagedObjectContext, now: Date = .now) -> Baby {
        let calendar = Calendar.current
        let birth = calendar.date(byAdding: .day, value: -49, to: now) ?? now.addingTimeInterval(-49 * 86400)
        let baby = Baby.create(name: "Juniper", birthDate: birth, in: context)
        let startOfToday = calendar.startOfDay(for: now)

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -day, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
                ?? base.addingTimeInterval(Double(hour * 3600 + minute * 60))
        }

        func minutes(_ m: Double) -> TimeInterval { m * 60 }

        for day in (0...2).reversed() {
            // Sleep: night stretch ending in the morning, plus naps. Night sleep starts the evening before.
            let nightStart = at(day + 1, 21, 15)
            let nightEnd = at(day, 6, 40 + day * 5)
            sleep(baby, nightStart, nightEnd, now, context)
            sleep(baby, at(day, 9, 30), at(day, 10, 45), now, context)
            sleep(baby, at(day, 13, 0), at(day, 14, 20), now, context)
            sleep(baby, at(day, 16, 45), at(day, 17, 15), now, context)

            // Nursing, alternating sides.
            let nursingTimes = [(7, 5), (10, 50), (13, 40), (17, 30), (20, 15)]
            for (index, time) in nursingTimes.enumerated() {
                let start = at(day, time.0, time.1)
                guard start < now else { continue }
                let event = LogEvent.create(kind: .breastfeed, for: baby, start: start, in: context)
                let first: BreastSide = (index + day) % 2 == 0 ? .left : .right
                let firstSeconds = minutes(Double(8 + index % 3))
                let secondSeconds = minutes(Double(5 + index % 2))
                event.startSide(first, at: start)
                event.startSide(first.other, at: start.addingTimeInterval(firstSeconds))
                event.finishNursing(at: start.addingTimeInterval(firstSeconds + secondSeconds))
                if event.endDate.map({ $0 > now }) ?? false {
                    event.endDate = start
                    event.leftSeconds = 0; event.rightSeconds = 0
                }
            }

            // Bottles.
            for (index, time) in [(4, 0), (22, 30)].enumerated() {
                let start = at(day, time.0, time.1)
                guard start < now else { continue }
                let event = LogEvent.create(kind: .bottle, for: baby, start: start, in: context)
                event.amountML = index == 0 ? 90 : 120
                event.bottleContent = index == 0 ? .breastMilk : .formula
            }

            // Pumping.
            let pumpStart = at(day, 15, 10)
            if pumpStart < now {
                let event = LogEvent.create(kind: .pump, for: baby, start: pumpStart, in: context)
                event.endDate = pumpStart.addingTimeInterval(minutes(18))
                event.leftML = 60
                event.rightML = 50
            }

            // Diapers.
            let diaperKinds: [DiaperKind] = [.wet, .mixed, .wet, .dirty, .wet, .wet, .mixed]
            let diaperHours = [(3, 45), (7, 20), (11, 0), (14, 30), (17, 45), (20, 30), (23, 0)]
            for (index, time) in diaperHours.enumerated() {
                let start = at(day, time.0, time.1)
                guard start < now else { continue }
                let event = LogEvent.create(kind: .diaper, for: baby, start: start, in: context)
                event.diaperKind = diaperKinds[(index + day) % diaperKinds.count]
            }

            // One medicine dose on the oldest day.
            if day == 2 {
                let event = LogEvent.create(kind: .medicine, for: baby, start: at(day, 19, 0), in: context)
                event.medicineName = "Vitamin D"
                event.dose = "1 drop"
            }
        }

        // Growth entry from ~2 days ago.
        let growthDate = min(at(2, 11, 30), now)
        let growth = LogEvent.create(kind: .growth, for: baby, start: growthDate, in: context)
        growth.weightKg = 4.25
        growth.lengthCm = 55.5
        growth.headCm = 37

        context.saveIfNeeded()
        return baby
    }

    private static func sleep(_ baby: Baby, _ start: Date, _ end: Date, _ now: Date, _ context: NSManagedObjectContext) {
        guard start < now else { return }
        let event = LogEvent.create(kind: .sleep, for: baby, start: start, in: context)
        event.endDate = min(end, now)
    }
}
