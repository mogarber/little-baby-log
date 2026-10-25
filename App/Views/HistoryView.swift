import SwiftUI
import CoreData
import BabyLogKit

struct HistoryView: View {
    let baby: Baby

    @FetchRequest private var events: FetchedResults<LogEvent>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @State private var filter: EventKind?
    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?

    init(baby: Baby) {
        self.baby = baby
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    private struct DayGroup: Identifiable {
        let day: Date
        /// Events shown under this day (after the kind filter).
        let rows: [LogEvent]
        /// Unfiltered events of this day and the day before, for the summary line.
        let summaryEvents: [LogEvent]
        var id: Date { day }
    }

    private func makeGroups() -> [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: Array(events)) { (event: LogEvent) -> Date in
            calendar.startOfDay(for: event.startDate ?? .distantPast)
        }
        var groups: [DayGroup] = []
        for day in byDay.keys.sorted(by: >) {
            let all = byDay[day] ?? []
            let rows = filter == nil ? all : all.filter { $0.kind == filter }
            if rows.isEmpty { continue }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let summaryEvents = all + (byDay[previousDay] ?? [])
            groups.append(DayGroup(day: day, rows: rows, summaryEvents: summaryEvents))
        }
        return groups
    }

    var body: some View {
        let groups = makeGroups()
        List {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "clock")
                } description: {
                    Text(emptyMessage)
                }
                .listRowBackground(Color.clear)
                .foregroundStyle(theme.secondary)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows, id: \.objectID) { event in
                        Button {
                            open(event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    DayHeader(day: group.day, events: group.summaryEvents)
                }
                .themedSection()
            }
        }
        .themedList()
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .sheet(item: $nursing) { item in
            BreastTimerView(event: item.event, suggestedSide: item.suggestedSide)
        }
    }

    private var emptyTitle: String {
        filter == nil ? "No entries yet" : "Nothing here"
    }

    private var emptyMessage: String {
        if let filter {
            return "No \(filter.title.lowercased()) entries logged yet."
        }
        return "Everything you log will show up here."
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $filter) {
                Text("Everything").tag(EventKind?.none)
                ForEach(EventKind.allCases) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
        } label: {
            Image(systemName: filter == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter")
    }

    private var addMenu: some View {
        Menu {
            ForEach(EventKind.allCases) { kind in
                Button {
                    editor = .new(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbolName)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Log a past entry")
    }

    private func open(_ event: LogEvent) {
        if event.kind == .breastfeed && event.isRunning {
            nursing = NursingSheetItem(event: event, suggestedSide: nil)
        } else {
            editor = .edit(event)
        }
    }

    private func delete(_ event: LogEvent) {
        context.delete(event)
        context.saveIfNeeded()
    }
}

private struct DayHeader: View {
    @Environment(\.appTheme) private var theme

    let day: Date
    let events: [LogEvent]
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.primary)
            Text(summaryLine)
                .font(.footnote)
                .foregroundStyle(theme.secondary)
        }
        .textCase(nil)
        .padding(.top, 6)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var summaryLine: String {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let summary = DaySummary(events: events, interval: DateInterval(start: day, end: end))
        var parts: [String] = []
        if summary.sleep > 0 {
            parts.append("Sleep " + DurationFormat.short(summary.sleep))
        }
        if summary.feedCount > 0 {
            parts.append(summary.feedCount == 1 ? "1 feed" : "\(summary.feedCount) feeds")
        }
        if summary.diaperCount > 0 {
            parts.append(summary.diaperCount == 1 ? "1 diaper" : "\(summary.diaperCount) diapers")
        }
        if summary.pumpML > 0 {
            parts.append(volumeUnit.format(milliliters: summary.pumpML) + " pumped")
        }
        return parts.isEmpty ? "No sleep, feeds or diapers" : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        HistoryView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
