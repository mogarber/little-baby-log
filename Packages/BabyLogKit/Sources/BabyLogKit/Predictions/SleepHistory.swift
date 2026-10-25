import Foundation

/// A baby's recent sleep log, cleaned up and split into the pieces the predictor needs: wake-window samples
/// by position in the day, the gaps before night sleep, bedtimes, and naps per day.
///
/// Day structure (all in the caller's calendar, so DST shifts are harmless):
/// - A **night sleep** starts between 17:30 and midnight and lasts at least `AgeNorms.minimumNightSleep`, or
///   starts between midnight and 05:30. A sleep that crosses midnight is one session, so it works as is.
/// - The **morning wake** is the end of a night sleep that ends between 04:00 and 11:00. Everything after it,
///   up to the next night sleep, is the baby's day.
/// - Gaps between two night sleeps are night wakings, not wake windows, and are ignored.
struct SleepHistory {
    struct Session: Equatable {
        var start: Date
        var end: Date
        var isNight: Bool

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// A wake window that ended in a nap. `position` is 1 for morning wake -> first nap, 2 for the next, ...
    struct NapGap: Equatable {
        var start: Date
        var duration: TimeInterval
        var position: Int
    }

    /// A wake window that ended in night sleep.
    struct BedGap: Equatable {
        var start: Date
        var duration: TimeInterval
    }

    /// Finished sessions in the last 14 days, oldest first.
    var sessions: [Session] = []
    /// A sleep is in progress (or its end is in the future).
    var isSleeping = false
    var napGaps: [NapGap] = []
    var bedGaps: [BedGap] = []
    /// Gaps thrown away by the outlier rule.
    var droppedGaps = 0
    /// Bedtimes (start of the first night sleep of an evening) in the last 7 days, as minutes after midnight.
    var bedtimes: [(start: Date, minuteOfDay: Int)] = []
    /// Naps per day for up to 7 recent complete days that have any sleep logged.
    var napsPerDay: [Int] = []

    static let historyDays = 14
    static let bedtimeDays = 7

    /// Short "sleeps" (an accidental tap) are ignored; two sleeps closer together than this are one sleep (the
    /// baby woke for a moment and was settled again).
    static let minimumSleep: TimeInterval = 10 * 60
    static let mergeGap: TimeInterval = 15 * 60

    static let eveningStart = 17 * 60 + 30
    static let nightEnd = 5 * 60 + 30
    static let morningWakeRange = (4 * 60)..<(11 * 60)

    init(sleeps: [SleepSession], ageDays: Int, now: Date, calendar: Calendar) {
        let earliest = now.addingTimeInterval(-TimeInterval(Self.historyDays) * 86_400)

        var finished: [(start: Date, end: Date)] = []
        for sleep in sleeps {
            guard sleep.start <= now else { continue }
            guard let end = sleep.end else { isSleeping = true; continue }
            if end > now { isSleeping = true; continue }
            guard end > sleep.start, end >= earliest else { continue }
            finished.append((sleep.start, end))
        }
        finished.sort { $0.start < $1.start }

        var merged: [(start: Date, end: Date)] = []
        for item in finished {
            if let last = merged.last, item.start.timeIntervalSince(last.end) < Self.mergeGap {
                merged[merged.count - 1].end = max(last.end, item.end)
            } else {
                merged.append(item)
            }
        }

        let minimumNight = AgeNorms.minimumNightSleep(ageDays: ageDays)
        sessions = merged
            .filter { $0.end.timeIntervalSince($0.start) >= Self.minimumSleep }
            .map { item in
                let minute = PredictionMath.minuteOfDay(item.start, calendar: calendar)
                let length = item.end.timeIntervalSince(item.start)
                let night = minute < Self.nightEnd || (minute >= Self.eveningStart && length >= minimumNight)
                return Session(start: item.start, end: item.end, isNight: night)
            }

        analyze(ageDays: ageDays, now: now, calendar: calendar)
    }

    private mutating func analyze(ageDays: Int, now: Date, calendar: Calendar) {
        let norm = AgeNorms.wakeWindow(ageDays: ageDays)
        var napIndex: Int?   // nil until the first morning wake in the log

        func isMorningWake(_ session: Session) -> Bool {
            Self.morningWakeRange.contains(PredictionMath.minuteOfDay(session.end, calendar: calendar))
        }

        for (index, session) in sessions.enumerated() {
            let previous = index > 0 ? sessions[index - 1] : nil

            // Bedtime: the first night sleep after a day (or after a night that ended in the morning).
            if session.isNight,
               PredictionMath.minuteOfDay(session.start, calendar: calendar) >= Self.eveningStart,
               previous.map({ !$0.isNight || isMorningWake($0) }) ?? true,
               session.start >= now.addingTimeInterval(-TimeInterval(Self.bedtimeDays) * 86_400) {
                bedtimes.append((session.start, PredictionMath.minuteOfDay(session.start, calendar: calendar)))
            }

            guard let previous else { continue }
            let gap = session.start.timeIntervalSince(previous.end)
            guard gap > 0 else { continue }

            switch (previous.isNight, session.isNight) {
            case (true, true):
                continue   // a night waking
            case (true, false):
                guard isMorningWake(previous) else { napIndex = nil; continue }
                napIndex = 1
                record(nap: gap, at: previous.end, position: 1, norm: norm)
            case (false, false):
                guard let current = napIndex else { continue }
                napIndex = current + 1
                record(nap: gap, at: previous.end, position: current + 1, norm: norm)
            case (false, true):
                if PredictionMath.isPlausible(gap, norm: norm) {
                    bedGaps.append(BedGap(start: previous.end, duration: gap))
                } else {
                    droppedGaps += 1
                }
                napIndex = nil
            }
        }

        // A "bad log" in the middle of a day (an implausible gap) still advances the position counter above,
        // because a missed nap is a missed nap; only its duration is left out of the samples.
        napsPerDay = Self.napCounts(sessions: sessions, now: now, calendar: calendar)
    }

    private mutating func record(nap gap: TimeInterval, at start: Date, position: Int, norm: ClosedRange<TimeInterval>) {
        if PredictionMath.isPlausible(gap, norm: norm) {
            napGaps.append(NapGap(start: start, duration: gap, position: position))
        } else {
            droppedGaps += 1
        }
    }

    /// Daytime sleeps per day for the last 7 complete days that have any sleep logged at all.
    private static func napCounts(sessions: [Session], now: Date, calendar: Calendar) -> [Int] {
        let today = calendar.startOfDay(for: now)
        var perDay: [Date: (naps: Int, any: Bool)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.start)
            guard day < today else { continue }
            var entry = perDay[day] ?? (0, false)
            entry.any = true
            if !session.isNight { entry.naps += 1 }
            perDay[day] = entry
        }
        let recent = perDay.keys.sorted().suffix(7)
        return recent.compactMap { perDay[$0] }.filter(\.any).map(\.naps)
    }

    /// The median bedtime in minutes after midnight, if at least `minimumSamples` nights back it up.
    var medianBedtime: Int? {
        guard bedtimes.count >= PredictionMath.minimumSamples else { return nil }
        return PredictionMath.median(bedtimes.map { Double($0.minuteOfDay) }).map { Int($0.rounded()) }
    }

    /// How many naps a day this baby really takes, if there are at least 3 days of logs to say.
    var personalNapCount: Int? {
        guard napsPerDay.count >= PredictionMath.minimumSamples else { return nil }
        return napsPerDay.sorted()[napsPerDay.count / 2]
    }
}
