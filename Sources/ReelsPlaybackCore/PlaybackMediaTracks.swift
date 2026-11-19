import Foundation

public enum PlaybackMediaTrackKind: Hashable, Sendable {
    case audio
    case subtitles
}

public struct PlaybackMediaTrack: Identifiable, Sendable, Equatable {
    /// Unique within the returned group. Load a fresh group after changing the source.
    public let id: Int
    public let displayName: String
    public let languageTag: String?
}

public struct PlaybackMediaTrackGroup: Sendable, Equatable {
    public let kind: PlaybackMediaTrackKind
    public let tracks: [PlaybackMediaTrack]
    public let selectedTrackID: Int?
    public let allowsDisabling: Bool
    let generation: UUID
}

public enum PlaybackMediaTrackSelection: Sendable, Equatable {
    case automatic
    case off
    case track(Int)
}
