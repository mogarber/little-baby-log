import SwiftUI
import Charts
import CoreData
import BabyLogKit

struct TrendsView: View {
    let baby: Baby

    @State private var days = 7

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $days) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                TrendsContent(baby: baby, days: days)
                    .id(days)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Trends")
    }
}

// MARK: - Content

private struct DayStat: Identifiable {
    let day: Date
    let summary: DaySummary
    var id: Date { day }
    var isToday: Bool { Calendar.current.isDateInToday(day) }
}

private struct DiaperPoint: Identifiable {
    let day: Date
    let label: String
    let count: Int
    var id: String { "\(day.timeIntervalSince1970)-\(label)" }
}

private struct WeightPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct TrendsContent: View {
    let baby: Baby
    let days: Int

    @FetchRequest private var events: FetchedResults<LogEvent>
    @FetchRequest private var growth: FetchedResults<LogEvent>
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    init(baby: Baby, days: Int) {
        self.baby = baby
        self.days = days
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        _events = FetchRequest(fetchRequest: LogEvent.requestOverlapping(baby: baby, from: first))
        _growth = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby, kinds: [.growth], ascending: true))
    }

    // MARK: Derived data

    private var stats: [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let list = Array(events)
        return (0..<days).reversed().compactMap { offset -> DayStat? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let summary = DaySummary(events: list, interval: DateInterval(start: day, end: next))
            return DayStat(day: day, summary: summary)
        }
    }

    /// Complete days (not today) from the first day anything was logged.
    private func completeDays(_ stats: [DayStat]) -> [DayStat] {
        let calendar = Calendar.current
        let earliest = events.compactMap { $0.startDate }.min()
        let firstDay = earliest.map { calendar.startOfDay(for: $0) } ?? .distantFuture
        return stats.filter { !$0.isToday && $0.day >= firstDay }
    }

    private func average(_ stats: [DayStat], _ value: (DaySummary) -> Double) -> Double {
        let complete = completeDays(stats)
        guard !complete.isEmpty else { return 0 }
        return complete.map { value($0.summary) }.reduce(0, +) / Double(complete.count)
    }

    private func perDay(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...1))) + " per day"
    }

    private var weightPoints: [WeightPoint] {
        growth.compactMap { event -> WeightPoint? in
            guard let date = event.startDate, event.weightKg > 0 else { return nil }
            let value = unitSystem == .metric ? event.weightKg : event.weightKg / 0.45359237
            return WeightPoint(date: date, value: value)
        }
    }

    // MARK: Body

    var body: some View {
        let stats = self.stats
        let hasData = !events.isEmpty || !growth.isEmpty

        if !hasData {
            ContentUnavailableView(
                "No trends yet",
                systemImage: "chart.bar",
                description: Text("Log a few sleeps, feeds and diapers and your charts will show up here.")
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 16) {
                sleepCard(stats)
                feedsCard(stats)
                diapersCard(stats)
                bottleCard(stats)
                weightCard
            }
        }
    }

    // MARK: Cards

    private func sleepCard(_ stats: [DayStat]) -> some View {
        let avg = average(stats) { $0.sleep / 3600 }
        return TrendCard(
            title: "Sleep",
            subtitle: avg > 0 ? "Average " + DurationFormat.short(avg * 3600) + " a day" : "No complete days yet"
        ) {
            DayBarChart(stats: stats, days: days, color: EventKind.sleep.color, average: avg, unit: "h", minTop: 1) { $0.sleep / 3600 }
        }
    }

    private func feedsCard(_ stats: [DayStat]) -> some View {
        let avg = average(stats) { Double($0.feedCount) }
        return TrendCard(
            title: "Feeds",
            subtitle: avg > 0 ? "Average " + perDay(avg) : "No complete days yet"
        ) {
            DayBarChart(stats: stats, days: days, color: EventKind.breastfeed.color, average: avg, unit: "", minTop: 4) { Double($0.feedCount) }
        }
    }

    private func diapersCard(_ stats: [DayStat]) -> some View {
        let avg = average(stats) { Double($0.diaperCount) }
        let points: [DiaperPoint] = stats.flatMap { stat -> [DiaperPoint] in
            [
                DiaperPoint(day: stat.day, label: "Wet", count: stat.summary.diapers[.wet] ?? 0),
                DiaperPoint(day: stat.day, label: "Dirty", count: stat.summary.diapers[.dirty] ?? 0),
                DiaperPoint(day: stat.day, label: "Both", count: stat.summary.diapers[.mixed] ?? 0)
            ]
        }
        let busiestDay = stats.map { Double($0.summary.diaperCount) }.max() ?? 0
        return TrendCard(
            title: "Diapers",
            subtitle: avg > 0 ? "Average " + perDay(avg) : "No complete days yet"
        ) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Diapers", point.count)
                )
                .foregroundStyle(by: .value("Type", point.label))
            }
            .chartForegroundStyleScale(
                domain: ["Wet", "Dirty", "Both"],
                range: [Color.teal, Color.brown, Color.orange]
            )
            .chartLegend(position: .bottom, alignment: .leading)
            .modifier(WholeNumberYAxis(scale: YAxisScale(maxValue: busiestDay, minTop: 4)))
            .modifier(DayAxis(days: days))
            .frame(height: 180)
        }
    }

    private func bottleCard(_ stats: [DayStat]) -> some View {
        let unit = volumeUnit
        let avg = average(stats) { unit.value(fromMilliliters: $0.bottleML) }
        return TrendCard(
            title: "Bottle volume",
            subtitle: avg > 0
                ? "Average " + avg.formatted(.number.precision(.fractionLength(0...1))) + " " + unit.symbol + " a day"
                : (stats.contains { $0.summary.bottleML > 0 } ? "No complete days yet" : "No bottles in this range")
        ) {
            DayBarChart(stats: stats, days: days, color: EventKind.bottle.color, average: avg, unit: unit.symbol, minTop: 1) {
                unit.value(fromMilliliters: $0.bottleML)
            }
        }
    }

    private var weightCard: some View {
        let points = weightPoints
        let symbol = unitSystem == .metric ? "kg" : "lb"
        let latest = growth.last(where: { $0.weightKg > 0 })?.weightKg
        return TrendCard(
            title: "Weight",
            subtitle: latest.map { "Latest " + unitSystem.formatWeight(kilograms: $0) } ?? "No weight logged yet"
        ) {
            if points.isEmpty {
                Text("Log a growth entry to see your baby's weight over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(EventKind.growth.color)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(EventKind.growth.color)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(symbol)
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Building blocks

private struct TrendCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct DayBarChart: View {
    let stats: [DayStat]
    let days: Int
    let color: Color
    let average: Double
    let unit: String
    /// Smallest top of the value axis, so a nearly empty chart still gets a sane scale.
    let minTop: Double
    let value: (DaySummary) -> Double

    var body: some View {
        let peak = stats.map { value($0.summary) }.max() ?? 0
        Chart {
            ForEach(stats) { stat in
                BarMark(
                    x: .value("Day", stat.day, unit: .day),
                    y: .value("Value", value(stat.summary))
                )
                .foregroundStyle(color.opacity(stat.isToday ? 0.5 : 1))
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxisLabel(unit)
        .modifier(WholeNumberYAxis(scale: YAxisScale(maxValue: max(peak, average), minTop: minTop)))
        .modifier(DayAxis(days: days))
        .frame(height: 160)
    }
}

/// A value axis from 0 with whole-number ticks: a round step and a top that is a multiple of it.
private struct YAxisScale {
    let top: Double
    let step: Double

    init(maxValue: Double, minTop: Double) {
        let wanted = max(minTop, maxValue.rounded(.up), 1)
        let raw = wanted / 4
        let magnitude = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 4, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? 10 * magnitude
        self.step = step
        self.top = (wanted / step).rounded(.up) * step
    }
}

private struct WholeNumberYAxis: ViewModifier {
    let scale: YAxisScale

    func body(content: Content) -> some View {
        content
            .chartYScale(domain: 0...scale.top)
            .chartYAxis {
                AxisMarks(values: .stride(by: scale.step)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.fractionLength(0)))
                }
            }
    }
}

private struct DayAxis: ViewModifier {
    let days: Int

    private var strideDays: Int {
        if days <= 7 { return 1 }
        if days <= 14 { return 2 }
        return 5
    }

    func body(content: Content) -> some View {
        content.chartXAxis {
            AxisMarks(values: .stride(by: .day, count: strideDays)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
    }
}

#Preview {
    NavigationStack {
        TrendsView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
