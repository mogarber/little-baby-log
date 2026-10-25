import SwiftUI
import CoreData
import BabyLogKit

/// "Up next" on Today: the next nap window or bedtime, and the next feed, with how sure we are and why.
///
/// Free and on-device: the numbers come from `SleepPredictor` / `FeedPredictor` in BabyLogKit, run on the baby's
/// last two weeks of logs. Nothing is stored; it is recomputed from the fetched events. The "in 25m" text is
/// kept current by a minute-granularity `TimelineView`, which only ticks while this screen is in the foreground.
/// There is no polling and no background work.
struct UpNextView: View {
    @ObservedObject var baby: Baby

    @Environment(\.appTheme) private var theme
    @FetchRequest private var events: FetchedResults<LogEvent>
    @State private var showsInfo = false

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let calendar = Calendar.current
        // A start-of-day bound keeps the request equal all day, so SwiftUI doesn't refetch on every update.
        let from = calendar.date(byAdding: .day, value: -PredictionInputs.lookbackDays, to: calendar.startOfDay(for: .now))
            ?? .now.addingTimeInterval(-TimeInterval(PredictionInputs.lookbackDays) * 86_400)
        _events = FetchRequest(fetchRequest: PredictionInputs.fetchRequest(for: baby, from: from))
    }

    // MARK: Forecast

    struct Forecast: Equatable {
        var ageDays: Int
        var sleep: SleepPrediction?
        var feed: FeedPrediction?
        var lastFeedStart: Date?

        var isEmpty: Bool { sleep == nil && feed == nil }
    }

    private func forecast(at now: Date) -> Forecast? {
        guard let birthDate = baby.birthDate else { return nil }
        let calendar = Calendar.current
        let inputs = PredictionInputs.samples(from: events, now: now)
        return Forecast(
            ageDays: AgeNorms.ageDays(birthDate: birthDate, now: now, calendar: calendar),
            sleep: SleepPredictor.next(birthDate: birthDate, sleeps: inputs.sleeps, now: now, calendar: calendar),
            feed: FeedPredictor.next(birthDate: birthDate, feeds: inputs.feeds, now: now, calendar: calendar),
            lastFeedStart: inputs.feeds.last?.start
        )
    }

    // MARK: Body

    var body: some View {
        if let first = forecast(at: .now), !first.isEmpty {
            Section {
                TimelineView(.everyMinute) { timeline in
                    content(forecast(at: timeline.date) ?? first, now: timeline.date)
                }
            } header: {
                header(first)
            }
            .themedSection()
        }
    }

    private func header(_ initial: Forecast) -> some View {
        HStack {
            Text("Up next")
                .textCase(nil)
            Spacer()
            Button {
                showsInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How predictions work")
        }
        .sheet(isPresented: $showsInfo) {
            UpNextInfoSheet(name: baby.displayName, forecast: forecast(at: .now) ?? initial)
        }
    }

    @ViewBuilder
    private func content(_ forecast: Forecast, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sleep = forecast.sleep {
                UpNextRow(
                    kind: .sleep,
                    title: sleep.kind == .nap ? "Nap window" : "Bedtime around",
                    value: sleep.kind == .nap ? Self.interval(sleep.window) : Self.time(sleep.centre),
                    timing: PredictionText.timing(of: sleep.window, at: now).text,
                    caption: PredictionText.caption(basis: sleep.basis, babyName: baby.displayName, ageDays: forecast.ageDays)
                )
            }
            if let feed = forecast.feed {
                UpNextRow(
                    kind: .breastfeed,
                    title: "Next feed around",
                    value: Self.time(feed.centre),
                    timing: PredictionText.timing(of: feed.around, at: now).text,
                    caption: PredictionText.caption(basis: feed.basis, babyName: baby.displayName, ageDays: forecast.ageDays)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: Formatting

    /// "2:10 – 2:40 PM", in the person's own clock style.
    static func interval(_ window: DateInterval) -> String {
        (window.start..<window.end).formatted(.interval.hour().minute())
    }

    /// "7:15 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct UpNextRow: View {
    @Environment(\.appTheme) private var theme

    let kind: EventKind
    let title: String
    let value: String
    let timing: String
    let caption: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KindIcon(kind: kind, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(timing)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.secondary)
                .monospacedDigit()
                .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(timing). \(caption).")
    }
}

/// The "how this works" sheet: the disclaimer, a short explanation, and the numbers behind what is on screen.
private struct UpNextInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let name: String
    let forecast: UpNextView.Forecast

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(PredictionText.disclaimer)
                        .font(.headline)
                    Text(PredictionText.howItWorks)
                        .foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !details.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Right now")
                                .font(.headline)
                            ForEach(details, id: \.self) { line in
                                Text(line)
                                    .foregroundStyle(theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .themedScreen()
            .navigationTitle("How predictions work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var details: [String] {
        var lines: [String] = []
        let age = PredictionText.ageLabel(ageDays: forecast.ageDays)
        if let sleep = forecast.sleep {
            let basis = PredictionText.caption(basis: sleep.basis, babyName: name, ageDays: forecast.ageDays)
            if let wake = sleep.lastWake {
                let gap = DurationFormat.short(sleep.centre.timeIntervalSince(wake))
                let noun = sleep.kind == .nap ? "nap window" : "bedtime"
                lines.append("Sleep: \(name) last woke at \(UpNextView.time(wake)). About \(gap) of awake time puts the \(noun) around \(UpNextView.time(sleep.centre)). \(basis).")
            } else {
                lines.append("Sleep: there is no recent wake-up in the log, so this counts from now using typical wake windows for \(age).")
            }
            if sleep.kind == .bedtime {
                lines.append("Bedtime comes next because today's naps are done, or the next nap would land close to \(name)'s usual bedtime.")
            }
        }
        if let feed = forecast.feed {
            let basis = PredictionText.caption(basis: feed.basis, babyName: name, ageDays: forecast.ageDays)
            if let last = forecast.lastFeedStart {
                let gap = DurationFormat.short(feed.centre.timeIntervalSince(last))
                lines.append("Feeding: the last feed started at \(UpNextView.time(last)), and feeds have been about \(gap) apart at this time of day. \(basis).")
            } else {
                lines.append("Feeding: \(basis).")
            }
        }
        return lines
    }
}

#Preview {
    List {
        UpNextView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
