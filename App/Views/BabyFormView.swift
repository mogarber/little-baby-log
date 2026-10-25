import SwiftUI
import CoreData
import BabyLogKit

/// Add a baby (`baby == nil`) or edit one. Saves itself, then calls `onSave` with the saved baby.
struct BabyFormView: View {
    let baby: Baby?
    let onSave: (Baby) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.persistence) private var persistence

    @State private var name: String
    @State private var birthDate: Date
    @State private var confirmDelete = false

    init(baby: Baby?, onSave: @escaping (Baby) -> Void) {
        self.baby = baby
        self.onSave = onSave
        _name = State(initialValue: baby?.name ?? "")
        _birthDate = State(initialValue: baby?.birthDate ?? Date.now)
    }

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canDelete: Bool {
        guard let baby else { return false }
        return !persistence.isInSharedStore(baby)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    DatePicker(
                        "Birthday",
                        selection: $birthDate,
                        in: ...latestBirthDate,
                        displayedComponents: .date
                    )
                } footer: {
                    Text("Not born yet? Use the due date and update it later.")
                }

                if canDelete {
                    Section {
                        Button("Delete baby and all entries", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(baby == nil ? "Add a baby" : "Edit baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete \(baby?.displayName ?? "this baby")?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { deleteBaby() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every entry for this baby, and for anyone you've shared them with. It can't be undone.")
            }
        }
    }

    private func save() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        let saved: Baby
        if let baby {
            baby.name = trimmed
            baby.birthDate = birthDate
            saved = baby
        } else {
            saved = Baby.create(name: trimmed, birthDate: birthDate, in: context)
        }
        context.saveIfNeeded()
        Haptics.success()
        onSave(saved)
        dismiss()
    }

    private func deleteBaby() {
        if let baby {
            context.delete(baby)
            context.saveIfNeeded()
        }
        dismiss()
    }
}

#Preview("Add") {
    BabyFormView(baby: nil) { _ in }
        .previewEnvironment()
}

#Preview("Edit") {
    BabyFormView(baby: PreviewData.baby) { _ in }
        .previewEnvironment()
}
