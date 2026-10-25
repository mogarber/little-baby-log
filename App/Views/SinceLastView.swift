import SwiftUI
import CoreData
import BabyLogKit

/// "Awake for 1h 20m", "Last feed 2h 10m ago · Next: Right", "Last diaper 45m ago".
struct SinceLastView: View {
    let baby: Baby

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @FetchRequest private var running: FetchedResults<LogEvent>
    @FetchRequest private var lastSleep: FetchedResults<LogEvent>
    @FetchRequest private var lastFeed: FetchedResults<LogEvent>
    @FetchRequest private var lastNursing: FetchedResults<LogEvent>
    @FetchRequest private var lastDiaper: FetchedResults<LogEvent>
    @State private var changeTick = 0

    init(baby: Baby) {
        self.baby = baby
        _running = FetchRequest(fetchRequest: LogEvent.requestRunning(baby: baby))
        _lastSleep = FetchRequest(
            fetchRequest: LogEvent.requestLatest(baby: baby, kinds: [.sleep], finishedOnly: true)
        )
        _lastFeed = FetchRequest(
            fetchRequest: LogEvent.requestLatest(baby: baby, kinds: [.breastfeed, .bottle])
        )
        _lastNursing = FetchRequest(
            fetchRequest: LogEvent.requestLatest(baby: baby, kinds: [.breastfeed], finishedOnly: true)
        )
        _lastDiaper = FetchRequest(
            fetchRequest: LogEvent.requestLatest(baby: baby, kinds: [.diaper])
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let _ = changeTick
            content(now: timeline.date)
        }
        .onContextChange(context) { changeTick += 1 }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let sleepLine = sleepStat(now: now)
        let feedLine = feedStat(now: now)
        let diaperLine = diaperStat(now: now)

        if sleepLine == nil && feedLine == nil && diaperLine == nil {
            Text("Nothing logged yet. Tap a button below to get started.")
                .foregroundStyle(theme.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let sleepLine {
                    StatLine(kind: .sleep, title: sleepLine.title, value: sleepLine.value, detail: nil)
                }
                if let feedLine {
                    StatLine(kind: feedLine.kind, title: "Last feed", value: feedLine.value, detail: feedLine.detail)
                }
                if let diaperLine {
                    StatLine(kind: .diaper, title: "Last diaper", value: diaperLine.value, detail: diaperLine.detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: Data

    private struct Stat {
        var kind: EventKind
        var title: String
        var value: String
        var detail: String?
    }

    private func sleepStat(now: Date) -> Stat? {
        if let sleep = running.first(where: { $0.kind == .sleep }), let start = sleep.startDate {
            return Stat(kind: .sleep, title: "Asleep for", value: DurationFormat.short(max(0, now.timeIntervalSince(start))), detail: nil)
        }
        if let end = lastSleep.first?.endDate {
            return Stat(kind: .sleep, title: "Awake for", value: DurationFormat.short(max(0, now.timeIntervalSince(end))), detail: nil)
        }
        return nil
    }

    private func feedStat(now: Date) -> Stat? {
        guard let feed = lastFeed.first else { return nil }
        let next = lastNursing.first?.lastSide?.other
        let detail = next.map { "Next: \($0.title)" }
        if feed.isRunning {
            return Stat(kind: feed.kind, title: "Last feed", value: "Now", detail: detail)
        }
        guard let reference = feed.endDate ?? feed.startDate else { return nil }
        return Stat(kind: feed.kind, title: "Last feed", value: ago(reference, now: now), detail: detail)
    }

    private func diaperStat(now: Date) -> Stat? {
        guard let diaper = lastDiaper.first, let time = diaper.startDate else { return nil }
        return Stat(kind: .diaper, title: "Last diaper", value: ago(time, now: now), detail: diaper.diaperKind?.title)
    }

    private func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        return DurationFormat.short(seconds) + " ago"
    }
}

private struct StatLine: View {
    @Environment(\.appTheme) private var theme

    let kind: EventKind
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            KindIcon(kind: kind, size: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        SinceLastView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
