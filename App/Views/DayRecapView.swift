import SwiftUI
import CoreData
import BabyLogKit

/// The daily hourly recap: everything that happened on one day, hour by hour, for a parent taking the baby back
/// from a nanny. A date header (previous / next / tap to pick), a summary strip, then a timeline with a sleep bar.
///
/// The layout comes from `DayRecap` in BabyLogKit; this file draws it. Only today's recap has a timer (once a
/// minute, to move the "now" line and grow a running sleep); past days draw once and nothing runs.
struct DayRecapView: View {
    let baby: Baby
    /// Inside the History tab, which supplies the title. Pushed on its own (from Today), the view titles itself.
    var embedded = false

    @State private var day: Date
    @State private var pickingDate = false
    @Environment(\.appTheme) private var theme

    init(baby: Baby, day: Date = .now, embedded: Bool = false) {
        self.baby = baby
        self.embedded = embedded
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 0) {
            header
            DayRecapDay(baby: baby, day: day)
                .id(day)
        }
        .themedScreen()
        .modifier(RecapTitle(embedded: embedded))
        .sheet(isPresented: $pickingDate) {
            RecapDatePicker(day: $day)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")

            Button {
                pickingDate = true
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Image(systemName: "calendar")
                            .font(.footnote)
                            .foregroundStyle(theme.accent)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Day: \(title). Choose a date")

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.gridLine).frame(height: 0.5)
        }
        .background(theme.background)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var subtitle: String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInYesterday(day) {
            return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        if !calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.year())
        }
        return nil
    }

    private func shift(by days: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .day, value: days, to: day) else { return }
        let today = calendar.startOfDay(for: .now)
        day = min(calendar.startOfDay(for: moved), today)
    }
}

/// Large titles don't collapse over a fixed header, so the recap uses an inline one.
private struct RecapTitle: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .navigationTitle("Recap")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Date picker

private struct RecapDatePicker: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(day: Binding<Date>) {
        _day = day
        _selection = State(initialValue: day.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $selection, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
                .themedScreen()
                .navigationTitle("Go to day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onChange(of: selection) { _, newValue in
                    day = Calendar.current.startOfDay(for: newValue)
                    dismiss()
                }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - One day

/// Owns the fetch for one day (the parent re-creates it with `.id(day)` when the day changes).
private struct DayRecapDay: View {
    let baby: Baby
    let day: Date

    @FetchRequest private var events: FetchedResults<LogEvent>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?
    @State private var changeTick = 0

    init(baby: Baby, day: Date) {
        self.baby = baby
        self.day = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _events = FetchRequest(fetchRequest: LogEvent.requestDay(baby: baby, interval: DateInterval(start: day, end: end)))
    }

    var body: some View {
        Group {
            if Calendar.current.isDateInToday(day) {
                // The only timer in the recap: once a minute, today only.
                TimelineView(.everyMinute) { timeline in
                    let _ = changeTick
                    page(now: timeline.date)
                }
            } else {
                let _ = changeTick
                page(now: .now)
            }
        }
        .onContextChange(context) { changeTick += 1 }
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .sheet(item: $nursing) { item in
            BreastTimerView(event: item.event, suggestedSide: item.suggestedSide)
        }
    }

    private var calendar: Calendar { .current }

    @ViewBuilder
    private func page(now: Date) -> some View {
        let recap = DayRecap(day: day, events: Array(events), calendar: calendar, now: now)
        Group {
            if recap.isEmpty {
                ContentUnavailableView {
                    Label("Nothing logged", systemImage: "moon.zzz")
                } description: {
                    Text(recap.isToday ? "Nothing has been logged yet today." : "Nothing was logged on this day.")
                }
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        RecapSummaryStrip(summary: recap.summary, napCount: recap.napCount, volumeUnit: volumeUnit)
                        RecapTimeline(recap: recap, now: now, unit: volumeUnit, system: unitSystem, onOpen: open)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(theme.background)
            }
        }
        .toolbar {
            if !recap.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    shareLink(for: recap)
                }
            }
        }
    }

    /// Plain text for people who are not on the app. Nothing leaves the phone until a destination is chosen.
    private func shareLink(for recap: DayRecap) -> some View {
        let describer = EventDescriber(volumeUnit: volumeUnit, unitSystem: unitSystem)
        let name = baby.displayName
        let text = recap.plainText(babyName: name, describer: describer, calendar: calendar)
        return ShareLink(item: text, subject: Text("\(name)'s day")) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share recap")
    }

    private func open(_ event: LogEvent) {
        if event.kind == .breastfeed && event.isRunning {
            nursing = NursingSheetItem(event: event, suggestedSide: nil)
        } else {
            editor = .edit(event)
        }
    }
}

// MARK: - Summary strip

private struct RecapSummaryStrip: View {
    @Environment(\.appTheme) private var theme

    let summary: DaySummary
    let napCount: Int
    let volumeUnit: VolumeUnit

    private struct Tile: Identifiable {
        let kind: EventKind
        let value: String
        let label: String
        var details: [String] = []
        var id: String { label }
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        result.append(Tile(
            kind: .sleep,
            value: DurationFormat.short(summary.sleep),
            label: "Sleep",
            details: [napCount == 1 ? "1 nap" : napCount == 0 ? "No naps" : "\(napCount) naps"]
        ))
        var feedDetails: [String] = []
        if summary.nursing > 0 { feedDetails.append("Nursing " + DurationFormat.short(summary.nursing)) }
        if summary.bottleML > 0 { feedDetails.append("Bottle " + volumeUnit.format(milliliters: summary.bottleML)) }
        result.append(Tile(
            kind: .breastfeed,
            value: "\(summary.feedCount)",
            label: summary.feedCount == 1 ? "Feed" : "Feeds",
            details: feedDetails
        ))
        result.append(Tile(
            kind: .diaper,
            value: "\(summary.diaperCount)",
            label: summary.diaperCount == 1 ? "Diaper" : "Diapers",
            details: summary.diaperCount > 0 ? ["\(summary.wetCount) wet · \(summary.dirtyCount) dirty"] : []
        ))
        if summary.solidsCount > 0 {
            result.append(Tile(kind: .solids, value: "\(summary.solidsCount)", label: "Solids"))
        }
        if summary.medicineCount > 0 {
            result.append(Tile(kind: .medicine, value: "\(summary.medicineCount)", label: "Medicine"))
        }
        if summary.pumpML > 0 {
            result.append(Tile(kind: .pump, value: volumeUnit.format(milliliters: summary.pumpML), label: "Pumped"))
        }
        return result
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12, alignment: .topLeading), GridItem(.flexible(), spacing: 12, alignment: .topLeading)],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(tiles) { tile in
                HStack(alignment: .top, spacing: 10) {
                    KindIcon(kind: tile.kind, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tile.value)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(tile.label)
                            .font(.footnote)
                            .foregroundStyle(theme.secondary)
                        ForEach(tile.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(theme.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Timeline

private enum RecapMetrics {
    static let labelWidth: CGFloat = 56
    static let trackWidth: CGFloat = 22
    static let barWidth: CGFloat = 10
    static let nowRowHeight: CGFloat = 24
    /// Vertical padding around an hour's entries; the "now" line sits above the bottom one.
    static let entryPadding: CGFloat = 6
}

/// The rows of the day in one card, oldest first. Rows have no spacing so the sleep bar runs unbroken through them.
private struct RecapTimeline: View {
    @Environment(\.appTheme) private var theme

    let recap: DayRecap
    let now: Date
    let unit: VolumeUnit
    let system: UnitSystem
    let onOpen: (LogEvent) -> Void

    var body: some View {
        let rows = recap.rows
        VStack(spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .hour(let hour):
                    HourRow(
                        hour: hour,
                        isCurrent: hour.index == recap.currentHourIndex,
                        now: now,
                        unit: unit,
                        system: system,
                        isFirst: row.id == rows.first?.id,
                        onOpen: onOpen
                    )
                case .quiet(let run):
                    QuietRow(run: run, isFirst: row.id == rows.first?.id)
                }
            }
        }
        .padding(.trailing, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One drawn piece of the sleep bar, as fractions (0...1) of the track's height.
private struct TrackBar {
    var from: Double
    var to: Double
    var roundTop: Bool
    var roundBottom: Bool
}

/// The vertical track: a hairline spine for the hours, a thick bar where the baby slept, and a dot at the "now"
/// line. `scale` stretches the fractions (the current hour only shows the part up to now); `bottomInset` leaves
/// room for the "now" line under the entries.
private struct SleepTrack: View {
    @Environment(\.appTheme) private var theme

    let bars: [TrackBar]
    var scale: Double = 1
    var bottomInset: CGFloat = 0
    var showsNowDot = false

    var body: some View {
        Color.clear
            .frame(width: RecapMetrics.trackWidth)
            .overlay {
                GeometryReader { geo in
                    let usable = max(0, geo.size.height - bottomInset)
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(theme.gridLine)
                            .frame(width: 2)
                        ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                            let top = min(1, bar.from * scale) * usable
                            let bottom = min(1, bar.to * scale) * usable
                            UnevenRoundedRectangle(
                                topLeadingRadius: bar.roundTop ? 5 : 0,
                                bottomLeadingRadius: bar.roundBottom ? 5 : 0,
                                bottomTrailingRadius: bar.roundBottom ? 5 : 0,
                                topTrailingRadius: bar.roundTop ? 5 : 0,
                                style: .continuous
                            )
                            .fill(theme.color(for: .sleep))
                            .frame(width: RecapMetrics.barWidth, height: max(6, bottom - top))
                            .offset(y: top)
                        }
                        if showsNowDot {
                            Circle()
                                .fill(theme.destructive)
                                .frame(width: 9, height: 9)
                                .offset(y: geo.size.height - RecapMetrics.entryPadding - RecapMetrics.nowRowHeight / 2 - 4.5)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .accessibilityHidden(true)
    }
}

private func hourLabel(_ date: Date) -> String {
    date.formatted(.dateTime.hour())
}

private struct HourRow: View {
    @Environment(\.appTheme) private var theme

    let hour: DayRecap.Hour
    let isCurrent: Bool
    let now: Date
    let unit: VolumeUnit
    let system: UnitSystem
    let isFirst: Bool
    let onOpen: (LogEvent) -> Void

    /// How far through the hour "now" is, for the current hour (nothing after it is drawn).
    private var nowFraction: Double {
        let length = hour.end.timeIntervalSince(hour.start)
        guard length > 0 else { return 1 }
        return min(1, max(0.02, now.timeIntervalSince(hour.start) / length))
    }

    private var bars: [TrackBar] {
        hour.sleepSlices.map {
            TrackBar(from: $0.from, to: $0.to, roundTop: $0.startsHere, roundBottom: $0.endsHere)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(hourLabel(hour.start))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                if hour.isRepeated {
                    Text("(2nd)")
                        .font(.caption2)
                        .foregroundStyle(theme.secondary)
                }
            }
            .foregroundStyle(theme.secondary)
            .frame(width: RecapMetrics.labelWidth - 8, alignment: .trailing)
            .padding(.trailing, 8)
            .padding(.top, 14)

            SleepTrack(
                bars: bars,
                scale: isCurrent ? 1 / nowFraction : 1,
                bottomInset: isCurrent ? RecapMetrics.nowRowHeight + RecapMetrics.entryPadding : 0,
                showsNowDot: isCurrent
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(hour.entries) { entry in
                    Button {
                        onOpen(entry.event)
                    } label: {
                        RecapEntryRow(entry: entry, now: now, unit: unit, system: system)
                    }
                    .buttonStyle(.plain)
                }
                if hour.entries.isEmpty {
                    Color.clear.frame(height: 30)
                }
                if isCurrent {
                    NowLine(now: now)
                }
            }
            .padding(.vertical, RecapMetrics.entryPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.gridLine.opacity(0.7))
                    .frame(height: 0.5)
                    .padding(.leading, RecapMetrics.labelWidth + RecapMetrics.trackWidth)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NowLine: View {
    @Environment(\.appTheme) private var theme
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Text("Now")
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.destructive)
            Rectangle()
                .fill(theme.destructive)
                .frame(height: 1.5)
        }
        .frame(height: RecapMetrics.nowRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
    }
}

/// A run of empty hours, one short row. If the baby slept through it, the sleep bar still passes through.
private struct QuietRow: View {
    @Environment(\.appTheme) private var theme

    let run: DayRecap.QuietRun
    let isFirst: Bool

    private var rangeLabel: [String] {
        // The second pass through a clock hour on a fall-back day gets the same "(2nd)" tag as an hour row.
        if run.hours.count == 1 {
            return [hourLabel(run.first.start)] + (run.first.isRepeated ? ["(2nd)"] : [])
        }
        return [hourLabel(run.first.start) + (run.first.isRepeated ? " (2nd)" : ""), "– " + hourLabel(run.last.start)]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(rangeLabel, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(theme.secondary)
            .frame(width: RecapMetrics.labelWidth - 8, alignment: .trailing)
            .padding(.trailing, 8)

            SleepTrack(bars: run.isAsleep ? [TrackBar(from: 0, to: 1, roundTop: false, roundBottom: false)] : [])

            Group {
                if run.isAsleep {
                    Label("Asleep · " + DurationFormat.short(run.asleepDuration), systemImage: "moon.zzz.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                } else {
                    Text("Nothing logged")
                        .font(.caption)
                        .foregroundStyle(theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(minHeight: 36)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.gridLine.opacity(0.7))
                    .frame(height: 0.5)
                    .padding(.leading, RecapMetrics.labelWidth + RecapMetrics.trackWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let span = run.hours.count == 1
            ? hourLabel(run.first.start)
            : "\(hourLabel(run.first.start)) to \(hourLabel(run.last.start))"
        return run.isAsleep
            ? "\(span): asleep, \(DurationFormat.short(run.asleepDuration))"
            : "\(span): nothing logged"
    }
}

/// A compact entry: icon, time, and the one-line summary.
private struct RecapEntryRow: View {
    @ObservedObject var event: LogEvent
    let entry: DayRecap.Entry
    let now: Date
    let unit: VolumeUnit
    let system: UnitSystem

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 64

    init(entry: DayRecap.Entry, now: Date, unit: VolumeUnit, system: UnitSystem) {
        self.entry = entry
        self.now = now
        self.unit = unit
        self.system = system
        _event = ObservedObject(wrappedValue: entry.event)
    }

    private var isWakeUp: Bool {
        if case .wakeUp = entry { return true }
        return false
    }

    private var time: String {
        entry.time.formatted(date: .omitted, time: .shortened)
    }

    private var title: String { isWakeUp ? "Woke up" : event.kind.title }

    private var detail: String {
        if isWakeUp { return "slept " + DurationFormat.short(event.duration(at: now)) }
        return EventDescriber(volumeUnit: unit, unitSystem: system).summary(for: event, now: now)
    }

    var body: some View {
        if event.isDeleted || event.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                if isWakeUp {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.onColor)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(theme.color(for: .sleep)))
                        .accessibilityHidden(true)
                } else {
                    KindIcon(kind: event.kind, size: 26)
                }
                Text(time)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondary)
                    .frame(width: timeWidth, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                labels
                Spacer(minLength: 0)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(time), \(title)" + (detail.isEmpty ? "" : ", \(detail)"))
            .accessibilityHint("Opens the entry to edit")
        }
    }

    @ViewBuilder
    private var labels: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.weight(.semibold))
                if !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(theme.secondary)
                }
            }
        } else {
            // One line when it fits; otherwise the summary drops under the title.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if !detail.isEmpty {
                        Text("· " + detail).font(.subheadline).foregroundStyle(theme.secondary)
                    }
                }
                .lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(theme.secondary).lineLimit(2)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DayRecapView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
