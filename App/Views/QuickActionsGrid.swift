import SwiftUI
import BabyLogKit

/// Big one-tap tiles for every kind of entry.
struct QuickActionsGrid: View {
    @Environment(\.appTheme) private var theme

    let isSleeping: Bool
    let onTap: (EventKind) -> Void
    let onLogPast: (EventKind) -> Void
    let onQuickDiaper: (DiaperKind) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(EventKind.allCases) { kind in
                tile(for: kind)
            }
        }
    }

    private func title(for kind: EventKind) -> String {
        if kind == .sleep && isSleeping { return "Wake up" }
        return kind.title
    }

    private func tile(for kind: EventKind) -> some View {
        // A Menu with a primary action (tap = log, long-press = menu) instead of
        // Button + .contextMenu: inside a List row, every tile's .contextMenu
        // resolved to the first tile's menu ("Log past sleep").
        Menu {
            Button {
                onLogPast(kind)
            } label: {
                Label("Log past \(kind.title.lowercased())", systemImage: "clock.arrow.circlepath")
            }
            if kind == .diaper {
                Divider()
                Button {
                    onQuickDiaper(.wet)
                } label: {
                    Label("Wet", systemImage: DiaperKind.wet.symbolName)
                }
                Button {
                    onQuickDiaper(.dirty)
                } label: {
                    Label("Dirty", systemImage: DiaperKind.dirty.symbolName)
                }
                Button {
                    onQuickDiaper(.mixed)
                } label: {
                    Label("Wet + dirty", systemImage: DiaperKind.mixed.symbolName)
                }
            }
        } label: {
            VStack(spacing: 6) {
                KindIcon(kind: kind, size: 58)
                Text(title(for: kind))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(Rectangle())
        } primaryAction: {
            onTap(kind)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title(for: kind))
    }
}

#Preview {
    List {
        QuickActionsGrid(isSleeping: false, onTap: { _ in }, onLogPast: { _ in }, onQuickDiaper: { _ in })
    }
}
