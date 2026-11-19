#if canImport(UIKit)
import AVFoundation
@testable import ReelsPlaybackCore
import ReelsPlaybackUIKit
import UIKit
import XCTest

final class PlaybackVideoViewTests: XCTestCase {
    @MainActor
    func testImmersiveControlsOnlyShowThePlaybackProgress() throws {
        let session = PlaybackSession(sourceProvider: PlaybackSourceResolver { _, _ in .unavailable })
        let players: [UIView] = [SinglePlaybackView(session: session), VerticalPlaybackView(session: session)]
        for player in players {
            let controls = try XCTUnwrap(player.subviews.compactMap { $0 as? PlaybackControlsView }.first)
            let standard = try XCTUnwrap(controls.subviews.compactMap { $0 as? UIStackView }.first)
            let progress = try XCTUnwrap(controls.subviews.compactMap { $0 as? UIProgressView }.first)
            XCTAssertFalse(standard.isHidden)
            XCTAssertTrue(progress.isHidden)

            (player as? SinglePlaybackView)?.showsProgressOnly = true
            (player as? VerticalPlaybackView)?.showsProgressOnly = true
            XCTAssertTrue(standard.isHidden)
            XCTAssertFalse(progress.isHidden)
            XCTAssertEqual(controls.backgroundColor, .clear)

            controls.showsProgressOnly = false
            XCTAssertFalse(standard.isHidden)
            XCTAssertTrue(progress.isHidden)
        }
    }

    @MainActor
    func testCoverFailureDoesNotPollOrBlockVideoAndCanRetryIndependently() async throws {
        let loader = CoverLoaderStub()
        let view = PlaybackVideoView(coverLoader: loader)
        let item = PlaybackItem(id: "episode", coverURL: URL(fileURLWithPath: "/poster.jpg"))
        let spinner = try XCTUnwrap(view.subviews.compactMap { $0 as? UIActivityIndicatorView }.first)
        let preparing = snapshot(for: item, state: .preparing)

        view.display(item, presentation: nil, snapshot: preparing)
        XCTAssertEqual(view.coverState, .loading)
        XCTAssertEqual(spinner.accessibilityLabel, "Loading video")
        try await wait { loader.requests.count == 1 }
        loader.complete(0, image: nil)
        try await wait { view.coverState == .failed }
        XCTAssertTrue(spinner.isAnimating)

        view.display(item, presentation: nil, snapshot: snapshot(for: item, state: .failed(.playbackFailed)))
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertFalse(spinner.isAnimating)

        view.retryCoverLoading()
        XCTAssertEqual(spinner.accessibilityLabel, "Loading cover")
        try await wait { loader.requests.count == 2 }
        loader.complete(1, image: UIImage(systemName: "film"))
        try await wait { view.coverState == .loaded }
        XCTAssertFalse(spinner.isAnimating)
    }

    @MainActor
    func testFirstFrameCancelsCoverAndLateResultCannotOverwriteReusedView() async throws {
        let loader = CoverLoaderStub()
        let view = PlaybackVideoView(coverLoader: loader)
        let url = URL(fileURLWithPath: "/poster.jpg")
        let first = PlaybackItem(id: "first", coverURL: url)
        let next = PlaybackItem(id: "next", coverURL: url)

        view.display(first, presentation: nil)
        try await wait { loader.requests.count == 1 }
        view.display(first, presentation: PlaybackPresentation(layer: AVPlayerLayer(), firstFrameReady: true))
        XCTAssertEqual(view.coverState, .idle)

        view.display(next, presentation: nil)
        try await wait { loader.requests.count == 2 }
        loader.complete(0, image: UIImage(systemName: "film"))
        await Task.yield()
        XCTAssertEqual(view.coverState, .loading)
        loader.complete(1, image: nil)
        try await wait { view.coverState == .failed }

        view.display(PlaybackItem(id: "no-poster"), presentation: nil)
        XCTAssertEqual(view.coverState, .noCover)
    }

    @MainActor
    func testReadyPresentationSkipsCoverRequestAndLoadsOnlyIfPosterBecomesNeeded() async throws {
        let loader = CoverLoaderStub()
        let view = PlaybackVideoView(coverLoader: loader)
        let item = PlaybackItem(id: "episode", coverURL: URL(fileURLWithPath: "/poster.jpg"))

        view.display(item, presentation: PlaybackPresentation(layer: AVPlayerLayer(), firstFrameReady: true))
        await Task.yield()
        XCTAssertTrue(loader.requests.isEmpty)
        XCTAssertEqual(view.coverState, .idle)

        view.display(item, presentation: nil)
        try await wait { loader.requests.count == 1 }
        loader.complete(0, image: UIImage(systemName: "film"))
        try await wait { view.coverState == .loaded }
    }

    private func snapshot(for item: PlaybackItem, state: PlaybackState) -> PlaybackSnapshot {
        .init(itemID: item.id, state: state, position: 0, duration: nil, bufferedUntil: 0, rate: 1,
              wantsPlayback: true, firstFrameReady: false, isScrubbing: false)
    }

    @MainActor
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the cover request to finish")
        throw CocoaError(.fileReadUnknown)
    }
}

@MainActor
private final class CoverLoaderStub: PlaybackCoverLoader {
    private(set) var requests: [CheckedContinuation<UIImage?, Never>?] = []

    func image(for url: URL) async -> UIImage? {
        await withCheckedContinuation { requests.append($0) }
    }

    func complete(_ index: Int, image: UIImage?) {
        let request = requests[index]
        requests[index] = nil
        request?.resume(returning: image)
    }
}
#endif
