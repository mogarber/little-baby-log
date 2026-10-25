import SwiftUI
import CoreData
import UIKit
import BabyLogKit

/// Settings > Reminders. Per baby: "feed every N hours", the nap window reminder, and any number of daily reminders. Stored on this phone only
/// (`ReminderSettingsStore`); every edit re-plans the notifications through `ReminderScheduler`.
struct RemindersSettingsView: View {
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme

    @State private var permission: ReminderScheduler.Permission = .notDetermined

    var body: some View {
        Form {
            if permission == .denied {
                permissionSection
            }
            ForEach(babies, id: \.objectID) { baby in
                if let id = baby.uuid {
                    BabyRemindersSection(babyID: id, babyName: baby.displayName, showName: babies.count > 1, permission: $permission)
                }
            }
            Section {
            } footer: {
                Text("Feed and medicine reminders are Time Sensitive, so they can get through Focus and Sleep mode. Nap reminders are not. You can turn that off for the app in iOS Settings. Reminders are set up on each phone separately.")
            }
        }
        .themedList()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { permission = await ReminderScheduler.shared.permission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { permission = await ReminderScheduler.shared.permission() }
            }
        }
    }

    private var permissionSection: some View {
        Section {
            Label {
                Text("Notifications are turned off for Little Baby Log, so reminders can't appear. Open iOS Settings, tap Notifications, and turn on Allow Notifications.")
            } icon: {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(theme.isNight ? theme.destructive : .orange)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "gearshape.fill")
            }
        }
        .themedSection()
    }
}

// MARK: - One baby

private struct BabyRemindersSection: View {
    let babyID: UUID
    let babyName: String
    let showName: Bool
    @Binding var permission: ReminderScheduler.Permission

    @Environment(\.appTheme) private var theme
    @State private var settings: BabyReminderSettings
    @State private var editing: DailyReminderEditorItem?

    private let store = ReminderSettingsStore()

    init(babyID: UUID, babyName: String, showName: Bool, permission: Binding<ReminderScheduler.Permission>) {
        self.babyID = babyID
        self.babyName = babyName
        self.showName = showName
        self._permission = permission
        self._settings = State(initialValue: ReminderSettingsStore().settings(for: babyID))
    }

    var body: some View {
        Group {
            feedSection
            napSection
            dailySection
        }
        .onChange(of: settings) { old, new in
            store.save(new, for: babyID)
            Task {
                // The first time anything is turned on is the moment to ask for permission, not at launch.
                if new.hasAnythingEnabled, !old.hasAnythingEnabled || permission == .notDetermined {
                    permission = await ReminderScheduler.shared.requestPermissionIfNeeded()
                }
                await ReminderScheduler.shared.refresh()
            }
        }
        .sheet(item: $editing) { item in
            DailyReminderEditor(reminder: item.reminder, isNew: item.isNew, babyName: babyName) { saved in
                if let index = settings.daily.firstIndex(where: { $0.id == saved.id }) {
                    settings.daily[index] = saved
                } else {
                    settings.daily.append(saved)
                }
            } onDelete: { id in
                settings.daily.removeAll { $0.id == id }
            }
        }
    }

    // MARK: Feed every N hours

    private var feedSection: some View {
        Section {
            Toggle("Remind me to feed", isOn: $settings.feedEvery.isEnabled)
            if settings.feedEvery.isEnabled {
                Picker("Every", selection: $settings.feedEvery.intervalMinutes) {
                    ForEach(intervalOptions, id: \.self) { minutes in
                        Text(Self.intervalTitle(minutes)).tag(minutes)
                    }
                }
                Picker("Counting from", selection: $settings.feedEvery.anchor) {
                    ForEach(FeedIntervalAnchor.allCases) { anchor in
                        Text(anchor == .start ? "Start" : "End").tag(anchor)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Quiet hours", isOn: quietHoursEnabled)
                if let quiet = settings.feedEvery.quietHours {
                    DatePicker("From", selection: minutesBinding(quietStart(quiet)), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: minutesBinding(quietEnd(quiet)), displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text(showName ? "\(babyName): feeding" : "Feeding")
        } footer: {
            if settings.feedEvery.isEnabled {
                Text(feedFooter)
            } else {
                Text("Get a reminder a set time after each feed. It moves every time a feed is logged, on this phone or a partner's.")
            }
        }
        .themedSection()
    }

    private var feedFooter: String {
        let from = settings.feedEvery.anchor == .start ? "the start of the last feed" : "the end of the last feed"
        var text = "Reminds you \(Self.intervalTitle(settings.feedEvery.intervalMinutes)) after \(from). Log a feed and the reminder moves."
        if settings.feedEvery.quietHours != nil {
            text += " A reminder due during quiet hours waits until they end."
        }
        return text
    }

    private var intervalOptions: [Int] {
        var options = FeedIntervalReminder.allowedMinutes
        #if DEBUG
        options.insert(1, at: 0)
        #endif
        let current = settings.feedEvery.intervalMinutes
        if !options.contains(current) { options.append(current) }
        return options
    }

    private var quietHoursEnabled: Binding<Bool> {
        Binding(
            get: { settings.feedEvery.quietHours != nil },
            set: { settings.feedEvery.quietHours = $0 ? (settings.feedEvery.quietHours ?? QuietHours()) : nil }
        )
    }

    private func quietStart(_ quiet: QuietHours) -> Binding<Int> {
        Binding(get: { quiet.startMinutes }, set: { settings.feedEvery.quietHours?.startMinutes = $0 })
    }

    private func quietEnd(_ quiet: QuietHours) -> Binding<Int> {
        Binding(get: { quiet.endMinutes }, set: { settings.feedEvery.quietHours?.endMinutes = $0 })
    }

    static func intervalTitle(_ minutes: Int) -> String {
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? hourText : "\(hourText) \(rest) min"
    }

    // MARK: Nap window

    private var napSection: some View {
        Section {
            Toggle("Nap window reminder", isOn: $settings.napWindow.isEnabled)
            if settings.napWindow.isEnabled {
                Picker("Remind me", selection: $settings.napWindow.leadMinutes) {
                    ForEach(leadOptions, id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                Toggle("Also remind for bedtime", isOn: $settings.napWindow.includeBedtime)
            }
        } header: {
            Text(showName ? "\(babyName): naps" : "Naps")
        } footer: {
            if settings.napWindow.isEnabled {
                Text(napFooter)
            } else {
                Text("Get a heads-up shortly before \(babyName)'s next nap window opens. It uses the same estimate as Up next on Today.")
            }
        }
        .themedSection()
    }

    private var napFooter: String {
        var text = "Reminds you \(settings.napWindow.leadMinutes) min before \(babyName)'s predicted nap window opens"
        text += settings.napWindow.includeBedtime ? ", and before bedtime." : "."
        text += " It moves when you log a wake-up and goes away when a sleep starts. Estimates only, not medical advice."
        return text
    }

    private var leadOptions: [Int] {
        var options = NapWindowReminder.allowedLeadMinutes
        #if DEBUG
        options.insert(1, at: 0)
        #endif
        let current = settings.napWindow.leadMinutes
        if !options.contains(current) { options.append(current) }
        return options
    }

    // MARK: Daily

    private var dailySection: some View {
        Section {
            ForEach(settings.daily.sorted { $0.minutesOfDay < $1.minutesOfDay }) { reminder in
                DailyReminderRow(reminder: reminder, isOn: enabledBinding(reminder.id)) {
                    editing = DailyReminderEditorItem(reminder: reminder, isNew: false)
                }
            }
            .onDelete { offsets in
                let sorted = settings.daily.sorted { $0.minutesOfDay < $1.minutesOfDay }
                let ids = Set(offsets.map { sorted[$0].id })
                settings.daily.removeAll { ids.contains($0.id) }
            }
            Button {
                editing = DailyReminderEditorItem(reminder: DailyReminder(), isNew: true)
            } label: {
                Label("Add a daily reminder", systemImage: "plus.circle.fill")
            }
        } header: {
            Text(showName ? "\(babyName): every day" : "Every day")
        } footer: {
            if settings.daily.isEmpty {
                Text("For things like vitamin D drops at 9:00 AM. Each repeats daily.")
            }
        }
        .themedSection()
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { settings.daily.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { value in
                if let index = settings.daily.firstIndex(where: { $0.id == id }) {
                    settings.daily[index].isEnabled = value
                }
            }
        )
    }
}

// MARK: - Daily reminder row and editor

private struct DailyReminderEditorItem: Identifiable {
    let reminder: DailyReminder
    let isNew: Bool
    var id: UUID { reminder.id }
}

private struct DailyReminderRow: View {
    let reminder: DailyReminder
    @Binding var isOn: Bool
    let onEdit: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: reminder.kind.symbolName)
                        .foregroundStyle(theme.isNight ? theme.accent : .accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeText(reminder.minutesOfDay))
                            .font(.headline)
                            .foregroundStyle(theme.primary)
                        Text(reminder.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(theme.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .opacity(reminder.isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .contain)
    }
}

private struct DailyReminderEditor: View {
    @State private var draft: DailyReminder
    let isNew: Bool
    let babyName: String
    let onSave: (DailyReminder) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        reminder: DailyReminder,
        isNew: Bool,
        babyName: String,
        onSave: @escaping (DailyReminder) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self._draft = State(initialValue: reminder)
        self.isNew = isNew
        self.babyName = babyName
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(DailyReminderKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Time", selection: minutesBinding($draft.minutesOfDay), displayedComponents: .hourAndMinute)
                    TextField(DailyReminder(kind: draft.kind).displayLabel, text: $draft.label)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Reminder for \(babyName)")
                } footer: {
                    Text("Repeats every day at this time.")
                }
                .themedSection()

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete(draft.id)
                            dismiss()
                        } label: {
                            Text("Delete reminder")
                                .frame(maxWidth: .infinity)
                        }
                        .themedDestructive()
                    }
                    .themedSection()
                }
            }
            .themedList()
            .navigationTitle(isNew ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Time helpers

private func timeText(_ minutes: Int) -> String {
    let clamped = min(max(minutes, 0), 1439)
    let date = Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: .now) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
}

/// A time-of-day picker value for a stored "minutes since midnight".
private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
        get: {
            let clamped = min(max(minutes.wrappedValue, 0), 1439)
            return Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: .now) ?? .now
        },
        set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    )
}

#Preview {
    NavigationStack {
        RemindersSettingsView()
    }
    .previewEnvironment()
}
