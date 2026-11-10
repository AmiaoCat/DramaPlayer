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
    private func makeSession(mode: PlaybackConfiguration.Mode = .single, focus: PlaybackFocus? = nil,
                             provider: (any PlaybackSourceProvider)? = nil,
                             cache: any PlaybackMediaCache = DirectPlaybackMediaCache(),
                             endBehavior: PlaybackConfiguration.EndBehavior = .stop) -> (PlaybackSession, Drivers) {
        let drivers = Drivers()
        let session = PlaybackSession(
            configuration: .init(mode: mode, endBehavior: endBehavior), sourceProvider: provider ?? PlaybackSourceResolver { item, _ in
                .allowed(.init(url: URL(fileURLWithPath: "/\(item.id).mp4"), cacheKey: item.id))
            }, cache: cache, focus: focus ?? PlaybackFocus()
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

@MainActor
private final class Drivers {
    var values: [FakeDriver] = []
}

@MainActor
private final class FakeDriver: PlaybackDriver {
    let layer = AVPlayerLayer()
    var onChange: (() -> Void)?
    var onEnd: (() -> Void)?
    var status: DriverStatus = .empty
    var position: TimeInterval = 0
    var duration: TimeInterval? = 60
    var bufferedUntil: TimeInterval = 60
    var isPlaying = false
    var isWaiting = false
    var isFrameReady: Bool { status == .ready }
    var lastRate: Float = 1
    var loadedURLs: [URL] = []

    func load(_ url: URL) {
        loadedURLs.append(url)
        status = .ready
    }

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
