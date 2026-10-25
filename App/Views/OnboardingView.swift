import SwiftUI
import BabyLogKit

struct OnboardingView: View {
    let onCreate: (String, Date) -> Void

    @Environment(\.appTheme) private var theme

    @State private var name = ""
    @State private var birthDate = Date.now
    @FocusState private var nameFocused: Bool

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        KindIcon(kind: .sleep, size: 52)
                        KindIcon(kind: .breastfeed, size: 52)
                        KindIcon(kind: .diaper, size: 52)
                    }
                    Text("Welcome to Little Baby Log")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Sleep, feeds and diapers, one tap at a time. Free, private, and shared with your family through your own iCloud.")
                        .font(.body)
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 0) {
                    TextField("Baby's name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .font(.title3)
                        .padding(16)
                    Divider()
                    DatePicker(
                        "Birthday",
                        selection: $birthDate,
                        in: ...latestBirthDate,
                        displayedComponents: .date
                    )
                    .font(.title3)
                    .padding(16)
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    Haptics.success()
                    onCreate(trimmedName, birthDate)
                } label: {
                    Text("Start tracking")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .themedOnColor()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedName.isEmpty)

                Text("Already invited by another caregiver? Open their invitation on this phone and your baby will appear here once iCloud syncs.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .themedForeground()
    }
}

#Preview {
    OnboardingView { _, _ in }
}
