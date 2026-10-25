import CoreData
import Foundation

/// Everything the Home Screen / Lock Screen widgets need, as plain values.
///
/// The app is the only process that opens Core Data. After every save it builds one of these for every
/// baby and writes it as JSON into the App Group container; the widget extension only ever reads the JSON.
/// Times are absolute dates so the widget can render live clocks (`Text(timerInterval:)`, `.relative`)
/// without being reloaded.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "widget-snapshot.json"

    public var generatedAt: Date
    /// The app's current baby; the default for widgets that aren't configured for a specific baby.
    public var selectedBabyID: UUID?
    public var volumeUnit: VolumeUnit
    public var babies: [BabySummary]

    public init(
        generatedAt: Date = .now,
        selectedBabyID: UUID? = nil,
        volumeUnit: VolumeUnit = .milliliters,
        babies: [BabySummary] = []
    ) {
        self.generatedAt = generatedAt
        self.selectedBabyID = selectedBabyID
        self.volumeUnit = volumeUnit
        self.babies = babies
    }

    public struct BabySummary: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        /// Latest breastfeed or bottle (finished or running).
        public var lastFeed: Feed?
        /// The other side of the latest finished nursing session.
        public var nextSide: BreastSide?
        public var lastDiaperAt: Date?
        public var lastDiaperKind: DiaperKind?
        /// End of the latest finished sleep.
        public var lastSleepEndedAt: Date?
        public var runningSleepStartedAt: Date?
        public var runningNursing: Nursing?
        public var today: Today

        public init(
            id: UUID,
            name: String,
            lastFeed: Feed? = nil,
            nextSide: BreastSide? = nil,
            lastDiaperAt: Date? = nil,
            lastDiaperKind: DiaperKind? = nil,
            lastSleepEndedAt: Date? = nil,
            runningSleepStartedAt: Date? = nil,
            runningNursing: Nursing? = nil,
            today: Today = Today()
        ) {
            self.id = id
            self.name = name
            self.lastFeed = lastFeed
            self.nextSide = nextSide
            self.lastDiaperAt = lastDiaperAt
            self.lastDiaperKind = lastDiaperKind
            self.lastSleepEndedAt = lastSleepEndedAt
            self.runningSleepStartedAt = runningSleepStartedAt
            self.runningNursing = runningNursing
            self.today = today
        }
    }

    public struct Feed: Codable, Equatable, Sendable {
        public var startedAt: Date
        public var kind: EventKind
        /// Via `EventDescriber`, e.g. "L 8m · R 6m" or "120 ml formula".
        public var detail: String
        /// When the feed finished; nil while a nursing timer is running. "Fed 2h ago" counts from here
        /// (like the Today screen does), falling back to `startedAt`.
        public var endedAt: Date?

        public init(startedAt: Date, kind: EventKind, detail: String, endedAt: Date? = nil) {
            self.startedAt = startedAt
            self.kind = kind
            self.detail = detail
            self.endedAt = endedAt
        }

        /// The moment "time since the last feed" counts from.
        public var referenceDate: Date { endedAt ?? startedAt }
    }

    public struct Nursing: Codable, Equatable, Sendable {
        public var startedAt: Date
        /// Banked (paused) seconds per side.
        public var leftSeconds: TimeInterval
        public var rightSeconds: TimeInterval
        public var activeSide: BreastSide?
        public var activeSideStartedAt: Date?

        public init(
            startedAt: Date,
            leftSeconds: TimeInterval = 0,
            rightSeconds: TimeInterval = 0,
            activeSide: BreastSide? = nil,
            activeSideStartedAt: Date? = nil
        ) {
            self.startedAt = startedAt
            self.leftSeconds = leftSeconds
            self.rightSeconds = rightSeconds
            self.activeSide = activeSide
            self.activeSideStartedAt = activeSideStartedAt
        }

        public func seconds(_ side: BreastSide, at now: Date) -> TimeInterval {
            var seconds = side == .left ? leftSeconds : rightSeconds
            if activeSide == side, let started = activeSideStartedAt {
                seconds += max(0, now.timeIntervalSince(started))
            }
            return seconds
        }

        public func total(at now: Date) -> TimeInterval {
            seconds(.left, at: now) + seconds(.right, at: now)
        }

        /// `Text(timerInterval: referenceStart...end)` shows the live total, but only while a side is
        /// active. Paused timers have no reference (show `total(at:)` as static text instead).
        public var liveTotalReferenceStart: Date? {
            guard activeSide != nil, let started = activeSideStartedAt else { return nil }
            return started.addingTimeInterval(-(leftSeconds + rightSeconds))
        }
    }

    public struct Today: Codable, Equatable, Sendable {
        public var feeds: Int
        public var diapers: Int
        public var sleep: TimeInterval

        public init(feeds: Int = 0, diapers: Int = 0, sleep: TimeInterval = 0) {
            self.feeds = feeds
            self.diapers = diapers
            self.sleep = sleep
        }
    }

    // MARK: Lookup

    /// The baby a widget should show: the configured one, else the app's current one, else the first.
    public func baby(id: UUID?) -> BabySummary? {
        if let id, let match = babies.first(where: { $0.id == id }) { return match }
        if let selectedBabyID, let match = babies.first(where: { $0.id == selectedBabyID }) { return match }
        return babies.first
    }

    /// Equal apart from `generatedAt`; used to skip rewriting the file and reloading timelines.
    public func isEquivalent(to other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        return copy == self
    }

    // MARK: Building

    /// Builds a snapshot from the store. Safe to call from any thread: fetching runs on `context`'s queue,
    /// and `babies` must belong to `context`.
    public static func make(
        babies: [Baby],
        context: NSManagedObjectContext,
        selectedBabyID: UUID?,
        volumeUnit: VolumeUnit,
        unitSystem: UnitSystem,
        now: Date = .now
    ) -> WidgetSnapshot {
        let describer = EventDescriber(volumeUnit: volumeUnit, unitSystem: unitSystem)
        var summaries: [BabySummary] = []
        context.performAndWait {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
            let today = DateInterval(start: startOfDay, end: max(endOfDay, startOfDay))

            for baby in babies where !baby.isDeleted {
                guard let id = baby.uuid else { continue }

                func first(_ request: NSFetchRequest<LogEvent>) -> LogEvent? {
                    (try? context.fetch(request))?.first
                }

                var summary = BabySummary(id: id, name: baby.displayName)

                if let feed = first(LogEvent.requestLatest(baby: baby, kinds: [.breastfeed, .bottle])),
                   let start = feed.startDate {
                    summary.lastFeed = Feed(
                        startedAt: start,
                        kind: feed.kind,
                        detail: describer.summary(for: feed, now: now),
                        endedAt: feed.endDate
                    )
                }
                summary.nextSide = first(LogEvent.requestLatest(baby: baby, kinds: [.breastfeed], finishedOnly: true))?
                    .lastSide?.other

                if let diaper = first(LogEvent.requestLatest(baby: baby, kinds: [.diaper])) {
                    summary.lastDiaperAt = diaper.startDate
                    summary.lastDiaperKind = diaper.diaperKind
                }
                summary.lastSleepEndedAt = first(LogEvent.requestLatest(baby: baby, kinds: [.sleep], finishedOnly: true))?.endDate

                let running = (try? context.fetch(LogEvent.requestRunning(baby: baby))) ?? []
                if let sleep = running.first(where: { $0.kind == .sleep }) {
                    summary.runningSleepStartedAt = sleep.startDate
                }
                if let nursing = running.first(where: { $0.kind == .breastfeed }), let start = nursing.startDate {
                    summary.runningNursing = Nursing(
                        startedAt: start,
                        leftSeconds: nursing.leftSeconds,
                        rightSeconds: nursing.rightSeconds,
                        activeSide: nursing.activeSide,
                        activeSideStartedAt: nursing.activeSideStartedAt
                    )
                }

                let events = (try? context.fetch(LogEvent.requestOverlapping(baby: baby, from: startOfDay))) ?? []
                let day = DaySummary(events: events, interval: today, now: now)
                summary.today = Today(feeds: day.feedCount, diapers: day.diaperCount, sleep: day.sleep)

                summaries.append(summary)
            }
        }
        return WidgetSnapshot(
            generatedAt: now,
            selectedBabyID: selectedBabyID,
            volumeUnit: volumeUnit,
            babies: summaries
        )
    }

    // MARK: File I/O

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// nil when the file is missing or unreadable.
    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Atomic, so a widget never sees a half-written file.
    public func write(to url: URL) throws {
        let data = try Self.encoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
