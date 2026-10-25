import Foundation
import BabyLogKit

/// Sample babies for placeholders and `#Preview(as:)`.
enum SampleSnapshot {
    static let id = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

    /// Fed a while ago, nothing running.
    static func resting(now: Date = .now) -> WidgetSnapshot.BabySummary {
        WidgetSnapshot.BabySummary(
            id: id,
            name: "Juniper",
            lastFeed: .init(
                startedAt: now.addingTimeInterval(-(2 * 3600 + 25 * 60)),
                kind: .breastfeed,
                detail: "L 8m · R 6m",
                endedAt: now.addingTimeInterval(-(2 * 3600 + 10 * 60))
            ),
            nextSide: .right,
            lastDiaperAt: now.addingTimeInterval(-45 * 60),
            lastDiaperKind: .wet,
            lastSleepEndedAt: now.addingTimeInterval(-70 * 60),
            today: .init(feeds: 5, diapers: 6, sleep: 9 * 3600 + 20 * 60),
            nextSleep: .init(kind: .nap, start: now.addingTimeInterval(10 * 60), end: now.addingTimeInterval(40 * 60)),
            nextFeed: .init(start: now.addingTimeInterval(20 * 60), end: now.addingTimeInterval(50 * 60))
        )
    }

    /// Nursing on the left, 6 minutes in.
    static func nursing(now: Date = .now) -> WidgetSnapshot.BabySummary {
        var baby = resting(now: now)
        baby.runningNursing = .init(
            startedAt: now.addingTimeInterval(-9 * 60),
            leftSeconds: 3 * 60,
            rightSeconds: 0,
            activeSide: .right,
            activeSideStartedAt: now.addingTimeInterval(-6 * 60)
        )
        baby.lastFeed = .init(startedAt: now.addingTimeInterval(-9 * 60), kind: .breastfeed, detail: "L 3m · R 6m")
        return baby
    }

    static func sleeping(now: Date = .now) -> WidgetSnapshot.BabySummary {
        var baby = resting(now: now)
        baby.runningSleepStartedAt = now.addingTimeInterval(-34 * 60)
        return baby
    }
}
