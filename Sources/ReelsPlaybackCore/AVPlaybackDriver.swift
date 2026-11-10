import AVFoundation
import Foundation

enum DriverStatus: Equatable { case empty, loading, ready, failed }

@MainActor
protocol PlaybackDriver: AnyObject {
    var layer: AVPlayerLayer { get }
    var onChange: (() -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    var status: DriverStatus { get }
    var position: TimeInterval { get }
    var duration: TimeInterval? { get }
    var bufferedUntil: TimeInterval { get }
    var isPlaying: Bool { get }
    var isWaiting: Bool { get }
    var isFrameReady: Bool { get }
    func load(_ url: URL)
    func play(rate: Float)
    func pause()
    func warm()
    func seek(to position: TimeInterval) async -> Bool
    func clear()
}

@MainActor
final class AVPlaybackDriver: PlaybackDriver {
    private(set) var layer: AVPlayerLayer
    var onChange: (() -> Void)?
    var onEnd: (() -> Void)?
    private let player: AVPlayer
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []
    private var layerObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        player = AVPlayer()
        layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        playerObservations = [player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }]
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
    }

    var status: DriverStatus {
        guard let item = player.currentItem else { return .empty }
        switch item.status {
        case .readyToPlay: return .ready
        case .failed: return .failed
        default: return .loading
        }
    }

    var position: TimeInterval {
        let value = player.currentTime().seconds
        return value.isFinite ? max(0, value) : 0
    }

    var duration: TimeInterval? {
        guard let value = player.currentItem?.duration.seconds, value.isFinite, value > 0 else { return nil }
        return value
    }

    var bufferedUntil: TimeInterval {
        player.currentItem?.loadedTimeRanges.map(\.timeRangeValue).first {
            let time = player.currentTime()
            return $0.containsTime(time) || CMTimeCompare($0.start, time) == 0
        }?.end.seconds ?? position
    }

    var isPlaying: Bool { player.timeControlStatus == .playing }
    var isWaiting: Bool { player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
    var isFrameReady: Bool { layer.isReadyForDisplay }

    func load(_ url: URL) {
        clear()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let display = AVPlayerLayer(player: player)
        display.videoGravity = .resizeAspectFill
        layer = display
        layerObservation = display.observe(\.isReadyForDisplay) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.layer === observed else { return }
                self.onChange?()
            }
        }
        itemObservations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player.currentItem === observed else { return }
                    self.onChange?()
                }
            },
            item.observe(\.loadedTimeRanges) { [weak self] observed, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.player.currentItem === observed else { return }
                    self.onChange?()
                }
            }
        ]
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                self.onEnd?()
            }
        }
    }

    func play(rate: Float) {
        player.cancelPendingPrerolls()
        player.playImmediately(atRate: rate)
    }

    func pause() {
        player.cancelPendingPrerolls()
        player.pause()
    }

    func warm() {
        guard player.status == .readyToPlay, player.rate == 0 else { return }
        player.preroll(atRate: 1)
    }

    func seek(to position: TimeInterval) async -> Bool {
        player.currentItem?.cancelPendingSeeks()
        let time = CMTime(seconds: position, preferredTimescale: 600)
        return await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func clear() {
        pause()
        layerObservation = nil
        layer.player = nil
        itemObservations.removeAll()
        player.currentItem?.cancelPendingSeeks()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
