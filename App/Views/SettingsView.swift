import SwiftUI
import CloudKit
import CoreData
import BabyLogKit

private enum BabySheet: Identifiable {
    case add
    case edit(Baby)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let baby):
            return "edit-" + baby.objectID.uriRepresentation().absoluteString
        }
    }
}

struct SettingsView: View {
    @Environment(\.persistence) private var persistence
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>

    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem
    @AppStorage(Prefs.appearanceMode) private var appearanceMode: AppearanceMode = Prefs.defaultAppearanceMode
    @AppStorage(Prefs.nightStartMinutes) private var nightStartMinutes = NightSchedule.defaultStartMinutes
    @AppStorage(Prefs.nightEndMinutes) private var nightEndMinutes = NightSchedule.defaultEndMinutes
    @AppStorage(Prefs.dimScreenAtNight) private var dimScreenAtNight = false
    @AppStorage(Prefs.keepScreenOnWhileNursing) private var keepScreenOnWhileNursing = false
    @Environment(\.appTheme) private var theme

    @State private var babySheet: BabySheet?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var remindersOn = false

    var body: some View {
        Form {
            babiesSection
            remindersSection
            caregiversSection
            syncSection
            unitsSection
            appearanceSection
            nursingTimerSection
            widgetsSection
            dataSection
            aboutSection
        }
        .themedList()
        .navigationTitle("Settings")
        .sheet(item: $babySheet) { sheet in
            switch sheet {
            case .add:
                BabyFormView(baby: nil) { saved in
                    selectedBabyID = saved.uuid?.uuidString ?? selectedBabyID
                }
            case .edit(let baby):
                BabyFormView(baby: baby) { _ in }
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Couldn't export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Sections

    private var babiesSection: some View {
        Section {
            ForEach(babies, id: \.objectID) { baby in
                Button {
                    babySheet = .edit(baby)
                } label: {
                    BabyRow(baby: baby)
                }
                .buttonStyle(.plain)
            }
            Button {
                babySheet = .add
            } label: {
                Label("Add a baby", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Babies")
        }
        .themedSection()
    }

    private var remindersSection: some View {
        Section {
            NavigationLink {
                RemindersSettingsView()
            } label: {
                HStack {
                    Label("Reminders", systemImage: "bell.badge.fill")
                    Spacer()
                    Text(remindersOn ? "On" : "Off")
                        .foregroundStyle(theme.secondary)
                }
            }
        } footer: {
            Text("Feed every few hours, a heads-up before nap windows, or set times each day. Reminders stay on this phone.")
        }
        .themedSection()
        .onAppear { remindersOn = ReminderSettingsStore().hasAnythingEnabled }
    }

    private var syncSection: some View {
        Section {
            ICloudSyncRow()
        } header: {
            Text("iCloud sync")
        }
        .themedSection()
    }

    private var caregiversSection: some View {
        Section {
            ForEach(babies, id: \.objectID) { baby in
                CaregiverRow(baby: baby)
            }
        } header: {
            Text("Caregivers")
        } footer: {
            if persistence.isCloudSyncEnabled {
                Text("Invite a partner or another caregiver. Everything you log appears on their phone, and theirs on yours, through iCloud.")
            } else {
                Text("This build of the app was made without iCloud turned on, so sharing isn't available. Your data stays on this phone.")
            }
        }
        .themedSection()
    }

    private var unitsSection: some View {
        Section {
            Picker("Liquids", selection: $volumeUnit) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Picker("Weight and length", selection: $unitSystem) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.title).tag(system)
                }
            }
        } header: {
            Text("Units")
        }
        .themedSection()
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if appearanceMode == .nightSchedule {
                DatePicker("From", selection: minutesBinding($nightStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: minutesBinding($nightEndMinutes), displayedComponents: .hourAndMinute)
            }

            if appearanceMode.canShowNight {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Dim screen at night", isOn: $dimScreenAtNight)
                    BatteryImpactNote("Lowers the screen brightness while Night is showing, which saves battery.", effect: .saves)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Appearance")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if appearanceMode == .nightSchedule {
                    Text("Night turns on at \(Self.timeString(nightStartMinutes)) and off at \(Self.timeString(nightEndMinutes)). The rest of the time the app follows your phone's Light or Dark setting.")
                } else if appearanceMode == .night {
                    Text("Night is a dim, warm, true-black look for feeding in the dark.")
                }
                Text("Widgets and Live Activities follow your phone's Light or Dark setting. iOS doesn't let apps change that.")
            }
        }
        .themedSection()
    }

    private var nursingTimerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep screen on during nursing timer", isOn: $keepScreenOnWhileNursing)
                BatteryImpactNote("Keeps your screen on while the timer is open, which uses more battery.")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Nursing timer")
        }
        .themedSection()
    }

    private var widgetsSection: some View {
        Section {
            Label {
                Text("Touch and hold an empty spot on the Home Screen, tap Edit, then Add Widget, and choose Little Baby Log. Start nursing or log a diaper without opening the app.")
            } icon: {
                Image(systemName: "rectangle.3.group.fill")
                    .foregroundStyle(theme.accent)
            }
            Label {
                Text("For the Lock Screen, touch and hold it, tap Customize, then add a widget under the clock. Running sleep and nursing timers also show up on the Lock Screen and in the Dynamic Island.")
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(theme.accent)
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text("To show a different baby in a widget, touch and hold it and tap Edit Widget.")
        }
        .themedSection()
    }

    private var dataSection: some View {
        Section {
            Button {
                exportCSV()
            } label: {
                Label("Export all data (CSV)", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("A spreadsheet of every entry for every baby.")
        }
        .themedSection()
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppConfig.versionString)
            Link(destination: AppConfig.sourceCodeURL) {
                Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Little Baby Log is free software, released under the GNU GPL-3.0. No accounts, no ads, no tracking.")
        }
        .themedSection()
    }

    // MARK: Times

    /// A time-of-day picker value for a stored "minutes since midnight".
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private static func timeString(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Export

    private func exportCSV() {
        let request: NSFetchRequest<LogEvent> = LogEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        do {
            let events = try context.fetch(request)
            let csv = CSVExporter.csv(for: events)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let filename = "LittleBabyLog-\(formatter.string(from: .now)).csv"

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// A baby's name and age. Observes the baby so renames show up immediately.
private struct BabyRow: View {
    @ObservedObject var baby: Baby
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.primary)
                if let birthDate = baby.birthDate {
                    Text(BabyAge.description(birthDate: birthDate))
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// One baby's sharing status plus an Invite / Manage button.
struct CaregiverRow: View {
    @ObservedObject var baby: Baby

    @Environment(\.persistence) private var persistence
    @State private var coordinator: CloudSharingCoordinator?
    @State private var isWorking = false
    @State private var refreshTick = 0
    @State private var problem: CloudSyncProblem?

    var body: some View {
        let _ = refreshTick
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(baby.displayName)
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView()
                } else {
                    Button(shareButtonTitle) {
                        startSharing()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!persistence.isCloudSyncEnabled)
                }
            }
            if let problem {
                SyncProblemView(problem: problem) { self.problem = nil }
            }
        }
    }

    private var shareButtonTitle: String {
        persistence.isShared(baby) ? "Manage" : "Invite"
    }

    private var statusText: String {
        guard persistence.isCloudSyncEnabled else { return "iCloud is off in this build" }

        if persistence.isInSharedStore(baby) {
            if let share = persistence.existingShare(for: baby),
               let components = share.owner.userIdentity.nameComponents {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty { return "Shared with you by \(name)" }
            }
            return "Shared with you"
        }

        if let share = persistence.existingShare(for: baby) {
            let others = share.participants.filter { $0.role != .owner }.count
            switch others {
            case 0: return "Not shared"
            case 1: return "Shared with 1 person"
            default: return "Shared with \(others) people"
            }
        }
        return "Not shared"
    }

    private func startSharing() {
        problem = nil
        // No point waiting for CloudKit to fail when we already know there's no iCloud account.
        if CloudSyncStatus.shared.state == .notSignedIn {
            problem = CloudSyncProblem(
                kind: .notSignedIn,
                message: CloudSyncProblem.message(for: .notSignedIn),
                technicalDetails: "iCloud account status: no account (CKAccountStatus.noAccount)"
            )
            return
        }
        isWorking = true
        let newCoordinator = CloudSharingCoordinator(persistence: persistence, baby: baby) {
            refreshTick += 1
        }
        coordinator = newCoordinator
        Task {
            do {
                try await newCoordinator.present()
            } catch {
                problem = CloudSyncProblem.classify(error)
            }
            isWorking = false
        }
    }
}

/// The "iCloud sync" status line: Syncing / Up to date / Not signed in / Error, with the plain-language reason and a
/// Details disclosure on errors.
private struct ICloudSyncRow: View {
    @State private var status = CloudSyncStatus.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label {
                    Text("iCloud sync")
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 8)
                if status.state == .syncing {
                    ProgressView()
                }
                Text(title)
                    .foregroundStyle(theme.secondary)
            }
            if case .error(let problem) = status.state {
                SyncProblemView(problem: problem, onDismiss: nil)
            } else if status.state == .notSignedIn {
                Text("Sign in to iCloud in the Settings app to sync and share.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            } else if status.state == .unavailable {
                Text("iCloud is restricted or unavailable on this phone right now.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .onAppear { status.refreshAccount() }
    }

    private var title: String {
        switch status.state {
        case .off: return "Off in this build"
        case .checking: return "Checking"
        case .notSignedIn: return "Not signed in"
        case .unavailable: return "Unavailable"
        case .syncing: return "Syncing"
        case .upToDate: return "Up to date"
        case .error: return "Error"
        }
    }

    private var symbol: String {
        switch status.state {
        case .off, .checking: return "icloud.slash"
        case .notSignedIn, .unavailable: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .upToDate: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    private var tint: Color {
        switch status.state {
        case .upToDate: return theme.isNight ? theme.accent : .green
        case .error: return theme.destructive
        case .notSignedIn, .unavailable: return theme.isNight ? theme.accent : .orange
        default: return theme.isNight ? theme.accent : .accentColor
        }
    }
}

/// A sync or sharing problem in plain language, with the technical text behind a "Details" disclosure so testers
/// can still copy it into a bug report.
private struct SyncProblemView: View {
    let problem: CloudSyncProblem
    var onDismiss: (() -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(problem.message)
                .font(.footnote)
                .foregroundStyle(theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
            if !problem.technicalDetails.isEmpty {
                DisclosureGroup("Details") {
                    Text(problem.technicalDetails)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
