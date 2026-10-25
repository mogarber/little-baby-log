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

    @State private var babySheet: BabySheet?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?

    var body: some View {
        Form {
            babiesSection
            caregiversSection
            unitsSection
            widgetsSection
            dataSection
            aboutSection
        }
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
    }

    private var widgetsSection: some View {
        Section {
            Label {
                Text("Touch and hold an empty spot on the Home Screen, tap Edit, then Add Widget, and choose Little Baby Log. Start nursing or log a diaper without opening the app.")
            } icon: {
                Image(systemName: "rectangle.3.group.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Label {
                Text("For the Lock Screen, touch and hold it, tap Customize, then add a widget under the clock. Running sleep and nursing timers also show up on the Lock Screen and in the Dynamic Island.")
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text("To show a different baby in a widget, touch and hold it and tap Edit Widget.")
        }
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let birthDate = baby.birthDate {
                    Text(BabyAge.description(birthDate: birthDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
    @State private var errorText: String?

    var body: some View {
        let _ = refreshTick
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
        .alert(
            "Couldn't open sharing",
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
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
        isWorking = true
        let newCoordinator = CloudSharingCoordinator(persistence: persistence, baby: baby) {
            refreshTick += 1
        }
        coordinator = newCoordinator
        Task {
            do {
                try await newCoordinator.present()
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
