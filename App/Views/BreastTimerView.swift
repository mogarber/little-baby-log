import SwiftUI
import CoreData
import BabyLogKit

/// Sheet item for presenting the nursing timer.
struct NursingSheetItem: Identifiable {
    let event: LogEvent
    let suggestedSide: BreastSide?

    var id: NSManagedObjectID { event.objectID }
}

/// Big two-sided nursing timer. Every tap is saved immediately so the other caregiver sees it live.
struct BreastTimerView: View {
    @ObservedObject var event: LogEvent
    let suggestedSide: BreastSide?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var confirmDiscard = false
    @State private var tapCount = 0

    private var isGone: Bool {
        event.isDeleted || event.managedObjectContext == nil
    }

    private var hasStarted: Bool {
        event.activeSide != nil || event.totalBreastSeconds() > 0
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("Nursing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.impact, trigger: tapCount)
        .confirmationDialog("Discard this feed?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discard() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The time you've tracked will be deleted.")
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            removeIfNeverStarted()
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Content

    private func content(now: Date) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DurationFormat.clock(isGone ? 0 : event.totalBreastSeconds(at: now)))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let start = event.startDate, !isGone {
                    Text("Started " + start.formatted(date: .omitted, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                sideTile(.left, now: now)
                sideTile(.right, now: now)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                    finish()
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(EventKind.breastfeed.color)

                Button(role: .destructive) {
                    confirmDiscard = true
                } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func sideTile(_ side: BreastSide, now: Date) -> some View {
        let active = event.activeSide == side
        let seconds = isGone ? 0 : event.breastSeconds(side, at: now)
        let showNext = !hasStarted && suggestedSide == side

        return Button {
            toggle(side)
        } label: {
            VStack(spacing: 10) {
                Text(side.title)
                    .font(.title2.weight(.bold))
                Text(DurationFormat.clock(seconds))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: active ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                nextBadge(visible: showNext, active: active)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(active ? side.color : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(showNext ? side.color : Color.clear, lineWidth: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side.title) side")
        .accessibilityValue(active ? "Running, \(DurationFormat.clock(seconds))" : "Paused, \(DurationFormat.clock(seconds))")
        .accessibilityHint(active ? "Pauses this side" : "Starts this side")
    }

    @ViewBuilder
    private func nextBadge(visible: Bool, active: Bool) -> some View {
        if visible {
            Text("Next")
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.12)))
        } else {
            Text(active ? "Running" : " ")
                .font(.footnote.weight(.medium))
                .padding(.vertical, 4)
                .opacity(active ? 0.9 : 0)
        }
    }

    // MARK: Actions

    private func toggle(_ side: BreastSide) {
        guard !isGone else { return }
        event.toggleSide(side)
        context.saveIfNeeded()
        tapCount += 1
    }

    private func finish() {
        guard !isGone else {
            dismiss()
            return
        }
        if event.totalBreastSeconds() < 1 {
            context.delete(event)
        } else {
            event.finishNursing()
        }
        context.saveIfNeeded()
        Haptics.success()
        dismiss()
    }

    private func discard() {
        if !isGone {
            context.delete(event)
            context.saveIfNeeded()
        }
        dismiss()
    }

    private func removeIfNeverStarted() {
        guard !isGone, !hasStarted else { return }
        context.delete(event)
        context.saveIfNeeded()
    }
}

#Preview {
    BreastTimerView(event: {
        let event = LogEvent.create(kind: .breastfeed, for: PreviewData.baby, in: PersistenceController.preview.viewContext)
        event.startSide(.left)
        return event
    }(), suggestedSide: .right)
    .previewEnvironment()
}
