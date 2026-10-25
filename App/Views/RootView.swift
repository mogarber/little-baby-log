import SwiftUI
import CoreData
import BabyLogKit

struct RootView: View {
    @Environment(\.persistence) private var persistence
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""

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
                MainTabView(baby: baby)
                    .id(baby.objectID)
            } else {
                OnboardingView { name, birthDate in
                    let baby = Baby.create(name: name, birthDate: birthDate, in: context)
                    context.saveIfNeeded()
                    selectedBabyID = baby.uuid?.uuidString ?? ""
                }
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
