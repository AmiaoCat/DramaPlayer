import Foundation

/// A playback attempt's events. Subscribe before activating the session to capture startup.
public struct PlaybackDiagnosticEvent: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case completed
        case interrupted
        case accessRequired
        case failed(PlaybackFailure)
    }

    public enum Kind: Sendable, Equatable {
        case started
        /// Time from eligible play intent to playback with a displayable first frame.
        case firstFrame(seconds: TimeInterval)
        /// Post-first-frame buffering. An interruption closes the interval without a recovery.
        case rebufferingEnded(seconds: TimeInterval, recovered: Bool)
        case cachedMediaFallback
        case finished(Outcome)
    }

    public let attemptID: UUID
    public let itemID: String
    public let kind: Kind
}

struct PlaybackAttempt {
    let itemID: String
    let start: TimeInterval
    private let id = UUID()
    private var reachedFirstFrame = false
    private var bufferingSince: TimeInterval?

    init(itemID: String, start: TimeInterval) {
        self.itemID = itemID
        self.start = start
    }

    func event(_ kind: PlaybackDiagnosticEvent.Kind) -> PlaybackDiagnosticEvent {
        PlaybackDiagnosticEvent(attemptID: id, itemID: itemID, kind: kind)
    }

    mutating func update(state: PlaybackState, firstFrameReady: Bool, seeking: Bool,
                         now: TimeInterval, emit: (PlaybackDiagnosticEvent) -> Void) {
        if state == .playing, firstFrameReady, !reachedFirstFrame, !seeking {
            reachedFirstFrame = true
            emit(event(.firstFrame(seconds: now - start)))
        }
        guard reachedFirstFrame else { return }
        if state == .buffering, !seeking {
            if bufferingSince == nil { bufferingSince = now }
        } else if let since = bufferingSince {
            bufferingSince = nil
            emit(event(.rebufferingEnded(seconds: now - since, recovered: state == .playing && !seeking)))
        }
    }

    func finish(_ outcome: PlaybackDiagnosticEvent.Outcome, now: TimeInterval,
                emit: (PlaybackDiagnosticEvent) -> Void) {
        if let since = bufferingSince {
            emit(event(.rebufferingEnded(seconds: now - since, recovered: false)))
        }
        emit(event(.finished(outcome)))
    }
}
