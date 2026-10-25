import SwiftUI
import WidgetKit
import BabyLogKit

struct BabyEntry: TimelineEntry {
    let date: Date
    /// The baby to show, resolved from the widget's configuration (nil: no babies yet).
    let baby: WidgetSnapshot.BabySummary?
    let volumeUnit: VolumeUnit
    /// When the app wrote the snapshot; counts for "today" are stale if that was a previous day.
    let generatedAt: Date?

    var babyID: UUID? { baby?.id }

    /// The nap window or bedtime, unless it closed more than an hour before this entry's date. The widget can't
    /// recompute anything, so a stale prediction disappears at its `expiresAt` through its own timeline entry.
    var nextSleep: WidgetSnapshot.NextSleep? {
        guard let prediction = baby?.nextSleep, prediction.expiresAt > date, !(baby?.isSleeping ?? false) else { return nil }
        return prediction
    }

    var nextFeed: WidgetSnapshot.NextFeed? {
        guard let prediction = baby?.nextFeed, prediction.expiresAt > date else { return nil }
        return prediction
    }

    /// Today's counts, or zeros when the snapshot is from an earlier day (the app hasn't run since midnight).
    var today: WidgetSnapshot.Today {
        guard let baby else { return .init() }
        guard let generatedAt, Calendar.current.isDate(generatedAt, inSameDayAs: date) else { return .init() }
        return baby.today
    }

    static func sample(date: Date = .now, _ baby: WidgetSnapshot.BabySummary = SampleSnapshot.resting(now: .now)) -> BabyEntry {
        BabyEntry(date: date, baby: baby, volumeUnit: .milliliters, generatedAt: date)
    }

    static var empty: BabyEntry {
        BabyEntry(date: .now, baby: nil, volumeUnit: .milliliters, generatedAt: nil)
    }
}

/// Reads the snapshot the app wrote and picks the configured baby. The widget never touches Core Data;
/// clocks tick via `Text(timerInterval:)` / `.relative`, so one entry is enough.
struct BabyTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = BabyEntry
    typealias Intent = SelectBabyIntent

    func placeholder(in context: Context) -> BabyEntry {
        .sample()
    }

    func snapshot(for configuration: SelectBabyIntent, in context: Context) async -> BabyEntry {
        let entry = load(configuration)
        if context.isPreview && entry.baby == nil { return .sample() }
        return entry
    }

    /// Battery: the policy is `.never`. Every time on screen updates itself (`Text(date, style: .relative)`,
    /// `Text(timerInterval:)`), and the app calls `reloadAllTimelines()` only when the snapshot really changed.
    /// The one extra entry is for midnight, when "today" counts roll over; it reuses the same data and costs
    /// no wake-up. Predictions work the same way: they are stored as absolute times, and one more entry is added
    /// where each of them stops being worth showing.
    func timeline(for configuration: SelectBabyIntent, in context: Context) async -> Timeline<BabyEntry> {
        let first = load(configuration)
        var changeDates: [Date] = []
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: first.date)) {
            changeDates.append(midnight)
        }
        if let expiry = first.baby?.nextSleep?.expiresAt { changeDates.append(expiry) }
        if let expiry = first.baby?.nextFeed?.expiresAt { changeDates.append(expiry) }

        var entries = [first]
        for date in Set(changeDates).sorted() where date > first.date {
            entries.append(BabyEntry(date: date, baby: first.baby, volumeUnit: first.volumeUnit, generatedAt: first.generatedAt))
        }
        return Timeline(entries: entries, policy: .never)
    }

    private func load(_ configuration: SelectBabyIntent) -> BabyEntry {
        guard let url = AppGroup.snapshotURL, let snapshot = WidgetSnapshot.read(from: url) else { return .empty }
        let baby = snapshot.baby(id: configuration.baby?.uuid)
        return BabyEntry(date: .now, baby: baby, volumeUnit: snapshot.volumeUnit, generatedAt: snapshot.generatedAt)
    }
}
