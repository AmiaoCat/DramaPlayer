import UIKit

#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
import ReelsPlaybackUIKit
#endif

@MainActor
final class DemoPlayerViewController: UIViewController {
    enum Mode: Equatable {
        case single, landscape, feed, custom, cover, access, remote(URL)

        var title: String {
            switch self {
            case .single: "Single video"
            case .landscape: "Landscape video"
            case .feed: "Vertical feed"
            case .custom: "Custom controls"
            case .cover: "Cover loading"
            case .access: "Episode access"
            case .remote: "Remote playback"
            }
        }

        var help: String {
            switch self {
            case .single: "Tap the video to play or pause. The clip loops."
            case .landscape: "Rotate the phone to see the same video in a wider layout."
            case .feed: "Swipe or use Episodes to jump to another clip."
            case .custom: "Press Play to start from the saved position."
            case .cover: "Use Cases to compare slow, failed, missing, and first-frame-first covers."
            case .access: "Episode 2 starts locked. Unlock it to continue."
            case .remote: "Use Retry if loading fails. Go back to try a different URL."
            }
        }

        var isVertical: Bool { self == .feed || self == .access }

        var configuration: PlaybackConfiguration {
            switch self {
            case .single, .landscape, .cover: .init(mode: .single, endBehavior: .loop, loadTimeout: 30)
            case .feed, .access: .init(mode: .vertical, preload: .preparedPlayer, endBehavior: .advance, loadTimeout: 30)
            case .custom: .init(autoplay: false, loadTimeout: 30)
            case .remote: .init(loadTimeout: 30)
            }
        }
    }

    private let mode: Mode
    private let session: PlaybackSession
    private let lifecycle: PlaybackLifecycle
    private static let downloads = PlaybackDownloadStore(directory: URL.applicationSupportDirectory
        .appendingPathComponent("DramaPlayerDownloads", isDirectory: true))
    private let downloadSource: PlaybackSource?
    private let downloadButton = UIButton(type: .system)
    private let downloadStatus = DemoStyle.label(style: .caption1, color: DemoStyle.secondary)
    private var downloadTask: Task<Void, Never>?
    private var hasDownload = false
    private let access: DemoEpisodeAccess
    private let status = UILabel()
    private let playbackDetail = DemoStyle.label(style: .caption1, color: DemoStyle.secondary)
    private let coverStatus = UILabel()
    private lazy var customVideo = PlaybackVideoView()
    private let progress = UILabel()
    private let completion = UILabel()
    private let playPause = UIButton(type: .system)
    private let skip = UIButton(type: .system)
    private let recovery = UIButton(type: .system)
    private var observations: Task<Void, Never>?
    private var diagnosticObservations: Task<Void, Never>?
    private weak var feedView: VerticalPlaybackView?
    private var customLandscapeGestures: PlaybackLandscapeGestures?
    private let help = UILabel()
    private let workspace = UIStackView()
    private var fullscreenLayout: DemoFullscreenLayout?
    private lazy var immersiveTap = UITapGestureRecognizer(target: self, action: #selector(exitImmersivePlayback))

    override var prefersStatusBarHidden: Bool { fullscreenLayout?.isFullscreen ?? false }

    init?(mode: Mode) {
        self.mode = mode

        let items: [PlaybackItem]
        let urls: [String: URL]
        let downloadable: PlaybackSource?
        if case .remote(let url) = mode {
            items = [PlaybackItem(id: "remote")]
            urls = ["remote": url]
            downloadable = PlaybackDownloadStore.supports(url) ? .init(url: url, cacheKey: url.absoluteString) : nil
        } else if mode == .cover {
            downloadable = nil
            guard let video = DemoSeries.asset("coffee-01", "mp4"),
                  let fastVideo = DemoSeries.asset("coffee-03", "mp4") else { return nil }
            items = [
                .init(id: "slow", coverURL: DemoSeries.asset("coffee-01", "jpg")),
                .init(id: "failed", coverURL: video.deletingLastPathComponent().appendingPathComponent("unavailable.jpg")),
                .init(id: "no-cover"),
                .init(id: "frame-first", coverURL: DemoSeries.asset("coffee-03", "jpg"))
            ]
            urls = ["slow": video, "failed": video, "no-cover": video, "frame-first": fastVideo]
        } else {
            downloadable = nil
            let ids = mode.isVertical ? DemoSeries.labEpisodeIDs : [mode == .landscape ? DemoSeries.landscapeID : "coffee-02"]
            let movies = ids.compactMap { id in
                DemoSeries.asset(id, "mp4").map { (id, $0) }
            }
            guard movies.count == ids.count else { return nil }
            urls = Dictionary(uniqueKeysWithValues: movies)
            items = ids.map { id in
                PlaybackItem(id: id, coverURL: DemoSeries.asset(id, "jpg"),
                             resumePosition: mode == .custom ? 2 : 0)
            }
        }

        let lockedID = mode == .access ? items.dropFirst().first?.id : nil
        let access = DemoEpisodeAccess(lockedID: lockedID)
        self.access = access
        let isCoverDemo = mode == .cover
        let resolver = PlaybackSourceResolver { item, _ in
            guard let url = urls[item.id] else { return .unavailable }
            // Playback and preload both check the same entitlement. The UI owns the unlock flow.
            guard await access.canPlay(item.id) else { return .requiresUserAction }
            if isCoverDemo, item.id != "frame-first" {
                try await Task.sleep(for: .seconds(4))
            }
            return .allowed(downloadable ?? .init(url: url, cacheKey: "demo/\(item.id)"))
        }
        downloadSource = downloadable
        let cache: any PlaybackMediaCache = downloadable == nil ? DirectPlaybackMediaCache() : Self.downloads
        session = PlaybackSession(configuration: mode.configuration, sourceProvider: resolver, cache: cache,
                                  logger: DemoLogging.logger)
        lifecycle = PlaybackLifecycle(session: session)
        super.init(nibName: nil, bundle: nil)
        session.setItems(items, selectedID: lockedID)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = DemoStyle.canvas

        let player: UIView
        if mode.isVertical {
            let feed = VerticalPlaybackView(session: session)
            feed.isLandscapeAdjustmentEnabled = true
            feedView = feed
            player = feed
            let menu = UIMenu(children: session.items.enumerated().map { index, item in
                UIAction(title: "Episode \(index + 1)") { [weak session] _ in session?.select(item.id) }
            })
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Episodes", menu: menu)
        } else if mode == .custom {
            player = customVideo
            customLandscapeGestures = PlaybackLandscapeGestures(session: session, surface: customVideo)
        } else {
            let loader: any PlaybackCoverLoader = mode == .cover ? DemoCoverLoader() : URLPlaybackCoverLoader()
            let single = SinglePlaybackView(session: session, coverLoader: loader, scaling: .fit)
            single.isLandscapeAdjustmentEnabled = true
            if mode == .cover { installCoverDemo(on: single) }
            player = single
        }

        configureLabel(help, color: .secondaryLabel)
        help.text = mode.help
        status.font = .preferredFont(forTextStyle: .headline)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.accessibilityIdentifier = "playback-status"

        DemoStyle.styleButton(recovery, filled: true)
        recovery.addAction(UIAction { [weak self] _ in self?.recoverPlayback() }, for: .touchUpInside)
        recovery.isHidden = true
        var arrangedViews: [UIView] = [status, playbackDetail, help, recovery]
        if mode == .custom { arrangedViews.append(makeCustomControls()) }
        if mode == .cover { arrangedViews.insert(coverStatus, at: 2) }
        if case .remote = mode {
            let diagnostics = UILabel()
            configureLabel(diagnostics, color: .secondaryLabel)
            diagnostics.text = "Waiting for playback diagnostics"
            diagnostics.accessibilityIdentifier = "playback-diagnostics"
            arrangedViews.insert(diagnostics, at: 2)
            observeDiagnostics(in: diagnostics)
            installStreamingMenu()
            if let source = downloadSource {
                DemoStyle.styleButton(downloadButton)
                downloadButton.accessibilityIdentifier = "download-action"
                downloadStatus.accessibilityIdentifier = "download-status"
                downloadButton.addAction(UIAction { [weak self] _ in self?.manageDownload(source) }, for: .touchUpInside)
                arrangedViews.append(contentsOf: [downloadStatus, downloadButton])
                refreshDownload(source)
            }
        }

        let inspector = DemoStyle.panel(arrangedViews, spacing: 5, inset: 12)
        let stage = UIView()
        DemoStyle.styleSurface(stage, radius: 20, color: .black)
        player.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(player)
        NSLayoutConstraint.activate([
            player.topAnchor.constraint(equalTo: stage.topAnchor),
            player.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            player.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            player.bottomAnchor.constraint(equalTo: stage.bottomAnchor)
        ])
        let customAction = mode == .custom ? UIAction(title: "Play or pause") { [weak session] _ in
            session?.togglePlayback()
        } : nil
        let customProgress = mode == .custom ? PlaybackControlsView(session: session) : nil
        if let customProgress {
            customProgress.showsProgressOnly = true
            customProgress.isHidden = true
            customProgress.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview(customProgress)
            NSLayoutConstraint.activate([
                customProgress.leadingAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                customProgress.trailingAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                customProgress.bottomAnchor.constraint(equalTo: stage.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ])
            immersiveTap.isEnabled = false
            player.addGestureRecognizer(immersiveTap)
        }
        fullscreenLayout = DemoFullscreenLayout(controller: self, workspace: workspace, stage: stage, details: inspector,
                                                extraAction: customAction, onScalingChange: { [weak player] fill in
            let scaling: PlaybackVideoScaling = fill ? .fill : .fit
            (player as? SinglePlaybackView)?.scaling = scaling
            (player as? VerticalPlaybackView)?.scaling = scaling
            (player as? PlaybackVideoView)?.scaling = scaling
        }, onImmersionChange: { [weak self, weak player, weak customProgress] immersive in
            let reveal: (() -> Void)? = immersive ? { [weak self] in self?.exitImmersivePlayback() } : nil
            if let single = player as? SinglePlaybackView {
                single.showsProgressOnly = immersive
                single.onVideoTap = reveal
            }
            if let feed = player as? VerticalPlaybackView {
                feed.showsProgressOnly = immersive
                feed.onVideoTap = reveal
            }
            if let customProgress {
                customProgress.isHidden = !immersive
                self?.immersiveTap.isEnabled = immersive
            }
        })

        render(session.snapshot)
        let stream = session.events()
        observations = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .snapshot(let snapshot):
                    self.render(snapshot)
                case .queueChanged, .presentationChanged:
                    if self.mode == .custom { self.renderCustomVideo() }
                case .ended where self.mode == .custom:
                    self.completion.text = "Playback completed. Press Replay to watch again."
                case .ended:
                    break
                }
            }
        }
    }

    private func installCoverDemo(on player: SinglePlaybackView) {
        configureLabel(coverStatus, color: .secondaryLabel)
        coverStatus.accessibilityIdentifier = "cover-status"
        player.onCoverStateChange = { [weak coverStatus] state in
            coverStatus?.text = switch state {
            case .noCover: "Cover: none"
            case .idle: "Cover: not needed"
            case .loading: "Cover: loading"
            case .loaded: "Cover: loaded"
            case .failed: "Cover: unavailable"
            }
        }
        player.onCoverStateChange?(player.coverState)
        let cases = [
            ("Slow cover", "slow"), ("Failed cover", "failed"),
            ("No cover", "no-cover"), ("Video arrives first", "frame-first")
        ]
        let actions = cases.map { title, id in
            UIAction(title: title) { [weak session] _ in session?.select(id) }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Cases", menu: UIMenu(children: actions))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fullscreenLayout?.update()
        let guidance = mode.isVertical ? "Swipe left/right sides vertically to adjust · Center to page"
            : "Slide up or down · Left for brightness · Right for volume"
        let helpText = view.bounds.width > view.bounds.height ? guidance : mode.help
        if help.text != helpText { help.text = helpText }
        if fullscreenLayout?.isFullscreen == false, let feed = feedView {
            let portrait = view.bounds.width / max(1, view.bounds.height) <= 0.7
            feed.scaling = portrait ? .fill : .fit
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fullscreenLayout?.update()
    }

    @objc private func exitImmersivePlayback() {
        fullscreenLayout?.exitImmersive()
    }

    override func accessibilityPerformEscape() -> Bool {
        fullscreenLayout?.exitImmersive() == true || super.accessibilityPerformEscape()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.deactivate()
    }

    private func makeCustomControls() -> UIView {
        configureLabel(progress, color: .label)
        configureLabel(completion, color: .secondaryLabel)
        completion.isHidden = true
        DemoStyle.styleButton(playPause, filled: true)
        DemoStyle.styleButton(skip)
        playPause.addAction(UIAction { [weak session] _ in session?.togglePlayback() }, for: .touchUpInside)
        skip.setTitle("+5 seconds", for: .normal)
        skip.addAction(UIAction { [weak session] _ in
            guard let session else { return }
            session.seek(to: session.snapshot.position + 5)
        }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [playPause, skip])
        buttons.distribution = .fillEqually
        buttons.spacing = 8
        let controls = UIStackView(arrangedSubviews: [progress, completion, buttons])
        controls.axis = .vertical
        controls.spacing = 4
        NSLayoutConstraint.activate([
            buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return controls
    }

    private func configureLabel(_ label: UILabel, color: UIColor) {
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = .natural
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func refreshDownload(_ source: PlaybackSource) {
        downloadButton.isEnabled = false
        downloadTask = Task { [weak self] in
            let file = await Self.downloads.localURL(for: source)
            guard !Task.isCancelled, let self else { return }
            renderDownload(available: file != nil)
        }
    }

    private func renderDownload(available: Bool, message: String? = nil) {
        hasDownload = available
        downloadStatus.text = message ?? (available ? "Available offline" : "Streaming online")
        downloadButton.setTitle(available ? "Delete local copy" : "Download video", for: .normal)
        downloadButton.isEnabled = true
    }

    private func manageDownload(_ source: PlaybackSource) {
        if hasDownload {
            let alert = UIAlertController(title: "Delete downloaded video?",
                                          message: "The video will play from the network again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                self?.changeDownload(source, deleting: true)
            })
            present(alert, animated: true)
        } else {
            changeDownload(source, deleting: false)
        }
    }

    private func changeDownload(_ source: PlaybackSource, deleting: Bool) {
        downloadButton.isEnabled = false
        downloadStatus.text = deleting ? "Removing local copy…" : "Downloading video…"
        downloadTask = Task { [weak self] in
            do {
                if deleting { try await Self.downloads.deleteDownload(for: source) }
                else { try await Self.downloads.download(source) }
                guard !Task.isCancelled, let self else { return }
                renderDownload(available: !deleting)
                // Keep the playhead when switching between remote and local media.
                let item = PlaybackItem(id: "remote", resumePosition: session.snapshot.position)
                if session.items.first == item { session.retry() }
                else { session.setItems([item]) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                renderDownload(available: deleting, message: deleting ? "Couldn’t delete the local copy." : "Download failed. Try again.")
            }
        }
    }

    private func installStreamingMenu() {
        let auto = UIAction(title: "Automatic", state: .on) { [weak session] _ in
            session?.setStreamPreferences(.init())
        }
        let limited = UIAction(title: "Data saver · 600 kbps preferred") { [weak session] _ in
            session?.setStreamPreferences(.init(preferredPeakBitRate: 600_000,
                                                preferredPeakBitRateForExpensiveNetworks: 600_000))
        }
        let quality = UIMenu(title: "Quality", options: .singleSelection, children: [auto, limited])
        let menu = UIMenu(children: [
            quality, trackMenu("Audio", kind: .audio), trackMenu("Subtitles", kind: .subtitles)
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Playback", menu: menu)
    }

    private func trackMenu(_ title: String, kind: PlaybackMediaTrackKind) -> UIMenu {
        let tracks = UIDeferredMenuElement.uncached { [weak self] completion in
            Task { @MainActor [weak self] in
                guard let session = self?.session, let group = await session.mediaTrackGroup(for: kind) else {
                    completion([UIAction(title: "No tracks available", attributes: .disabled) { _ in }])
                    return
                }
                let automatic = UIAction(title: "Automatic") { [weak session] _ in
                    session?.selectMediaTrack(.automatic, in: group)
                }
                var actions = [automatic]
                if group.allowsDisabling {
                    actions.append(UIAction(title: "Off", state: group.selectedTrackID == nil ? .on : .off) { [weak session] _ in
                        session?.selectMediaTrack(.off, in: group)
                    })
                }
                actions += group.tracks.map { track in
                    UIAction(title: track.displayName, state: track.id == group.selectedTrackID ? .on : .off) { [weak session] _ in
                        session?.selectMediaTrack(.track(track.id), in: group)
                    }
                }
                completion(actions)
            }
        }
        return UIMenu(title: title, children: [tracks])
    }

    private func observeDiagnostics(in label: UILabel) {
        let stream = session.diagnostics()
        diagnosticObservations = Task { [weak label] in
            for await event in stream {
                guard let label else { return }
                switch event.kind {
                case .started:
                    label.text = "Measuring startup…"
                case .firstFrame(let seconds):
                    label.text = "First frame · \((seconds * 1_000).formatted(.number.precision(.fractionLength(0)))) ms"
                case .rebufferingEnded(let seconds, let recovered):
                    let duration = seconds.formatted(.number.precision(.fractionLength(2)))
                    label.text = recovered ? "Rebuffered · \(duration) s" : "Rebuffer interrupted · \(duration) s"
                case .cachedMediaFallback:
                    label.text = "Retrying from the original source"
                case .finished(let outcome):
                    if case .failed = outcome { label.text = "Playback attempt failed" }
                }
            }
        }
    }

    private func render(_ snapshot: PlaybackSnapshot) {
        let state: String
        switch snapshot.state {
        case .idle: state = "Idle"
        case .preparing: state = "Preparing"
        case .ready: state = "Ready"
        case .playing: state = "Playing"
        case .buffering: state = "Buffering"
        case .paused: state = "Paused"
        case .ended: state = "Ended"
        case .accessRequired: state = "Access required"
        case .failed(.sourceUnavailable): state = "Source unavailable"
        case .failed(.sourceExpired): state = "Source expired"
        case .failed(.playbackFailed): state = "Playback failed"
        }
        let frame = snapshot.firstFrameReady ? "First frame ready" : "No first frame"
        status.text = state
        playbackDetail.text = "\(snapshot.itemID.map { "Clip \($0)" } ?? "No clip")  ·  \(frame)"
        switch snapshot.state {
        case .accessRequired:
            status.textColor = .systemOrange
            recovery.setTitle("Unlock episode", for: .normal)
            recovery.isHidden = false
        case .failed:
            status.textColor = .systemRed
            recovery.setTitle("Retry playback", for: .normal)
            recovery.isHidden = false
        default:
            status.textColor = snapshot.state == .playing ? .systemMint : .label
            recovery.isHidden = true
        }

        guard mode == .custom else { return }
        renderCustomVideo()
        let position = snapshot.position.formatted(.number.precision(.fractionLength(1)))
        let duration = snapshot.duration?.formatted(.number.precision(.fractionLength(1))) ?? "—"
        progress.text = "\(position) / \(duration) seconds"
        let canControlPlayback = [.ready, .playing, .paused, .buffering, .ended].contains(snapshot.state)
        playPause.isEnabled = canControlPlayback
        skip.isEnabled = canControlPlayback && (snapshot.duration ?? 0) > 0
        let action = snapshot.state == .ended ? "Replay" : (snapshot.wantsPlayback ? "Pause" : "Play")
        playPause.setTitle(action, for: .normal)
        completion.isHidden = snapshot.state != .ended
    }

    private func renderCustomVideo() {
        let item = session.items.first { $0.id == session.selectedID }
        let presentation = item.flatMap { session.presentation(for: $0.id) }
        customVideo.display(item, presentation: presentation, snapshot: session.snapshot)
    }

    private func recoverPlayback() {
        switch session.snapshot.state {
        case .accessRequired:
            guard let id = session.selectedID else { return }
            recovery.isEnabled = false
            Task { [weak self, access] in
                await access.unlock(id)
                guard let self else { return }
                self.recovery.isEnabled = true
                // A swipe while the host updates access must not retry a different episode.
                guard self.session.selectedID == id, self.session.snapshot.state == .accessRequired else { return }
                self.session.retry()
            }
        case .failed:
            session.retry()
        default:
            break
        }
    }

    deinit {
        observations?.cancel()
        diagnosticObservations?.cancel()
        downloadTask?.cancel()
    }
}

private struct DemoCoverLoader: PlaybackCoverLoader {
    func image(for url: URL) async -> UIImage? {
        let delay: Duration = url.lastPathComponent == "coffee-03.jpg" ? .seconds(6) : .seconds(1)
        do { try await Task.sleep(for: delay) }
        catch { return nil }
        return await URLPlaybackCoverLoader().image(for: url)
    }
}

/// In-memory entitlement for the demo. The host app owns the real entitlement service.
private actor DemoEpisodeAccess {
    private var lockedID: String?

    init(lockedID: String?) { self.lockedID = lockedID }

    func canPlay(_ id: String) -> Bool { lockedID != id }

    func unlock(_ id: String) {
        if lockedID == id { lockedID = nil }
    }
}
