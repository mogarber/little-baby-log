import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents
import BabyLogKit

/// Lock Screen banner and Dynamic Island for a running sleep or nursing timer.
struct TimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerBanner(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
                .widgetURL(link(context.attributes))
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        WidgetKindIcon(kind: attributes.kind, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(attributes.babyName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(subtitle(attributes, state))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerClock(attributes: attributes, state: state)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .frame(maxWidth: 110, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerButtons(attributes: attributes, state: state)
                        .frame(height: 42)
                }
            } compactLeading: {
                Image(systemName: attributes.kind.symbolName)
                    .foregroundStyle(attributes.kind.color)
            } compactTrailing: {
                TimerClock(attributes: attributes, state: state)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 52, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: attributes.kind.symbolName)
                    .foregroundStyle(attributes.kind.color)
            }
            .widgetURL(link(attributes))
            .keylineTint(attributes.kind.color)
        }
    }

    private func link(_ attributes: TimerActivityAttributes) -> URL {
        let babyID = UUID(uuidString: attributes.babyID)
        return attributes.kind == .breastfeed ? DeepLink.nursing(babyID: babyID).url : DeepLink.today(babyID: babyID).url
    }

    private func subtitle(_ attributes: TimerActivityAttributes, _ state: TimerActivityAttributes.ContentState) -> String {
        guard attributes.kind == .breastfeed else { return "Sleeping" }
        let values = NursingValues(state)
        if let side = values.activeSide { return "Nursing · \(side.title)" }
        return "Nursing · paused"
    }
}

/// The live total: ticking while running, frozen when a nursing timer is paused.
private struct TimerClock: View {
    let attributes: TimerActivityAttributes
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        if attributes.kind == .breastfeed {
            NursingTotalClock(values: NursingValues(state))
        } else {
            LiveClock(reference: state.startedAt)
        }
    }
}

private struct TimerBanner: View {
    let attributes: TimerActivityAttributes
    let state: TimerActivityAttributes.ContentState

    private var values: NursingValues { NursingValues(state) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                WidgetKindIcon(kind: attributes.kind, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.babyName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(headline)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TimerClock(attributes: attributes, state: state)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            if attributes.kind == .breastfeed {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        HStack(spacing: 6) {
                            Text(side.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            NursingSideClock(values: values, side: side)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(values.activeSide == side ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            TimerButtons(attributes: attributes, state: state)
                .frame(height: 44)
        }
    }

    private var headline: String {
        guard attributes.kind == .breastfeed else { return "Sleeping since \(state.startedAt.formatted(date: .omitted, time: .shortened))" }
        if let side = values.activeSide { return "Nursing · \(side.title) side" }
        return "Nursing · paused"
    }
}

/// Nursing: Left / Right (switch or pause) + Done. Sleep: Wake up.
private struct TimerButtons: View {
    let attributes: TimerActivityAttributes
    let state: TimerActivityAttributes.ContentState

    private var babyID: UUID? { UUID(uuidString: attributes.babyID) }

    var body: some View {
        if let babyID {
            if attributes.kind == .breastfeed {
                let values = NursingValues(state)
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        Button(intent: NursingSideIntent(babyID: babyID, side: side)) {
                            TileLabel(
                                title: side.title,
                                systemImage: values.activeSide == side ? "pause.fill" : "play.fill",
                                tint: side.color,
                                filled: values.activeSide == side
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Button(intent: FinishNursingIntent(babyID: babyID)) {
                        TileLabel(title: "Done", systemImage: "checkmark", tint: .green, filled: true)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(intent: ToggleSleepIntent(babyID: babyID)) {
                    TileLabel(title: "Wake up", systemImage: "sun.max.fill", tint: .orange, filled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
