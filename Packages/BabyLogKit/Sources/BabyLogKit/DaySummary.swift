import Foundation

public struct DaySummary: Equatable {
    /// Overlap of sleeps with the interval (overnight sleep is split across days; running sleep counts up to now).
    public var sleep: TimeInterval = 0
    /// Breastfeed + bottle events starting in the interval.
    public var feedCount: Int = 0
    public var nursing: TimeInterval = 0
    public var bottleML: Double = 0
    public var solidsCount: Int = 0
    public var diapers: [DiaperKind: Int] = [:]
    public var pumpML: Double = 0
    public var medicineCount: Int = 0

    public var diaperCount: Int { diapers.values.reduce(0, +) }
    /// Mixed counts as wet and dirty.
    public var wetCount: Int { diapers.filter { $0.key.isWet }.values.reduce(0, +) }
    public var dirtyCount: Int { diapers.filter { $0.key.isDirty }.values.reduce(0, +) }

    public init() {}

    public init<S: Sequence>(events: S, interval: DateInterval, now: Date = .now) where S.Element == LogEvent {
        for event in events {
            guard let start = event.startDate else { continue }
            let startsInInterval = start >= interval.start && start < interval.end
            switch event.kind {
            case .sleep:
                let end = event.endDate ?? now
                let from = max(start, interval.start)
                let to = min(end, interval.end)
                if to > from { sleep += to.timeIntervalSince(from) }
            case .breastfeed:
                if startsInInterval {
                    feedCount += 1
                    nursing += event.totalBreastSeconds(at: now)
                }
            case .bottle:
                if startsInInterval {
                    feedCount += 1
                    bottleML += event.amountML
                }
            case .solids:
                if startsInInterval { solidsCount += 1 }
            case .diaper:
                if startsInInterval, let kind = event.diaperKind { diapers[kind, default: 0] += 1 }
            case .pump:
                if startsInInterval { pumpML += event.leftML + event.rightML }
            case .medicine:
                if startsInInterval { medicineCount += 1 }
            case .growth:
                break
            }
        }
    }
}
