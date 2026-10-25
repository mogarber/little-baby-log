import Foundation

/// Breastfeeding timer. Per-side seconds are banked in `leftSeconds`/`rightSeconds`;
/// the side currently running is `activeSide` since `activeSideStartedAt`.
extension LogEvent {
    public func breastSeconds(_ side: BreastSide, at now: Date = .now) -> TimeInterval {
        var seconds = side == .left ? leftSeconds : rightSeconds
        if activeSide == side, let started = activeSideStartedAt {
            seconds += max(0, now.timeIntervalSince(started))
        }
        return seconds
    }

    public func totalBreastSeconds(at now: Date = .now) -> TimeInterval {
        breastSeconds(.left, at: now) + breastSeconds(.right, at: now)
    }

    /// Pauses the other side first (banking its time), then starts `side`. Sets `lastSide`.
    public func startSide(_ side: BreastSide, at now: Date = .now) {
        if activeSide == side, activeSideStartedAt != nil { return }
        pauseNursing(at: now)
        activeSide = side
        activeSideStartedAt = now
        lastSide = side
        modifiedAt = now
    }

    /// Banks the elapsed time of the running side and clears the active side.
    public func pauseNursing(at now: Date = .now) {
        if let side = activeSide, let started = activeSideStartedAt {
            let elapsed = max(0, now.timeIntervalSince(started))
            switch side {
            case .left: leftSeconds += elapsed
            case .right: rightSeconds += elapsed
            }
        }
        activeSide = nil
        activeSideStartedAt = nil
        modifiedAt = now
    }

    /// Active side → pause; otherwise start it.
    public func toggleSide(_ side: BreastSide, at now: Date = .now) {
        if activeSide == side {
            pauseNursing(at: now)
        } else {
            startSide(side, at: now)
        }
    }

    /// Pauses and ends the session at `now`.
    public func finishNursing(at now: Date = .now) {
        pauseNursing(at: now)
        endDate = now
    }
}
