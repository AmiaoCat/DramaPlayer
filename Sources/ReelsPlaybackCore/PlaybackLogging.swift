import Foundation
import OSLog

public enum PlaybackLogLevel: Int, Comparable, Sendable {
    case debug, info, warning, error

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PlaybackLogEntry: Sendable, Equatable {
    public enum Event: String, Sendable {
        case queueUpdated, selectionChanged, activated, deactivated, retryRequested, sourcesInvalidated
        case preloadPolicyChanged, streamPreferencesChanged, memoryPressure
        case sourceRequested, accessRequired, mediaResolved, cacheLookupFailed, cachedMediaFallback
        case prefetchRequested, prefetchFinished, prefetchCancelled, prefetchSkipped, prefetchFailed
        case loadTimedOut, playbackFailed, attemptStarted, firstFrame, rebufferingEnded, attemptFinished
    }

    public let timestamp: Date
    public let sessionID: UUID
    public let level: PlaybackLogLevel
    public let event: Event
    /// Supplied only when the host enables identifiers. Use opaque, non-sensitive episode IDs.
    public let itemID: String?
    /// SDK-defined fields. Resolved URLs, cache keys and error messages are omitted.
    public let fields: [String: String]
}

public struct PlaybackLogger: Sendable {
    public let minimumLevel: PlaybackLogLevel
    public let includesItemIdentifiers: Bool
    private let sink: @Sendable (PlaybackLogEntry) -> Void

    /// The sink runs inline. Dispatch expensive work off the playback actor.
    public init(minimumLevel: PlaybackLogLevel = .info, includesItemIdentifiers: Bool = false,
                sink: @escaping @Sendable (PlaybackLogEntry) -> Void) {
        self.minimumLevel = minimumLevel
        self.includesItemIdentifiers = includesItemIdentifiers
        self.sink = sink
    }

    public static func system(subsystem: String = "DramaPlayer", minimumLevel: PlaybackLogLevel = .info,
                              includesItemIdentifiers: Bool = false) -> Self {
        let logger = Logger(subsystem: subsystem, category: "Playback")
        return Self(minimumLevel: minimumLevel, includesItemIdentifiers: includesItemIdentifiers) { entry in
            let fields = entry.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            let message = "\(entry.event.rawValue) session=\(entry.sessionID.uuidString) \(fields)"
            let item = entry.itemID ?? ""
            switch entry.level {
            case .debug: logger.debug("\(message, privacy: .public) item=\(item, privacy: .private)")
            case .info: logger.info("\(message, privacy: .public) item=\(item, privacy: .private)")
            case .warning: logger.warning("\(message, privacy: .public) item=\(item, privacy: .private)")
            case .error: logger.error("\(message, privacy: .public) item=\(item, privacy: .private)")
            }
        }
    }

    func write(_ level: PlaybackLogLevel, _ event: PlaybackLogEntry.Event, sessionID: UUID,
               itemID: String?, fields: () -> [String: String]) {
        guard level >= minimumLevel else { return }
        sink(PlaybackLogEntry(timestamp: .now, sessionID: sessionID, level: level, event: event,
                              itemID: includesItemIdentifiers ? itemID : nil, fields: fields()))
    }
}
