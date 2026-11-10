/// A focus group allows only one session to play at a time.
@MainActor
public final class PlaybackFocus {
    public static let shared = PlaybackFocus()
    private weak var current: PlaybackSession?

    public init() {}

    func claim(_ session: PlaybackSession) {
        guard current !== session else { return }
        let previous = current
        current = session
        previous?.focusWasTaken()
    }

    func release(_ session: PlaybackSession) {
        if current === session { current = nil }
    }
}
