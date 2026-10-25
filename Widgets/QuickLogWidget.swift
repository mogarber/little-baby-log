import SwiftUI
import WidgetKit
import AppIntents
import BabyLogKit

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickLogWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("One-tap buttons for nursing, sleep, and diapers.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct QuickLogWidgetView: View {
    let entry: BabyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let baby = entry.baby {
                content(baby)
            } else {
                EmptyWidgetView()
            }
        }
        .widgetBackground()
    }

    private func content(_ baby: WidgetSnapshot.BabySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(baby)
            if family == .systemLarge {
                details(baby)
            }
            grid(baby)
        }
        .widgetURL(DeepLink.today(babyID: baby.id).url)
    }

    private func header(_ baby: WidgetSnapshot.BabySummary) -> some View {
        HStack(spacing: 6) {
            Text(baby.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let nursing = baby.runningNursing {
                let values = NursingValues(nursing)
                Label {
                    NursingTotalClock(values: values)
                } icon: {
                    Image(systemName: EventKind.breastfeed.symbolName)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(EventKind.breastfeed.color)
                .widgetAccentable()
            } else if let started = baby.runningSleepStartedAt {
                Label {
                    Elapsed.since(started)
                } icon: {
                    Image(systemName: EventKind.sleep.symbolName)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(EventKind.sleep.color)
                .lineLimit(1)
                .widgetAccentable()
            } else if let feed = baby.lastFeed {
                AgoLine(prefix: "Fed", date: feed.referenceDate)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Large only: last feed, last diaper, and today's totals.
    private func details(_ baby: WidgetSnapshot.BabySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(
                kind: baby.lastFeed?.kind ?? .breastfeed,
                title: baby.isNursing ? "Nursing now" : "Last feed",
                date: baby.isNursing ? nil : baby.lastFeed?.referenceDate,
                detail: [baby.lastFeed?.detail, baby.nextSide.map { "Next: \($0.title)" }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            )
            detailRow(
                kind: .diaper,
                title: "Last diaper",
                date: baby.lastDiaperAt,
                detail: baby.lastDiaperKind?.title ?? ""
            )
            let today = entry.today
            HStack(spacing: 14) {
                stat("\(today.feeds)", "feeds")
                stat("\(today.diapers)", "diapers")
                stat(DurationFormat.short(today.sleep), "sleep")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(kind: EventKind, title: String, date: Date?, detail: String) -> some View {
        HStack(spacing: 10) {
            WidgetKindIcon(kind: kind, size: 30)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                if let date {
                    AgoLine(date: date)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                } else {
                    Text(title == "Nursing now" ? "In progress" : "None yet")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            Spacer(minLength: 6)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    // MARK: Buttons

    private func grid(_ baby: WidgetSnapshot.BabySummary) -> some View {
        let values = baby.runningNursing.map(NursingValues.init)
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(BreastSide.allCases) { side in
                    Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                        TileLabel(
                            title: "Nurse \(side.shortLabel)",
                            systemImage: values?.activeSide == side ? "pause.fill" : EventKind.breastfeed.symbolName,
                            tint: side.color,
                            filled: values?.activeSide == side || (values == nil && baby.nextSide == side)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button(intent: ToggleSleepIntent(babyID: baby.id)) {
                    TileLabel(
                        title: baby.isSleeping ? "Wake up" : "Sleep",
                        systemImage: baby.isSleeping ? "sun.max.fill" : EventKind.sleep.symbolName,
                        tint: baby.isSleeping ? .orange : EventKind.sleep.color,
                        filled: baby.isSleeping
                    )
                }
                .buttonStyle(.plain)
            }
            GridRow {
                Button(intent: LogDiaperIntent(babyID: baby.id, kind: .wet)) {
                    TileLabel(title: "Wet", systemImage: DiaperKind.wet.symbolName, tint: EventKind.diaper.color)
                }
                .buttonStyle(.plain)
                Button(intent: LogDiaperIntent(babyID: baby.id, kind: .dirty)) {
                    TileLabel(title: "Dirty", systemImage: DiaperKind.dirty.symbolName, tint: .brown)
                }
                .buttonStyle(.plain)
                Link(destination: DeepLink.log(.bottle, babyID: baby.id).url) {
                    TileLabel(title: "Bottle", systemImage: EventKind.bottle.symbolName, tint: EventKind.bottle.color)
                }
            }
        }
        .frame(maxHeight: family == .systemLarge ? 150 : .infinity)
    }
}

#Preview("Medium", as: .systemMedium) {
    QuickLogWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
}

#Preview("Large", as: .systemLarge) {
    QuickLogWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.sleeping())
}
