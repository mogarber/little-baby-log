import Foundation

/// Predicts when the baby will next fall asleep: a nap window, or bedtime.
///
/// The idea is the one parents use by hand: *wake window* = how long the baby can comfortably stay awake. We
/// start from typical wake windows for the baby's age, then lean more and more on this baby's own last 14 days.
///
/// 1. **Wake windows** are the gaps between a sleep ending and the next one starting, grouped by position in the
///    day (morning wake -> 1st nap, 1st -> 2nd nap, ...) and, separately, the last gap before night sleep.
///    Gaps outside 0.5x-2x of the age range are dropped as bad logs. Each group's median is used.
/// 2. **Blend**: personal weight = `min(1, samples / 10)` (0 under 3 samples). The expected gap is
///    `weight x own median + (1 - weight) x middle of the age range`, clamped to the age range widened by 25%.
///    The window is that time after the last wake-up, +/- 15 minutes (+/- 10 under 8 weeks).
/// 3. **Nap or bedtime?** Bedtime when the nap would start within 90 minutes of the baby's usual bedtime
///    (median of the last 7 evenings, else a typical one for the age), or when today's naps have reached the
///    number this baby takes (their own median, else the age's maximum). The bedtime window is centred on a
///    mix of the usual bedtime and the wake-window rule.
/// 4. Nothing is predicted while a sleep is running, or during a night waking.
public enum SleepPredictor {
    /// How long past the end of its window a prediction is still shown (as "overdue") before it is considered
    /// stale: the log is probably missing a sleep, so the next window is counted from now instead.
    static let staleAfter: TimeInterval = 60 * 60
    /// A nap is bedtime if it would start this close to (or after) the usual bedtime.
    static let bedtimeLead: TimeInterval = 90 * 60
    /// How much of a bedtime window's centre comes from the usual bedtime rather than the wake-window rule.
    static let personalBedtimeShare = 0.5
    static let typicalBedtimeShare = 0.25

    /// nil while the baby is asleep (running sleep), during a night waking, or when the next window has
    /// already passed with nothing useful to say. With no usable wake-up (nothing logged, or an old log) the
    /// window counts from now and is labeled `typicalForAge`.
    public static func next(birthDate: Date, sleeps: [SleepSession], now: Date, calendar: Calendar) -> SleepPrediction? {
        let ageDays = AgeNorms.ageDays(birthDate: birthDate, now: now, calendar: calendar)
        let history = SleepHistory(sleeps: sleeps, ageDays: ageDays, now: now, calendar: calendar)
        guard !history.isSleeping else { return nil }

        let context = Context(history: history, ageDays: ageDays, now: now, calendar: calendar)
        if context.isNightWaking { return nil }

        if let wake = context.lastWake, let prediction = context.predict(anchor: wake), !context.isStale(prediction) {
            return prediction
        }
        guard let fallback = context.predict(anchor: nil), !context.isStale(fallback) else { return nil }
        return fallback
    }

    // MARK: Internals

    struct Context {
        let history: SleepHistory
        let ageDays: Int
        let now: Date
        let calendar: Calendar

        var lastSession: SleepHistory.Session? { history.sessions.last }

        /// The end of the latest sleep, unless it is too old to count as "the last wake-up".
        var lastWake: Date? {
            guard let end = lastSession?.end, now.timeIntervalSince(end) < 24 * 3600 else { return nil }
            return end
        }

        /// Awake in the middle of the night, between night sleeps.
        var isNightWaking: Bool {
            guard let last = lastSession, last.isNight, now.timeIntervalSince(last.end) < 6 * 3600 else { return false }
            return Self.isNightHour(PredictionMath.minuteOfDay(last.end, calendar: calendar))
                && Self.isNightHour(PredictionMath.minuteOfDay(now, calendar: calendar))
        }

        private static func isNightHour(_ minute: Int) -> Bool {
            minute >= SleepHistory.eveningStart || minute < SleepHistory.nightEnd
        }

        func isStale(_ prediction: SleepPrediction) -> Bool {
            now.timeIntervalSince(prediction.window.end) > SleepPredictor.staleAfter
        }

        /// Daytime sleeps already logged today.
        var napsToday: Int {
            let startOfDay = calendar.startOfDay(for: now)
            return history.sessions.filter { !$0.isNight && $0.start >= startOfDay }.count
        }

        var napCap: Int {
            history.personalNapCount ?? AgeNorms.napsPerDay(ageDays: ageDays).upperBound
        }

        /// The usual bedtime on today's calendar day, and whether it comes from this baby's logs.
        var bedtimeToday: (date: Date, isPersonal: Bool)? {
            if let minute = history.medianBedtime {
                return (PredictionMath.date(atMinuteOfDay: minute, on: now, calendar: calendar), true)
            }
            if let minute = AgeNorms.typicalBedtime(ageDays: ageDays) {
                return (PredictionMath.date(atMinuteOfDay: minute, on: now, calendar: calendar), false)
            }
            return nil
        }

        struct Estimate {
            var gap: TimeInterval
            var samples: Int
            var days: Int
        }

        /// Expected wake window before the next nap, by position in the day. Falls back to all of the baby's
        /// daytime windows when this position has fewer than 3 samples.
        func napEstimate(position: Int) -> Estimate {
            let norm = AgeNorms.wakeWindow(ageDays: ageDays)
            var chosen = history.napGaps.filter { $0.position == position }
            if chosen.count < PredictionMath.minimumSamples { chosen = history.napGaps }
            return estimate(durations: chosen.map(\.duration), starts: chosen.map(\.start), norm: norm)
        }

        func bedEstimate() -> Estimate {
            let norm = AgeNorms.wakeWindow(ageDays: ageDays)
            var result = estimate(durations: history.bedGaps.map(\.duration), starts: history.bedGaps.map(\.start), norm: norm)
            // A steady bedtime is evidence too, even when the wake-up before it was not logged.
            if history.bedtimes.count > result.samples {
                result.samples = history.bedtimes.count
                result.days = PredictionMath.distinctDays(history.bedtimes.map(\.start), calendar: calendar)
            }
            return result
        }

        private func estimate(durations: [TimeInterval], starts: [Date], norm: ClosedRange<TimeInterval>) -> Estimate {
            let gap = PredictionMath.blend(
                personalMedian: PredictionMath.median(durations),
                samples: durations.count,
                norm: norm
            )
            return Estimate(gap: gap, samples: durations.count, days: PredictionMath.distinctDays(starts, calendar: calendar))
        }

        /// `anchor` is the last wake-up; nil counts from now with the age norms alone.
        func predict(anchor: Date?) -> SleepPrediction? {
            let from = anchor ?? now
            let position = napsToday + 1
            let norm = AgeNorms.wakeWindow(ageDays: ageDays)

            let nap = anchor == nil
                ? Estimate(gap: PredictionMath.blend(personalMedian: nil, samples: 0, norm: norm), samples: 0, days: 0)
                : napEstimate(position: position)
            let napStart = from.addingTimeInterval(nap.gap)

            let bedtime = bedtimeToday
            let comesDownToBedtime = napsToday >= napCap
                || (bedtime.map { napStart >= $0.date.addingTimeInterval(-SleepPredictor.bedtimeLead) } ?? false)

            guard comesDownToBedtime else {
                return SleepPrediction(
                    kind: .nap,
                    window: PredictionMath.window(centre: napStart, ageDays: ageDays),
                    basis: PredictionMath.basis(samples: nap.samples, days: nap.days),
                    lastWake: anchor
                )
            }

            let bed = anchor == nil
                ? Estimate(gap: PredictionMath.blend(personalMedian: nil, samples: 0, norm: norm), samples: 0, days: 0)
                : bedEstimate()
            let byWakeWindow = from.addingTimeInterval(bed.gap)
            let centre: Date
            switch (anchor, bedtime) {
            case (nil, let bedtime?):
                centre = bedtime.date
            case (_, let bedtime?):
                let share = bedtime.isPersonal ? SleepPredictor.personalBedtimeShare : SleepPredictor.typicalBedtimeShare
                let seconds = share * bedtime.date.timeIntervalSince(byWakeWindow)
                centre = byWakeWindow.addingTimeInterval(seconds)
            default:
                centre = byWakeWindow
            }
            return SleepPrediction(
                kind: .bedtime,
                window: PredictionMath.window(centre: centre, ageDays: ageDays),
                basis: PredictionMath.basis(samples: bed.samples, days: bed.days),
                lastWake: anchor
            )
        }
    }
}
