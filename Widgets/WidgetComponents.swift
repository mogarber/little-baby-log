import SwiftUI
import WidgetKit
import BabyLogKit

// MARK: Live clocks

/// Counts up from `reference` without any timeline reloads. The upper bound only needs to be far away.
///
/// On a dimmed, Always-On Lock Screen (`isLuminanceReduced`) iOS stops ticking live timers once a second and
/// draws their seconds as dashes ("1:--"). So in that state this shows the elapsed time in whole minutes instead,
/// which the system keeps current by itself (`Elapsed`).
struct LiveClock: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let reference: Date
    var showsHours = true

    var body: some View {
        if isLuminanceReduced {
            Elapsed.since(reference)
        } else {
            Text.live(since: reference, showsHours: showsHours)
        }
    }
}

extension Text {
    static func live(since reference: Date, showsHours: Bool = true) -> Text {
        Text(timerInterval: reference...reference.addingTimeInterval(24 * 3600), countsDown: false, showsHours: showsHours)
            .monospacedDigit()
    }
}

/// The times of a nursing session, from either the widget snapshot or a Live Activity's state.
struct NursingValues: Equatable {
    var leftSeconds: TimeInterval
    var rightSeconds: TimeInterval
    var activeSide: BreastSide?
    var activeSideStartedAt: Date?

    init(_ nursing: WidgetSnapshot.Nursing) {
        leftSeconds = nursing.leftSeconds
        rightSeconds = nursing.rightSeconds
        activeSide = nursing.activeSide
        activeSideStartedAt = nursing.activeSideStartedAt
    }

    init(_ state: TimerActivityAttributes.ContentState) {
        leftSeconds = state.leftSeconds
        rightSeconds = state.rightSeconds
        activeSide = state.isPaused ? nil : state.activeSide
        activeSideStartedAt = state.isPaused ? nil : state.activeSideStartedAt
    }

    func banked(_ side: BreastSide) -> TimeInterval { side == .left ? leftSeconds : rightSeconds }

    func seconds(_ side: BreastSide, at now: Date) -> TimeInterval {
        var seconds = banked(side)
        if activeSide == side, let started = activeSideStartedAt { seconds += max(0, now.timeIntervalSince(started)) }
        return seconds
    }

    func total(at now: Date) -> TimeInterval { seconds(.left, at: now) + seconds(.right, at: now) }
    var isRunning: Bool { activeSide != nil && activeSideStartedAt != nil }

    /// `Text(timerInterval:)` reference for the live total (only while a side runs).
    var totalReference: Date? {
        guard isRunning, let started = activeSideStartedAt else { return nil }
        return started.addingTimeInterval(-(leftSeconds + rightSeconds))
    }

    /// The total as `Text`, for places that interpolate it into a longer string.
    var totalText: Text {
        if let reference = totalReference { return .live(since: reference, showsHours: false) }
        return Text(DurationFormat.clock(total(at: .now))).monospacedDigit()
    }

    /// `Text(timerInterval:)` reference for one side (only while that side runs).
    func sideReference(_ side: BreastSide) -> Date? {
        guard activeSide == side, let started = activeSideStartedAt else { return nil }
        return started.addingTimeInterval(-banked(side))
    }
}

/// Total nursing time: live while a side runs, frozen when paused.
struct NursingTotalClock: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let values: NursingValues

    var body: some View {
        if isLuminanceReduced, let reference = values.totalReference {
            Elapsed.since(reference)
        } else {
            values.totalText
        }
    }
}

/// One side's time: live while that side runs, otherwise the banked time. Whole minutes while the screen is dimmed
/// (see `LiveClock`).
struct NursingSideClock: View {
    let values: NursingValues
    let side: BreastSide
    var body: some View {
        if let reference = values.sideReference(side) {
            LiveClock(reference: reference, showsHours: false)
        } else {
            Text(DurationFormat.clock(values.banked(side))).monospacedDigit()
        }
    }
}

/// Time since `date`, kept current by the system, so the widget needs no timeline reloads (and no wake-ups) to
/// stay right.
///
/// iOS 18 and later: a minute-granularity `SystemFormatStyle.DateOffset` ("2 hr, 10 min", "6 min"). The old
/// `.relative` style counts seconds ("6 min, 40 sec"), which is wordy for a glance, and ticks every second.
/// iOS 17 falls back to `.relative`.
enum Elapsed {
    static func since(_ date: Date) -> Text {
        if #available(iOS 18.0, *) {
            // The input is "now"; the system re-evaluates it as time passes. `date` is the anchor.
            return Text(Date.now, format: .offset(to: date, allowedFields: [.day, .hour, .minute], maxFieldCount: 2, sign: .never))
        }
        return Text(date, style: .relative)
    }
}

/// "2 hr, 10 min" over a small "ago", for headlines that may wrap.
///
/// The time is its own `Text(date, style: .relative)`, not interpolated into a longer string: the system renders
/// date-style text separately, and as part of an interpolation it loses the surrounding foreground style
/// (it came out black on a dark widget).
struct AgoStack: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Elapsed.since(date)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("ago")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

/// "Fed 2 hr, 10 min ago" on one line, built from separate views (see `AgoStack`).
struct AgoLine: View {
    var prefix: String?
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            if let prefix { Text(prefix) }
            Elapsed.since(date)
            Text("ago")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: Pieces

extension EventKind {
    /// Widget-friendly name for a feed.
    var feedTitle: String { self == .breastfeed ? "Nursing" : "Bottle" }
}

extension WidgetSnapshot.BabySummary {
    var isNursing: Bool { runningNursing != nil }
    var isSleeping: Bool { runningSleepStartedAt != nil }
}

/// Shown when the app hasn't written a snapshot yet (no baby added, or never opened).
struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(EventKind.breastfeed.color)
                .widgetAccentable()
            Text("Open Little Baby Log to add your baby")
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(DeepLink.today(babyID: nil).url)
    }
}

/// A big tappable tile: icon over title, tinted. Used for both intent buttons and link tiles.
struct TileLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let tint: Color
    var subtitle: String?
    /// When set, the subtitle is a live clock counting up from this date instead of `subtitle`.
    var liveSince: Date?
    var filled = false
    var badge: String?

    /// Dark mode (3am): muted tints on black instead of bright saturated blocks.
    private var fill: Color {
        if colorScheme == .dark {
            return tint.opacity(filled ? 0.5 : 0.2)
        }
        return filled ? tint : tint.opacity(0.16)
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let liveSince {
                LiveClock(reference: liveSince, showsHours: false)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .opacity(0.85)
            } else if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(filled ? Color.white : tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fill)
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint))
                    .foregroundStyle(.white)
                    .padding(5)
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .combine)
    }
}

/// `KindIcon`, a little dimmer in dark mode.
struct WidgetKindIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let kind: EventKind
    var size: CGFloat = 44

    var body: some View {
        KindIcon(kind: kind, size: size)
            .saturation(colorScheme == .dark ? 0.8 : 1)
            .brightness(colorScheme == .dark ? -0.12 : 0)
    }
}

extension View {
    /// Plain system background: pure black in dark mode, which is easy on the eyes and on OLED batteries.
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
