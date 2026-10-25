import SwiftUI
import CoreData
import BabyLogKit

/// Sleep / feeds / diapers / pumped totals for one day.
struct DaySummaryView: View {
    let events: [LogEvent]
    let day: Date

    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @Environment(\.managedObjectContext) private var context
    @State private var changeTick = 0

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let _ = changeTick
            grid(summary: summary(now: timeline.date))
        }
        .onContextChange(context) { changeTick += 1 }
    }

    private func summary(now: Date) -> DaySummary {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return DaySummary(events: events, interval: DateInterval(start: day, end: end), now: now)
    }

    private func grid(summary s: DaySummary) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatCell(
                kind: .sleep,
                value: DurationFormat.short(s.sleep),
                label: "Sleep",
                detail: nil
            )
            StatCell(
                kind: .breastfeed,
                value: "\(s.feedCount)",
                label: s.feedCount == 1 ? "Feed" : "Feeds",
                detail: s.bottleML > 0 ? volumeUnit.format(milliliters: s.bottleML) + " bottle" : nil
            )
            StatCell(
                kind: .diaper,
                value: "\(s.diaperCount)",
                label: s.diaperCount == 1 ? "Diaper" : "Diapers",
                detail: s.diaperCount > 0 ? "\(s.wetCount) wet · \(s.dirtyCount) dirty" : nil
            )
            StatCell(
                kind: .pump,
                value: s.pumpML > 0 ? volumeUnit.format(milliliters: s.pumpML) : "0",
                label: "Pumped",
                detail: nil
            )
        }
        .padding(.vertical, 4)
    }
}

private struct StatCell: View {
    let kind: EventKind
    let value: String
    let label: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            KindIcon(kind: kind, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        DaySummaryView(events: [], day: Calendar.current.startOfDay(for: .now))
    }
    .previewEnvironment()
}
