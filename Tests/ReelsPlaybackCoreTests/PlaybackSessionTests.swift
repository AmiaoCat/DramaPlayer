import AVFoundation
import XCTest
@testable import ReelsPlaybackCore

final class PlaybackSessionTests: XCTestCase {
    @MainActor
    func testReadyNeighborReusesLayerAndPosition() async throws {
        let (session, drivers) = makeSession(mode: .vertical)
        session.setItems([.init(id: "a"), .init(id: "b")])
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        let first = drivers.values[0]
        first.position = 11
        session.select("b")
        XCTAssertFalse(first.isPlaying)
        XCTAssertTrue(drivers.values[1].isPlaying)
        session.select("a")
        XCTAssertEqual(drivers.values.count, 2)
        XCTAssertTrue(session.presentation(for: "a")?.layer === first.layer)
        XCTAssertTrue(session.snapshot.firstFrameReady)
        XCTAssertEqual(session.snapshot.position, 11)
        XCTAssertTrue(first.isPlaying)
    }

    @MainActor
    func testManualPauseSurvivesFocusAndSuspension() async throws {
        let focus = PlaybackFocus()
        let (first, firstDrivers) = makeSession(focus: focus)
        let (second, secondDrivers) = makeSession(focus: focus)
        first.setItems([.init(id: "a")])
        second.setItems([.init(id: "b")])
        first.activate()
        try await wait { firstDrivers.values.first?.isPlaying == true }
        second.activate()
        XCTAssertFalse(firstDrivers.values[0].isPlaying)
        try await wait { secondDrivers.values.first?.isPlaying == true }
        second.pause()
        second.setSuspended(true, reason: .background)
        second.setSuspended(false, reason: .background)
        XCTAssertFalse(secondDrivers.values[0].isPlaying)
        XCTAssertFalse(second.snapshot.wantsPlayback)
    }

    @MainActor
    func testScrubCommitsPositionAndResumesAtSelectedRate() async throws {
        let (session, drivers) = makeSession()
        session.setItems([.init(id: "a")])
        session.activate()
        try await wait { drivers.values.first?.isPlaying == true }
        session.setRate(1.5)
        session.beginScrubbing()
        session.previewScrub(to: 32)
        XCTAssertEqual(session.snapshot.position, 32)
        XCTAssertFalse(drivers.values[0].isPlaying)
        session.endScrubbing()
        try await wait { drivers.values[0].position == 32 && drivers.values[0].isPlaying }
        XCTAssertEqual(drivers.values[0].lastRate, 1.5)
    }

    @MainActor
    func testRapidSelectionCannotPlayLateResult() async throws {
        let provider = PlaybackSourceResolver { item, _ in
            if item.id == "a" { try? await Task.sleep(for: .milliseconds(80)) }
            return .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
        }
        let (session, drivers) = makeSession(provider: provider)
        session.setItems([.init(id: "a"), .init(id: "b")])
        session.activate()
        await Task.yield()
        session.select("b")
        try await wait { drivers.values.count == 2 && drivers.values[1].isPlaying }
        try await Task.sleep(for: .milliseconds(110))
        XCTAssertEqual(session.snapshot.itemID, "b")
        XCTAssertFalse(drivers.values[0].isPlaying)
        XCTAssertNil(session.presentation(for: "a"))
    }

    @MainActor
    func testAccessDeniedDuringPreloadIsResolvedOnSelection() async throws {
        let provider = PlaybackSourceResolver { item, purpose in
            if item.id == "b", purpose == .preload { return .requiresUserAction }
            return .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
        }
        let (session, drivers) = makeSession(mode: .vertical, provider: provider)
        session.setItems([.init(id: "a"), .init(id: "b")])
        session.activate()
        try await wait { drivers.values.count == 2 }
        session.select("b")
        try await wait { session.snapshot.itemID == "b" && session.snapshot.state == .playing }
        XCTAssertEqual(drivers.values.count, 3)
    }

    @MainActor
    func testMemoryPressureDropsWarmItemsWithoutRecreatingThemOnTick() async throws {
        let (session, drivers) = makeSession(mode: .vertical)
        session.setItems([.init(id: "a"), .init(id: "b"), .init(id: "c")])
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        session.discardInactiveItems()
        drivers.values[0].onChange?()
        XCTAssertEqual(drivers.values.count, 2)
        XCTAssertNil(session.presentation(for: "b"))
        XCTAssertTrue(drivers.values[0].isPlaying)
    }

    @MainActor
    func testConfirmedCacheFailureFallsBackToOriginOnce() async throws {
        let cache = CacheStub()
        let (session, drivers) = makeSession(cache: cache)
        session.setItems([.init(id: "a")])
        session.activate()
        try await wait { drivers.values.first?.isPlaying == true }
        let driver = drivers.values[0]
        driver.position = 14
        driver.status = .failed
        driver.onChange?()
        try await wait { driver.loadedURLs.count == 2 && driver.isPlaying }
        XCTAssertEqual(driver.loadedURLs.map(\.lastPathComponent), ["cached.mp4", "a.mp4"])
        XCTAssertEqual(driver.position, 14)
        let invalidations = await cache.invalidations
        XCTAssertEqual(invalidations, 1)

        driver.status = .failed
        driver.onChange?()
        XCTAssertEqual(session.snapshot.state, .failed(.playbackFailed))
        XCTAssertEqual(driver.loadedURLs.count, 2)
    }

    @MainActor
    func testEndAdvancesToPreparedItemAndKeepsOnlyOnePlaying() async throws {
        let (session, drivers) = makeSession(mode: .vertical, endBehavior: .advance)
        session.setItems([.init(id: "a"), .init(id: "b")])
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        drivers.values[0].onEnd?()
        XCTAssertEqual(session.selectedID, "b")
        XCTAssertFalse(drivers.values[0].isPlaying)
        XCTAssertTrue(drivers.values[1].isPlaying)
        XCTAssertEqual(drivers.values.count, 2)
    }

    @MainActor
    func testDiagnosticsCorrelatesStartFallbackAndTerminalFailure() async throws {
        let (session, drivers) = makeSession(cache: CacheStub())
        var events: [PlaybackDiagnosticEvent] = []
        let stream = session.diagnostics()
        let observer = Task { @MainActor in
            for await event in stream { events.append(event) }
        }
        defer { observer.cancel() }

        session.setItems([.init(id: "a")])
        session.activate()
        try await wait { drivers.values.first?.isPlaying == true }
        let driver = drivers.values[0]
        driver.onFailure?()
        driver.onFailure?() // Duplicate terminal notification during cache invalidation.
        try await wait { driver.loadedURLs.count == 2 && driver.isPlaying }
        driver.onFailure?()
        try await wait { events.count >= 4 }

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(Set(events.map(\.attemptID)).count, 1)
        XCTAssertEqual(Set(events.map(\.itemID)), ["a"])
        XCTAssertEqual(events[0].kind, .started)
        if case .firstFrame(let seconds) = events[1].kind {
            XCTAssertGreaterThanOrEqual(seconds, 0)
        } else {
            XCTFail("Expected exactly one startup frame")
        }
        XCTAssertEqual(events[2].kind, .cachedMediaFallback)
        XCTAssertEqual(events[3].kind, .finished(.failed(.playbackFailed)))
        XCTAssertEqual(session.snapshot.state, .failed(.playbackFailed))
    }

    func testAttemptMeasuresPostStartupBufferingAndInterruptedIntervals() {
        var attempt = PlaybackAttempt(itemID: "a", start: 100)
        var events: [PlaybackDiagnosticEvent.Kind] = []
        let record: (PlaybackDiagnosticEvent) -> Void = { events.append($0.kind) }
        attempt.update(state: .buffering, firstFrameReady: false, seeking: false, now: 101, emit: record)
        attempt.update(state: .playing, firstFrameReady: true, seeking: false, now: 102, emit: record)
        attempt.update(state: .buffering, firstFrameReady: true, seeking: true, now: 103, emit: record)
        attempt.update(state: .buffering, firstFrameReady: true, seeking: false, now: 104, emit: record)
        attempt.update(state: .playing, firstFrameReady: true, seeking: false, now: 107, emit: record)
        attempt.update(state: .buffering, firstFrameReady: true, seeking: false, now: 110, emit: record)
        attempt.finish(.interrupted, now: 112, emit: record)
        XCTAssertEqual(events, [
            .firstFrame(seconds: 2),
            .rebufferingEnded(seconds: 3, recovered: true),
            .rebufferingEnded(seconds: 2, recovered: false),
            .finished(.interrupted)
        ])
    }

    @MainActor
    func testStreamPreferencesUpdateRetainedPlayersAndApplyToNewLoads() async throws {
        let (session, drivers) = makeSession(mode: .vertical)
        session.setItems(["a", "b", "c"].map { PlaybackItem(id: $0) })
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        let preferences = PlaybackStreamPreferences(preferredPeakBitRate: 1_000_000,
                                                    preferredPeakBitRateForExpensiveNetworks: -.infinity,
                                                    preferredForwardBufferDuration: 4)
        session.setStreamPreferences(preferences)
        XCTAssertEqual(preferences.preferredPeakBitRateForExpensiveNetworks, 0)
        XCTAssertEqual(drivers.values.map(\.preferences), [preferences, preferences])
        session.select("b")
        try await wait { drivers.values.count == 3 && drivers.values[2].status == .ready }
        XCTAssertEqual(drivers.values[2].preferences, preferences)
    }

    @MainActor
    func testChangingPreloadPolicyPreservesSelectedPlayer() async throws {
        let (session, drivers) = makeSession(mode: .vertical)
        session.setItems([.init(id: "a"), .init(id: "b")])
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        let selected = drivers.values[0]
        selected.position = 7

        session.setPreloadPolicy(.disabled)
        XCTAssertNil(session.presentation(for: "b"))
        XCTAssertTrue(session.presentation(for: "a")?.layer === selected.layer)
        XCTAssertEqual(session.snapshot.position, 7)
        selected.onChange?()
        XCTAssertEqual(drivers.values.count, 2)

        session.setPreloadPolicy(.preparedPlayer)
        try await wait { drivers.values.count == 3 && drivers.values[2].status == .ready }
        XCTAssertTrue(selected.isPlaying)
        XCTAssertTrue(session.presentation(for: "a")?.layer === selected.layer)
    }

    @MainActor
    func testLoadDeadlineRejectsLateResolverResultAndAllowsRetry() async throws {
        let resolver = DelayedFirstResolver()
        let (session, drivers) = makeSession(provider: resolver, loadTimeout: 0.1)
        session.setItems([.init(id: "a")])
        session.activate()
        try await wait { session.snapshot.state == .failed(.sourceUnavailable) }
        XCTAssertTrue(drivers.values.first?.loadedURLs.isEmpty == true)

        session.retry()
        try await wait { session.snapshot.state == .playing }
        await resolver.completeFirstRequest()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(drivers.values.first?.loadedURLs.isEmpty == true)
        XCTAssertEqual(drivers.values.last?.loadedURLs.count, 1)
    }

    @MainActor
    func testLogsFilterLevelsAndOmitSensitiveInputsByDefault() async throws {
        let recorder = LogRecorder()
        let logger = PlaybackLogger(minimumLevel: .info) { recorder.append($0) }
        let provider = PlaybackSourceResolver { _, _ in
            return .allowed(.init(url: URL(string: "https://example.invalid/video?token=secret")!,
                                  cacheKey: "private-cache-key"))
        }
        let (session, drivers) = makeSession(provider: provider, logger: logger)
        session.setItems([.init(id: "account-private-episode")])
        session.activate()
        try await wait { drivers.values.first?.isPlaying == true }
        drivers.values[0].onFailure?()

        let entries = recorder.entries
        XCTAssertEqual(entries.map(\.event), [.attemptStarted, .firstFrame, .playbackFailed, .attemptFinished])
        XCTAssertTrue(entries.allSatisfy { $0.itemID == nil && $0.level >= .info })
        XCTAssertEqual(Set(entries.map(\.sessionID)).count, 1)
        for entry in entries {
            let fields = entry.fields.values.joined()
            XCTAssertFalse(fields.contains("secret"))
            XCTAssertFalse(fields.contains("private"))
            XCTAssertFalse(fields.contains("example.invalid"))
        }
    }

    @MainActor
    func testSlowCachedPlayerTimesOutAndFallsBackToOrigin() async throws {
        let cache = CacheStub()
        let driver = FakeDriver { $0.lastPathComponent == "cached.mp4" ? .loading : .ready }
        let session = PlaybackSession(
            configuration: .init(loadTimeout: 0.1),
            sourceProvider: PlaybackSourceResolver { item, _ in
                .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
            },
            cache: cache, focus: PlaybackFocus(), makeDriver: { driver }
        )
        session.setItems([.init(id: "a", resumePosition: 12)])
        session.activate()
        try await wait { driver.loadedURLs.count == 2 && session.snapshot.state == .playing }
        XCTAssertEqual(driver.loadedURLs.map(\.lastPathComponent), ["cached.mp4", "a.mp4"])
        XCTAssertEqual(session.snapshot.position, 12)
        let invalidations = await cache.invalidations
        XCTAssertEqual(invalidations, 1)
    }

    @MainActor
    func testCustomPrefetchFiltersCandidatesChecksAuthorizationAndKeepsPlayback() async throws {
        let cache = PrefetchRecorder()
        let logs = LogRecorder()
        let provider = PlaybackSourceResolver { item, purpose in
            if purpose == .preload, item.id == "locked" { return .requiresUserAction }
            return .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
        }
        let (session, drivers) = makeSession(mode: .vertical, provider: provider, cache: cache,
                                             logger: .init(minimumLevel: .debug) { logs.append($0) })
        session.setItems(["a", "b", "c", "locked", "d", "e"].map { PlaybackItem(id: $0) }, selectedID: "b")
        session.activate()
        try await wait { session.snapshot.state == .playing }
        let selected = drivers.values[0]
        selected.position = 17

        session.setMediaPrefetchPolicy(.init(maxCandidates: 3) { context in
            ["d", context.selectedItem.id, "d", "missing", "locked", "a", "e"]
        })
        session.setPreloadPolicy(.mediaBytes)
        try await wait { logs.entries.filter { $0.event == .prefetchFinished }.count == 2 }
        let custom = await cache.keys
        XCTAssertEqual(custom, ["d", "a"])
        XCTAssertEqual(session.snapshot.position, 17)
        XCTAssertTrue(session.presentation(for: "b")?.layer === selected.layer)

        session.setMediaPrefetchPolicy(nil)
        try await wait { logs.entries.filter { $0.event == .prefetchFinished }.count == 3 }
        let standard = await cache.keys
        XCTAssertEqual(standard, ["d", "a", "c"])
        XCTAssertTrue(selected.isPlaying)
    }

    func testMediaPrefetchOffsetsIgnoreOverflowAndQueueEdges() {
        let items = ["a", "b", "c"].map { PlaybackItem(id: $0) }
        let policy = PlaybackMediaPrefetchPolicy(offsets: [Int.max, -2, 1, 0, -1, 1])
        XCTAssertEqual(policy.candidates(in: items, selectedIndex: 1).map(\.id), ["c", "a"])
        XCTAssertTrue(PlaybackMediaPrefetchPolicy(offsets: [1], maxCandidates: 0)
            .candidates(in: items, selectedIndex: 1).isEmpty)
    }

    @MainActor
    func testVolumeAppliesToPreparedAndFuturePlayers() async throws {
        let (session, drivers) = makeSession(mode: .vertical)
        session.setVolume(0.4)
        session.setItems(["a", "b", "c"].map { PlaybackItem(id: $0) })
        session.activate()
        try await wait { drivers.values.count == 2 && drivers.values[1].status == .ready }
        XCTAssertEqual(drivers.values.map(\.volume), [0.4, 0.4])

        session.setVolume(-1)
        session.setVolume(.nan)
        XCTAssertEqual(session.volume, 0)
        XCTAssertEqual(drivers.values.map(\.volume), [0, 0])
        session.select("b")
        try await wait { drivers.values.count == 3 && drivers.values[2].status == .ready }
        XCTAssertEqual(drivers.values[2].volume, 0)

        session.setVolume(2)
        XCTAssertEqual(session.volume, 1)
        XCTAssertEqual(drivers.values.map(\.volume), [1, 1, 1])
    }

    @MainActor
    private func makeSession(mode: PlaybackConfiguration.Mode = .single, focus: PlaybackFocus? = nil,
                             provider: (any PlaybackSourceProvider)? = nil,
                             cache: any PlaybackMediaCache = DirectPlaybackMediaCache(),
                             endBehavior: PlaybackConfiguration.EndBehavior = .stop,
                             loadTimeout: TimeInterval? = 30,
                             logger: PlaybackLogger? = nil) -> (PlaybackSession, Drivers) {
        let drivers = Drivers()
        let session = PlaybackSession(
            configuration: .init(mode: mode, endBehavior: endBehavior, loadTimeout: loadTimeout),
            sourceProvider: provider ?? PlaybackSourceResolver { item, _ in
                .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
            }, cache: cache, focus: focus ?? PlaybackFocus(), logger: logger
        ) {
            let driver = FakeDriver()
            drivers.values.append(driver)
            return driver
        }
        return (session, drivers)
    }

    @MainActor
    private func wait(until predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Playback condition did not become true")
        throw PlaybackFailure.playbackFailed
    }
}

private actor DelayedFirstResolver: PlaybackSourceProvider {
    private var calls = 0
    private var firstRequest: CheckedContinuation<Void, Never>?

    func source(for item: PlaybackItem, purpose: PlaybackPurpose) async throws -> PlaybackAccess {
        calls += 1
        if calls == 1 { await withCheckedContinuation { firstRequest = $0 } }
        return .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
    }

    func completeFirstRequest() {
        firstRequest?.resume()
        firstRequest = nil
    }
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PlaybackLogEntry] = []

    var entries: [PlaybackLogEntry] { lock.withLock { storage } }

    func append(_ entry: PlaybackLogEntry) { lock.withLock { storage.append(entry) } }
}

@MainActor
private final class Drivers {
    var values: [FakeDriver] = []
}

@MainActor
private final class FakeDriver: PlaybackDriver {
    let layer = AVPlayerLayer()
    var onChange: (() -> Void)?
    var onEnd: (() -> Void)?
    var onFailure: (() -> Void)?
    var status: DriverStatus = .empty
    var position: TimeInterval = 0
    var duration: TimeInterval? = 60
    var bufferedUntil: TimeInterval = 60
    var isPlaying = false
    var isWaiting = false
    var isFrameReady: Bool { status == .ready }
    var lastRate: Float = 1
    var loadedURLs: [URL] = []
    var preferences = PlaybackStreamPreferences()
    var volume: Float = 1
    private let statusAfterLoad: (URL) -> DriverStatus

    init(statusAfterLoad: @escaping (URL) -> DriverStatus = { _ in .ready }) {
        self.statusAfterLoad = statusAfterLoad
    }

    func load(_ url: URL, preferences: PlaybackStreamPreferences) {
        self.preferences = preferences
        loadedURLs.append(url)
        status = statusAfterLoad(url)
    }

    func setStreamPreferences(_ preferences: PlaybackStreamPreferences) { self.preferences = preferences }

    func mediaTrackGroup(for kind: PlaybackMediaTrackKind) async -> PlaybackMediaTrackGroup? { nil }

    func selectMediaTrack(_ selection: PlaybackMediaTrackSelection, in group: PlaybackMediaTrackGroup) -> Bool { false }

    func play(rate: Float) {
        lastRate = rate
        isPlaying = true
    }

    func pause() { isPlaying = false }
    func warm() {}

    func seek(to position: TimeInterval) async -> Bool {
        self.position = position
        return true
    }

    func clear() {
        status = .empty
        isPlaying = false
        position = 0
    }
}

private actor CacheStub: PlaybackMediaCache {
    private(set) var invalidations = 0

    func media(for source: PlaybackSource) async throws -> PlaybackMedia {
        PlaybackMedia(url: URL(fileURLWithPath: "/cached.mp4"), isCached: true)
    }

    func invalidate(_ source: PlaybackSource) async { invalidations += 1 }
}

private actor PrefetchRecorder: PlaybackMediaCache {
    private(set) var keys: [String] = []

    func media(for source: PlaybackSource) async throws -> PlaybackMedia { .init(url: source.url) }

    func prefetch(_ source: PlaybackSource) async throws { keys.append(source.cacheKey) }
}
