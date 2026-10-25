import SwiftUI
import WidgetKit
import BabyLogKit

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LockScreenWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Last Feed")
        .description("Time since the last feed and the next side, or the live nursing clock.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    let entry: BabyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let baby = entry.baby {
                switch family {
                case .accessoryCircular: Circular(baby: baby)
                case .accessoryInline: Inline(baby: baby)
                default: Rectangular(baby: baby)
                }
            } else {
                switch family {
                case .accessoryInline: Text("Open Little Baby Log")
                default:
                    VStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                        Text("Add your baby")
                            .font(.caption2)
                    }
                }
            }
        }
        .widgetURL(DeepLink.today(babyID: entry.babyID).url)
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct Circular: View {
    let baby: WidgetSnapshot.BabySummary

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: baby.isNursing ? "heart.fill" : "clock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                if let nursing = baby.runningNursing {
                    NursingTotalClock(values: NursingValues(nursing))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else if let feed = baby.lastFeed {
                    // h:mm:ss counting up from the end of the last feed.
                    Text(feed.referenceDate, style: .timer)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .frame(maxWidth: 46)
                } else {
                    Text("--")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

private struct Rectangular: View {
    let baby: WidgetSnapshot.BabySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let nursing = baby.runningNursing {
                let values = NursingValues(nursing)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").widgetAccentable()
                    Text(values.activeSide.map { "Nursing \($0.shortLabel)" } ?? "Nursing paused")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                NursingTotalClock(values: values)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(BreastSide.allCases) { side in
                        HStack(spacing: 3) {
                            Text(side.shortLabel)
                            NursingSideClock(values: values, side: side)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2)
            } else if let feed = baby.lastFeed {
                HStack(spacing: 4) {
                    Image(systemName: feed.kind.symbolName).widgetAccentable()
                    Text(baby.name).fontWeight(.semibold).lineLimit(1)
                }
                .font(.headline)
                Text("Fed \(Elapsed.since(feed.referenceDate)) ago")
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let side = baby.nextSide {
                    Text("Next: \(side.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !feed.detail.isEmpty {
                    Text(feed.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(baby.name).font(.headline)
                Text("No feeds yet").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Inline: View {
    let baby: WidgetSnapshot.BabySummary

    var body: some View {
        if let nursing = baby.runningNursing {
            let values = NursingValues(nursing)
            Label {
                Text("Nursing \(values.activeSide?.shortLabel ?? "paused") \(values.totalText)")
            } icon: {
                Image(systemName: "heart.fill")
            }
        } else if let feed = baby.lastFeed {
            Label {
                Text("Fed \(Elapsed.since(feed.referenceDate)) ago\(baby.nextSide.map { " · next \($0.shortLabel)" } ?? "")")
            } icon: {
                Image(systemName: "heart.fill")
            }
        } else {
            Text("No feeds yet")
        }
    }
}

#Preview("Circular", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
}
