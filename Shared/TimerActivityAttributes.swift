import ActivityKit
import Foundation
import BabyLogKit

/// Live Activity for a running sleep or nursing timer. All times are absolute dates so the clock ticks
/// without any updates (`Text(timerInterval:)`).
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        /// Nursing: banked (paused) seconds per side. Sleep: 0.
        var leftSeconds: TimeInterval
        var rightSeconds: TimeInterval
        var activeSide: BreastSide?
        var activeSideStartedAt: Date?
        /// Nursing with no side running. Sleep is never paused.
        var isPaused: Bool

        func seconds(_ side: BreastSide, at now: Date) -> TimeInterval {
            var seconds = side == .left ? leftSeconds : rightSeconds
            if activeSide == side, let started = activeSideStartedAt {
                seconds += max(0, now.timeIntervalSince(started))
            }
            return seconds
        }

        func nursingTotal(at now: Date) -> TimeInterval {
            seconds(.left, at: now) + seconds(.right, at: now)
        }

        /// Start of a `timerInterval` range showing the live total, for a running nursing timer.
        var nursingReferenceStart: Date? {
            guard !isPaused, activeSide != nil, let started = activeSideStartedAt else { return nil }
            return started.addingTimeInterval(-(leftSeconds + rightSeconds))
        }
    }

    var babyID: String
    var babyName: String
    var kind: EventKind
}
