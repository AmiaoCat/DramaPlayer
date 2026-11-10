import Foundation

public struct PlaybackItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let coverURL: URL?
    public let resumePosition: TimeInterval

    public init(id: String, coverURL: URL? = nil, resumePosition: TimeInterval = 0) {
        self.id = id
        self.coverURL = coverURL
        self.resumePosition = resumePosition.isFinite ? max(0, resumePosition) : 0
    }
}

public struct PlaybackSource: Sendable, Equatable {
    public let url: URL
    public let cacheKey: String
    public let expiresAt: Date?

    public init(url: URL, cacheKey: String, expiresAt: Date? = nil) {
        self.url = url
        self.cacheKey = cacheKey
        self.expiresAt = expiresAt
    }

    var isValid: Bool { expiresAt.map { $0 > .now } ?? true }
}

public enum PlaybackPurpose: Sendable, Equatable { case playback, preload }

public enum PlaybackAccess: Sendable, Equatable {
    case allowed(PlaybackSource)
    case requiresUserAction
    case unavailable
}

public protocol PlaybackSourceProvider: Sendable {
    /// Preload requests may inspect authorization and must be free of purchase or unlock side effects.
    func source(for item: PlaybackItem, purpose: PlaybackPurpose) async throws -> PlaybackAccess
}

public struct PlaybackSourceResolver: PlaybackSourceProvider {
    private let resolve: @Sendable (PlaybackItem, PlaybackPurpose) async throws -> PlaybackAccess

    public init(_ resolve: @escaping @Sendable (PlaybackItem, PlaybackPurpose) async throws -> PlaybackAccess) {
        self.resolve = resolve
    }

    public func source(for item: PlaybackItem, purpose: PlaybackPurpose) async throws -> PlaybackAccess {
        try await resolve(item, purpose)
    }
}

public struct PlaybackMedia: Sendable, Equatable {
    public let url: URL
    public let isCached: Bool

    public init(url: URL, isCached: Bool = false) {
        self.url = url
        self.isCached = isCached
    }
}

public protocol PlaybackMediaCache: Sendable {
    func media(for source: PlaybackSource) async throws -> PlaybackMedia
    func prefetch(_ source: PlaybackSource) async throws
    func invalidate(_ source: PlaybackSource) async
}

public extension PlaybackMediaCache {
    func prefetch(_ source: PlaybackSource) async throws {}
    func invalidate(_ source: PlaybackSource) async {}
}

public struct DirectPlaybackMediaCache: PlaybackMediaCache {
    public init() {}
    public func media(for source: PlaybackSource) async throws -> PlaybackMedia {
        PlaybackMedia(url: source.url)
    }
}

/// Bridges an app-owned disk or proxy cache without adding a package dependency.
public struct PlaybackCacheAdapter: PlaybackMediaCache {
    private let resolve: @Sendable (PlaybackSource) async throws -> PlaybackMedia
    private let warm: @Sendable (PlaybackSource) async throws -> Void
    private let remove: @Sendable (PlaybackSource) async -> Void

    public init(resolve: @escaping @Sendable (PlaybackSource) async throws -> PlaybackMedia,
                prefetch: @escaping @Sendable (PlaybackSource) async throws -> Void = { _ in },
                invalidate: @escaping @Sendable (PlaybackSource) async -> Void = { _ in }) {
        self.resolve = resolve
        warm = prefetch
        remove = invalidate
    }

    public func media(for source: PlaybackSource) async throws -> PlaybackMedia { try await resolve(source) }
    public func prefetch(_ source: PlaybackSource) async throws { try await warm(source) }
    public func invalidate(_ source: PlaybackSource) async { await remove(source) }
}

public struct PlaybackConfiguration: Sendable {
    public enum Mode: Sendable { case single, vertical }
    public enum Preload: Sendable { case disabled, preparedPlayer, mediaBytes }
    public enum EndBehavior: Sendable { case stop, loop, advance }

    public let mode: Mode
    public let autoplay: Bool
    public let preload: Preload
    public let endBehavior: EndBehavior
    public let preparedItemLimit: Int
    public let retention: TimeInterval
    public let rates: [Float]

    public init(mode: Mode = .single, autoplay: Bool = true, preload: Preload = .preparedPlayer,
                endBehavior: EndBehavior = .stop, preparedItemLimit: Int = 3,
                retention: TimeInterval = 120, rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]) {
        self.mode = mode
        self.autoplay = autoplay
        self.preload = preload
        self.endBehavior = endBehavior
        self.preparedItemLimit = min(max(preparedItemLimit, 1), 3)
        self.retention = retention.isFinite ? max(retention, 0) : 120
        self.rates = Array(Set(rates.filter { $0.isFinite && $0 > 0 } + [1])).sorted()
    }
}

public enum PlaybackState: Sendable, Equatable {
    case idle, preparing, ready, playing, buffering, paused, ended
    case accessRequired
    case failed(PlaybackFailure)
}

public enum PlaybackFailure: Error, Sendable, Equatable {
    case sourceUnavailable
    case sourceExpired
    case playbackFailed
}

public enum PlaybackSuspension: Hashable, Sendable {
    case background, interruption, overlay
    case custom(String)
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public let itemID: String?
    public let state: PlaybackState
    public let position: TimeInterval
    public let duration: TimeInterval?
    public let bufferedUntil: TimeInterval
    public let rate: Float
    public let wantsPlayback: Bool
    public let firstFrameReady: Bool
    public let isScrubbing: Bool
}

public enum PlaybackEvent: Sendable, Equatable {
    case queueChanged
    case snapshot(PlaybackSnapshot)
    case presentationChanged(String)
    case ended(String)
}
