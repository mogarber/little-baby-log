import SwiftUI
import CoreData
import BabyLogKit

struct TodayView: View {
    @ObservedObject var baby: Baby
    let day: Date
    @Binding var link: DeepLink?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @FetchRequest private var running: FetchedResults<LogEvent>
    @FetchRequest private var dayEvents: FetchedResults<LogEvent>

    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?
    @State private var feedback = 0

    init(baby: Baby, day: Date, link: Binding<DeepLink?> = .constant(nil)) {
        _baby = ObservedObject(wrappedValue: baby)
        self.day = day
        _link = link
        _running = FetchRequest(fetchRequest: LogEvent.requestRunning(baby: baby))
        _dayEvents = FetchRequest(fetchRequest: LogEvent.requestOverlapping(baby: baby, from: day))
    }

    private var runningSleep: LogEvent? {
        running.first(where: { $0.kind == .sleep })
    }

    private var runningNursing: LogEvent? {
        running.first(where: { $0.kind == .breastfeed })
    }

    private var timeline: [LogEvent] {
        dayEvents.filter { !$0.isRunning }
    }

    var body: some View {
        List {
            if !running.isEmpty {
                Section {
                    ForEach(running, id: \.objectID) { event in
                        ActiveTimerRow(
                            event: event,
                            onWake: { wake(event) },
                            onOpen: { openNursing(event) }
                        )
                    }
                }
                .themedSection()
            }

            Section {
                SinceLastView(baby: baby)
            } header: {
                if let birthDate = baby.birthDate {
                    Text(BabyAge.description(birthDate: birthDate))
                        .font(.subheadline.weight(.medium))
                        .textCase(nil)
                }
            }
            .themedSection()

            Section {
                QuickActionsGrid(
                    isSleeping: runningSleep != nil,
                    onTap: { quickTap($0) },
                    onLogPast: { editor = .new($0) },
                    onQuickDiaper: { quickDiaper($0) }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
            } header: {
                Text("Log").textCase(nil)
            }
            .themedSection()

            Section {
                DaySummaryView(events: Array(dayEvents), day: day)
            } header: {
                Text("Today").textCase(nil)
            }
            .themedSection()

            Section {
                if timeline.isEmpty {
                    Text("Nothing logged yet today.")
                        .foregroundStyle(theme.secondary)
                } else {
                    ForEach(timeline, id: \.objectID) { event in
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
                }
            } header: {
                Text("Timeline").textCase(nil)
            }
            .themedSection()
        }
        .themedList()
        .navigationTitle(baby.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BabySwitcherMenu()
            }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onChange(of: link, initial: true) { _, newLink in
            guard let newLink else { return }
            link = nil
            open(newLink)
        }
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .sheet(item: $nursing) { item in
            BreastTimerView(event: item.event, suggestedSide: item.suggestedSide)
        }
    }

    // MARK: Actions

    /// `littlebabylog://` links from widgets: the editor for a kind, or the nursing timer.
    private func open(_ link: DeepLink) {
        let present: () -> Void
        switch link {
        case .today:
            return
        case .nursing, .log(.breastfeed, _):
            present = { startNursing() }
        case .log(let kind, _):
            present = { editor = .new(kind) }
        }
        if editor != nil || nursing != nil {
            // Replace whatever sheet is up; SwiftUI can't swap one sheet for another in a single update.
            editor = nil
            nursing = nil
            DispatchQueue.main.async(execute: present)
        } else {
            present()
        }
    }

    private func quickTap(_ kind: EventKind) {
        switch kind {
        case .sleep:
            toggleSleep()
        case .breastfeed:
            startNursing()
        default:
            editor = .new(kind)
        }
    }

    private func toggleSleep() {
        if let sleep = runningSleep {
            wake(sleep)
        } else {
            _ = LogEvent.create(kind: .sleep, for: baby, in: context)
            context.saveIfNeeded()
            feedback += 1
        }
    }

    private func wake(_ event: LogEvent) {
        var draft = EventDraft(event: event)
        draft.endDate = .now
        draft.apply(to: event)
        context.saveIfNeeded()
        feedback += 1
    }

    private func quickDiaper(_ kind: DiaperKind) {
        let event = LogEvent.create(kind: .diaper, for: baby, in: context)
        event.diaperKind = kind
        context.saveIfNeeded()
        feedback += 1
    }

    private func nextSide() -> BreastSide? {
        let request = LogEvent.requestLatest(baby: baby, kinds: [.breastfeed], finishedOnly: true)
        let latest = (try? context.fetch(request))?.first
        return latest?.lastSide?.other
    }

    private func startNursing() {
        if let existing = runningNursing {
            openNursing(existing)
            return
        }
        let suggestion = nextSide()
        let event = LogEvent.create(kind: .breastfeed, for: baby, in: context)
        context.saveIfNeeded()
        nursing = NursingSheetItem(event: event, suggestedSide: suggestion)
    }

    private func openNursing(_ event: LogEvent) {
        nursing = NursingSheetItem(event: event, suggestedSide: nextSide())
    }

    private func open(_ event: LogEvent) {
        if event.kind == .breastfeed && event.isRunning {
            openNursing(event)
        } else {
            editor = .edit(event)
        }
    }

    private func delete(_ event: LogEvent) {
        context.delete(event)
        context.saveIfNeeded()
    }
}

#Preview {
    NavigationStack {
        TodayView(baby: PreviewData.baby, day: Calendar.current.startOfDay(for: .now))
    }
    .previewEnvironment()
}
