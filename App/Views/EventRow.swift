import SwiftUI
import BabyLogKit

/// One line in a timeline: icon, kind, one-line detail, and the time.
struct EventRow: View {
    @ObservedObject var event: LogEvent

    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    var body: some View {
        if event.isDeleted || event.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                KindIcon(kind: event.kind, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.kind.title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(event.startDate ?? .now, style: .time)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    private var detail: String {
        let describer = EventDescriber(volumeUnit: volumeUnit, unitSystem: unitSystem)
        return describer.summary(for: event)
    }
}

#Preview {
    List {
        ForEach(PreviewData.events(limit: 4), id: \.objectID) { event in
            EventRow(event: event)
        }
    }
    .previewEnvironment()
}
