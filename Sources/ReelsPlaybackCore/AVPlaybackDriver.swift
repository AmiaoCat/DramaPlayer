import AVFoundation
import Foundation

enum DriverStatus: Equatable { case empty, loading, ready, failed }

@MainActor
protocol PlaybackDriver: AnyObject {
    var layer: AVPlayerLayer { get }
    var onChange: (() -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    var status: DriverStatus { get }
    var position: TimeInterval { get }
    var duration: TimeInterval? { get }
    var bufferedUntil: TimeInterval { get }
    var isPlaying: Bool { get }
    var isWaiting: Bool { get }
    var isFrameReady: Bool { get }
    var volume: Float { get set }
    func load(_ url: URL, preferences: PlaybackStreamPreferences)
    func setStreamPreferences(_ preferences: PlaybackStreamPreferences)
    func mediaTrackGroup(for kind: PlaybackMediaTrackKind) async -> PlaybackMediaTrackGroup?
    func selectMediaTrack(_ selection: PlaybackMediaTrackSelection, in group: PlaybackMediaTrackGroup) -> Bool
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
    var onFailure: (() -> Void)?
    private let player: AVPlayer
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []
    private var layerObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var itemNotifications: [NSObjectProtocol] = []
    private var itemGeneration = UUID()
    private var mediaGroups: [PlaybackMediaTrackKind: AVMediaSelectionGroup] = [:]

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

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func load(_ url: URL, preferences: PlaybackStreamPreferences) {
        clear()
        let item = AVPlayerItem(url: url)
        apply(preferences, to: item)
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
        itemNotifications = [
            observe(.AVPlayerItemDidPlayToEndTime, item: item) { $0.onEnd?() },
            observe(.AVPlayerItemFailedToPlayToEndTime, item: item) { $0.onFailure?() }
        ]
    }

    func setStreamPreferences(_ preferences: PlaybackStreamPreferences) {
        if let item = player.currentItem { apply(preferences, to: item) }
    }

    func mediaTrackGroup(for kind: PlaybackMediaTrackKind) async -> PlaybackMediaTrackGroup? {
        guard let item = player.currentItem else { return nil }
        let group: AVMediaSelectionGroup
        if let existing = mediaGroups[kind] {
            group = existing
        } else {
            let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
            guard let loaded = try? await item.asset.loadMediaSelectionGroup(for: characteristic),
                  player.currentItem === item, !Task.isCancelled else { return nil }
            // A concurrent request may already have installed a group and handed its IDs to the host.
            group = mediaGroups[kind] ?? loaded
            mediaGroups[kind] = group
        }
        let options = group.options
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        return PlaybackMediaTrackGroup(
            kind: kind,
            tracks: options.enumerated().map { index, option in
                PlaybackMediaTrack(id: index, displayName: option.displayName, languageTag: option.extendedLanguageTag)
            },
            selectedTrackID: selected.flatMap { options.firstIndex(of: $0) },
            allowsDisabling: group.allowsEmptySelection,
            generation: itemGeneration
        )
    }

    func selectMediaTrack(_ selection: PlaybackMediaTrackSelection, in group: PlaybackMediaTrackGroup) -> Bool {
        guard group.generation == itemGeneration, let item = player.currentItem,
              let currentGroup = mediaGroups[group.kind] else { return false }
        switch selection {
        case .automatic:
            item.selectMediaOptionAutomatically(in: currentGroup)
        case .off:
            guard currentGroup.allowsEmptySelection else { return false }
            item.select(nil, in: currentGroup)
        case .track(let index):
            let options = currentGroup.options
            guard options.indices.contains(index) else { return false }
            item.select(options[index], in: currentGroup)
        }
        return true
    }

    private func apply(_ preferences: PlaybackStreamPreferences, to item: AVPlayerItem) {
        item.preferredPeakBitRate = preferences.preferredPeakBitRate
        item.preferredPeakBitRateForExpensiveNetworks = preferences.preferredPeakBitRateForExpensiveNetworks
        item.preferredForwardBufferDuration = preferences.preferredForwardBufferDuration
    }

    private func observe(_ name: Notification.Name, item: AVPlayerItem,
                         action: @escaping @MainActor (AVPlaybackDriver) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                action(self)
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
        itemGeneration = UUID()
        mediaGroups.removeAll()
        layerObservation = nil
        layer.player = nil
        itemObservations.removeAll()
        player.currentItem?.cancelPendingSeeks()
        itemNotifications.forEach(NotificationCenter.default.removeObserver)
        itemNotifications.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        itemNotifications.forEach(NotificationCenter.default.removeObserver)
    }
}
