import SwiftUI
import BabyLogKit

extension EventKind {
    var color: Color {
        switch self {
        case .sleep: return .indigo
        case .breastfeed: return .pink
        case .bottle: return .orange
        case .solids: return .green
        case .diaper: return .teal
        case .pump: return .purple
        case .growth: return .blue
        case .medicine: return .red
        }
    }
}

extension BreastSide {
    /// Left and right get slightly different tints so they are easy to tell apart half asleep.
    var color: Color {
        switch self {
        case .left: return .pink
        case .right: return .purple
        }
    }
}

/// A white SF Symbol on a gradient circle in the kind's color.
struct KindIcon: View {
    let kind: EventKind
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [kind.color.opacity(0.75), kind.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(EventKind.allCases) { kind in
            KindIcon(kind: kind, size: 36)
        }
    }
    .padding()
}
