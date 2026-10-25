import SwiftUI
import CoreData
import BabyLogKit

struct RootView: View {
    @Environment(\.persistence) private var persistence
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""
    /// A `littlebabylog://` link waiting for Today to act on it. Lives here, not in a tab, because
    /// switching babies rebuilds `MainTabView`.
    @State private var pendingLink: DeepLink?

    private var selectedBaby: Baby? {
        babies.first(where: { $0.uuid?.uuidString == selectedBabyID }) ?? babies.first
    }

    var body: some View {
        Group {
            if let error = persistence.loadError {
                ContentUnavailableView {
                    Label("Couldn't open your data", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            } else if let baby = selectedBaby {
                MainTabView(baby: baby, link: $pendingLink)
                    .id(baby.objectID)
            } else {
                OnboardingView { name, birthDate in
                    let baby = Baby.create(name: name, birthDate: birthDate, in: context)
                    context.saveIfNeeded()
                    selectedBabyID = baby.uuid?.uuidString ?? ""
                }
            }
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) { open(link) }
        }
        // A tapped reminder notification asks for Today (see `ReminderResponder`). The link may have been parked
        // before this view existed, so also look when it appears.
        .onReceive(NotificationCenter.default.publisher(for: DeepLinkRouter.didReceiveLink)) { _ in
            if let link = DeepLinkRouter.take() { open(link) }
        }
        .task {
            if let link = DeepLinkRouter.take() { open(link) }
        }
    }

    private func open(_ link: DeepLink) {
        if let id = link.babyID, babies.contains(where: { $0.uuid == id }) {
            selectedBabyID = id.uuidString
        }
        pendingLink = link
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
