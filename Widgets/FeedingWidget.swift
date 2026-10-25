import SwiftUI
import WidgetKit
import AppIntents
import BabyLogKit

struct FeedingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FeedingWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            FeedingWidgetView(entry: entry)
        }
        .configurationDisplayName("Feeding")
        .description("Time since the last feed and the next side. Start nursing with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FeedingWidgetView: View {
    let entry: BabyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let baby = entry.baby {
                switch family {
                case .systemMedium: MediumFeeding(baby: baby)
                default: SmallFeeding(baby: baby)
                }
            } else {
                EmptyWidgetView()
            }
        }
        .widgetBackground()
    }
}

// MARK: Shared info block

/// "Last feed" headline used by both sizes.
private struct FeedSummary: View {
    let baby: WidgetSnapshot.BabySummary
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let nursing = baby.runningNursing {
                let values = NursingValues(nursing)
                Text(values.isRunning ? "Nursing · \(values.activeSide?.title ?? "")" : "Nursing · paused")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(EventKind.breastfeed.color)
                    .widgetAccentable()
                NursingTotalClock(values: values)
                    .font(.system(size: compact ? 30 : 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                // A ticking timer Text stretches to the width it's offered, so give each side its own half.
                HStack(spacing: 4) {
                    ForEach(BreastSide.allCases) { side in
                        HStack(spacing: 4) {
                            Text(side.shortLabel)
                            NursingSideClock(values: values, side: side)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let feed = baby.lastFeed {
                Text("Last feed")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(feed.kind.color)
                    .widgetAccentable()
                AgoStack(date: feed.referenceDate)
                    .font(.system(size: compact ? 17 : 19, weight: .bold, design: .rounded))
                if !feed.detail.isEmpty {
                    Text(feed.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No feeds yet")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Small

private struct SmallFeeding: View {
    let baby: WidgetSnapshot.BabySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WidgetKindIcon(kind: .breastfeed, size: 22)
                    .widgetAccentable()
                Text(baby.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            FeedSummary(baby: baby, compact: true)
            Spacer(minLength: 4)
            if baby.isNursing {
                Text("Open to manage")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if let side = baby.nextSide {
                Text("Next: \(side.title)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(side.color.opacity(0.2)))
                    .foregroundStyle(side.color)
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(baby.isNursing ? DeepLink.nursing(babyID: baby.id).url : DeepLink.today(babyID: baby.id).url)
    }
}

// MARK: Medium

private struct MediumFeeding: View {
    let baby: WidgetSnapshot.BabySummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    WidgetKindIcon(kind: .breastfeed, size: 22)
                        .widgetAccentable()
                    Text(baby.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                FeedSummary(baby: baby)
                Spacer(minLength: 4)
                if !baby.isNursing, let side = baby.nextSide {
                    Text("Next: \(side.title)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(side.color)
                        .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            buttons
                .frame(maxWidth: .infinity)
        }
        .widgetURL(DeepLink.today(babyID: baby.id).url)
    }

    @ViewBuilder
    private var buttons: some View {
        if let nursing = baby.runningNursing {
            let values = NursingValues(nursing)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                            TileLabel(
                                title: side.title,
                                systemImage: values.activeSide == side ? "pause.fill" : "play.fill",
                                tint: side.color,
                                subtitle: DurationFormat.clock(values.banked(side)),
                                liveSince: values.sideReference(side),
                                filled: values.activeSide == side
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(intent: FinishNursingIntent(babyID: baby.id)) {
                    TileLabel(title: "Done", systemImage: "checkmark", tint: .green, filled: true)
                        .frame(maxHeight: 40)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                            TileLabel(
                                title: side.title,
                                systemImage: "play.fill",
                                tint: side.color,
                                filled: baby.nextSide == side,
                                badge: baby.nextSide == side ? "NEXT" : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Link(destination: DeepLink.log(.bottle, babyID: baby.id).url) {
                    TileLabel(title: "Bottle", systemImage: EventKind.bottle.symbolName, tint: EventKind.bottle.color)
                        .frame(maxHeight: 40)
                }
            }
        }
    }
}

#Preview("Small", as: .systemSmall) {
    FeedingWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
    BabyEntry.empty
}

#Preview("Medium", as: .systemMedium) {
    FeedingWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
    BabyEntry.empty
}
