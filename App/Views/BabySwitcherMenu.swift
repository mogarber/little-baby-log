import SwiftUI
import CoreData
import BabyLogKit

/// Toolbar menu for switching babies. Renders nothing when there is only one baby.
struct BabySwitcherMenu: View {
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""

    private var selected: Baby? {
        babies.first(where: { $0.uuid?.uuidString == selectedBabyID }) ?? babies.first
    }

    var body: some View {
        if babies.count > 1 {
            Menu {
                ForEach(babies, id: \.objectID) { baby in
                    Button {
                        selectedBabyID = baby.uuid?.uuidString ?? ""
                    } label: {
                        if baby.objectID == selected?.objectID {
                            Label(baby.displayName, systemImage: "checkmark")
                        } else {
                            Text(baby.displayName)
                        }
                    }
                }
            } label: {
                Label("Switch baby", systemImage: "person.2.fill")
            }
        }
    }
}

#Preview {
    NavigationStack {
        Text("Hello")
            .toolbar { BabySwitcherMenu() }
    }
    .previewEnvironment()
}
