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
        case single, landscape, feed, custom, access, remote(URL)

        var title: String {
            switch self {
            case .single: "Single video"
            case .landscape: "Landscape video"
            case .feed: "Vertical feed"
            case .custom: "Custom controls"
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
            case .access: "Episode 2 starts locked. Unlock it to continue."
            case .remote: "Use Retry if loading fails. Go back to try a different URL."
            }
        }

        var isVertical: Bool { self == .feed || self == .access }

        var configuration: PlaybackConfiguration {
            switch self {
            case .single, .landscape: .init(mode: .single, endBehavior: .loop, loadTimeout: 30)
            case .feed, .access: .init(mode: .vertical, preload: .preparedPlayer, endBehavior: .advance, loadTimeout: 30)
            case .custom: .init(autoplay: false, loadTimeout: 30)
            case .remote: .init(loadTimeout: 30)
            }
        }
    }

    private let mode: Mode
    private let session: PlaybackSession
    private let lifecycle: PlaybackLifecycle
    private let access: DemoEpisodeAccess
    private let status = UILabel()
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

    init?(mode: Mode) {
        self.mode = mode

        let items: [PlaybackItem]
        let urls: [String: URL]
        if case .remote(let url) = mode {
            items = [PlaybackItem(id: "remote")]
            urls = ["remote": url]
        } else {
            let ids = mode.isVertical ? ["01", "02", "03"] : [mode == .landscape ? "04" : "01"]
            let movies = ids.compactMap { id in
                Bundle.main.url(forResource: id, withExtension: "mp4").map { (id, $0) }
            }
            guard movies.count == ids.count else { return nil }
            urls = Dictionary(uniqueKeysWithValues: movies)
            items = ids.map { id in
                PlaybackItem(id: id, coverURL: Bundle.main.url(forResource: id, withExtension: "jpg"),
                             resumePosition: mode == .custom ? 2 : 0)
            }
        }

        let access = DemoEpisodeAccess(lockedID: mode == .access ? "02" : nil)
        self.access = access
        let resolver = PlaybackSourceResolver { item, _ in
            guard let url = urls[item.id] else { return .unavailable }
            // Playback and preload both check the same entitlement. The UI owns the unlock flow.
            guard await access.canPlay(item.id) else { return .requiresUserAction }
            return .allowed(.init(url: url, cacheKey: "demo/\(item.id)"))
        }
        session = PlaybackSession(configuration: mode.configuration, sourceProvider: resolver, logger: DemoLogging.logger)
        lifecycle = PlaybackLifecycle(session: session)
        super.init(nibName: nil, bundle: nil)
        session.setItems(items, selectedID: mode == .access ? "02" : nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = .black

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
            let single = SinglePlaybackView(session: session, scaling: .fit)
            single.isLandscapeAdjustmentEnabled = true
            player = single
        }

        configureLabel(help, color: .secondaryLabel)
        help.text = mode.help
        configureLabel(status, color: .systemMint)
        status.accessibilityIdentifier = "playback-status"

        recovery.addAction(UIAction { [weak self] _ in self?.recoverPlayback() }, for: .touchUpInside)
        recovery.isHidden = true
        var arrangedViews: [UIView] = [help, status, recovery, player]
        if mode == .custom { arrangedViews.append(makeCustomControls()) }
        if case .remote = mode {
            let diagnostics = UILabel()
            configureLabel(diagnostics, color: .secondaryLabel)
            diagnostics.text = "Waiting for playback diagnostics"
            diagnostics.accessibilityIdentifier = "playback-diagnostics"
            arrangedViews.insert(diagnostics, at: 2)
            observeDiagnostics(in: diagnostics)
            installStreamingMenu()
        }

        let stack = UIStackView(arrangedSubviews: arrangedViews)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let guidance = mode.isVertical ? "Swipe left/right sides vertically to adjust · Center to page"
            : "Slide up or down · Left for brightness · Right for volume"
        let helpText = view.bounds.width > view.bounds.height ? guidance : mode.help
        if help.text != helpText { help.text = helpText }
        if let feed = feedView, feed.bounds.height > 0 {
            // Keep portrait material intact in wide windows, including the unfolded display.
            feed.scaling = feed.bounds.width / feed.bounds.height > 0.7 ? .fit : .fill
        }
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
        playPause.addAction(UIAction { [weak session] _ in session?.togglePlayback() }, for: .touchUpInside)
        skip.setTitle("+5 seconds", for: .normal)
        skip.addAction(UIAction { [weak session] _ in
            guard let session else { return }
            session.seek(to: session.snapshot.position + 5)
        }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [playPause, skip])
        buttons.distribution = .fillEqually
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
        label.textAlignment = .center
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
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
        status.text = "\(snapshot.itemID ?? "—")  ·  \(state)  ·  \(frame)"
        switch snapshot.state {
        case .accessRequired:
            recovery.setTitle("Unlock episode", for: .normal)
            recovery.isHidden = false
        case .failed:
            recovery.setTitle("Retry playback", for: .normal)
            recovery.isHidden = false
        default:
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
