import UIKit

#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
import ReelsPlaybackUIKit
#endif

@MainActor
final class DemoCacheViewController: UIViewController {
    private enum Policy: Int, CaseIterable {
        case disabled, preparedPlayer, mediaBytes, custom

        var title: String {
            switch self {
            case .disabled: "Off"
            case .preparedPlayer: "Players"
            case .mediaBytes: "Bytes"
            case .custom: "Custom"
            }
        }

        var preload: PlaybackConfiguration.Preload {
            switch self {
            case .disabled: .disabled
            case .preparedPlayer: .preparedPlayer
            case .mediaBytes, .custom: .mediaBytes
            }
        }

        var instructions: String {
            switch self {
            case .disabled: "Choose another episode to load it on demand."
            case .preparedPlayer: "Watch for a player beside the next episode, then select it."
            case .mediaBytes: "Wait for Episode 2 to show Prefetched, then select it to see a Cache hit."
            case .custom: "Choose how many episodes to prefetch ahead or behind. Changes apply while the current episode plays."
            }
        }
    }

    private let items: [PlaybackItem]
    private let sourceProvider: PlaybackSourceResolver
    private let policies = UISegmentedControl(items: Policy.allCases.map(\.title))
    private let episodes = UISegmentedControl(items: ["Episode 1", "Episode 2", "Episode 3"])
    private let prefetchAhead = UISegmentedControl(items: ["0", "1", "2"])
    private let prefetchBehind = UISegmentedControl(items: ["0", "1", "2"])
    private let customControls = UIStackView()
    private let instructions = UILabel()
    private let activity = UILabel()
    private let playerContainer = UIView()
    private var playerView: SinglePlaybackView?
    private var session: PlaybackSession?
    private var lifecycle: PlaybackLifecycle?
    private var playbackEvents: Task<Void, Never>?
    private var cacheEvents: Task<Void, Never>?
    private var routes: [String: String] = [:]
    private var isVisible = false
    private let workspace = UIStackView()
    private var controlsWidth: NSLayoutConstraint?

    init?(bundle: Bundle) {
        let ids = ["01", "02", "03"]
        let movies = ids.compactMap { id in
            bundle.url(forResource: id, withExtension: "mp4").map { (id, $0) }
        }
        guard movies.count == ids.count else { return nil }
        let urls = Dictionary(uniqueKeysWithValues: movies)
        items = ids.map { PlaybackItem(id: $0, coverURL: bundle.url(forResource: $0, withExtension: "jpg")) }
        sourceProvider = PlaybackSourceResolver { item, _ in
            guard let url = urls[item.id] else { return .unavailable }
            return .allowed(.init(url: url, cacheKey: item.id))
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cache policies"
        view.backgroundColor = DemoStyle.canvas
        policies.accessibilityLabel = "Preload policy"
        episodes.accessibilityLabel = "Episode"
        policies.selectedSegmentIndex = Policy.mediaBytes.rawValue
        policies.addAction(UIAction { [weak self] _ in self?.startRun() }, for: .valueChanged)
        episodes.addAction(UIAction { [weak self] _ in
            guard let self, items.indices.contains(episodes.selectedSegmentIndex) else { return }
            session?.select(items[episodes.selectedSegmentIndex].id)
        }, for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", primaryAction: UIAction { [weak self] _ in
            self?.startRun()
        })

        instructions.font = .preferredFont(forTextStyle: .footnote)
        instructions.adjustsFontForContentSizeCategory = true
        instructions.textColor = .secondaryLabel
        instructions.numberOfLines = 0
        activity.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .medium))
        activity.adjustsFontForContentSizeCategory = true
        activity.textColor = .systemMint
        activity.numberOfLines = 0
        activity.accessibilityIdentifier = "cache-activity"

        customControls.axis = .vertical
        customControls.spacing = 8
        customControls.addArrangedSubview(makePrefetchRow("Episodes ahead", picker: prefetchAhead))
        customControls.addArrangedSubview(makePrefetchRow("Episodes behind", picker: prefetchBehind))
        let policyPanel = DemoStyle.panel([
            DemoStyle.label("Preload policy", style: .headline, weight: .semibold),
            policies, instructions, customControls
        ], spacing: 10)
        let activityPanel = DemoStyle.panel([
            DemoStyle.label("Cache activity", style: .headline, weight: .semibold), activity
        ], spacing: 6)
        DemoStyle.styleSurface(playerContainer, radius: 20, color: .black)
        let controls = UIStackView(arrangedSubviews: [policyPanel, episodes, activityPanel])
        controls.axis = .vertical
        controls.spacing = 10
        workspace.addArrangedSubview(controls)
        workspace.addArrangedSubview(playerContainer)
        workspace.axis = .vertical
        workspace.spacing = 12
        workspace.translatesAutoresizingMaskIntoConstraints = false
        controlsWidth = controls.widthAnchor.constraint(equalToConstant: 318)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(workspace)
        let safeArea = view.safeAreaLayoutGuide
        let preferredHeight = playerContainer.heightAnchor.constraint(equalTo: playerContainer.widthAnchor, multiplier: 0.98)
        preferredHeight.priority = .defaultHigh
        let preferredWidth = workspace.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            workspace.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            workspace.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor),
            workspace.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            workspace.widthAnchor.constraint(lessThanOrEqualToConstant: 880),
            workspace.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
            playerContainer.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.92),
            preferredHeight,
            preferredWidth
        ])
        startRun()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safeSize = view.safeAreaLayoutGuide.layoutFrame.size
        let wide = safeSize.width >= 640 && safeSize.width > safeSize.height
        let axis: NSLayoutConstraint.Axis = wide ? .horizontal : .vertical
        if workspace.axis != axis {
            controlsWidth?.isActive = false
            workspace.axis = axis
            workspace.alignment = wide ? .top : .fill
            controlsWidth?.isActive = wide
        }
    }

    private func makePrefetchRow(_ title: String, picker: UISegmentedControl) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.isAccessibilityElement = false
        picker.accessibilityLabel = title
        picker.selectedSegmentIndex = 1
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            session?.setMediaPrefetchPolicy(customPolicy)
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, picker])
        row.alignment = .center
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private var customPolicy: PlaybackMediaPrefetchPolicy {
        let ahead = (0..<max(0, prefetchAhead.selectedSegmentIndex)).map { $0 + 1 }
        let behind = (0..<max(0, prefetchBehind.selectedSegmentIndex)).map { -($0 + 1) }
        return .init(offsets: ahead + behind, maxCandidates: 4)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        session?.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        session?.deactivate()
    }

    private func startRun() {
        guard let policy = Policy(rawValue: policies.selectedSegmentIndex) else { return }
        playbackEvents?.cancel()
        cacheEvents?.cancel()
        session?.deactivate()
        session?.setItems([])
        playerView?.removeFromSuperview()
        routes.removeAll()
        instructions.text = policy.instructions
        customControls.isHidden = policy != .custom
        episodes.selectedSegmentIndex = 0

        // Reset and mode switches start fresh. Editing a custom plan keeps the current session.
        let (activityStream, continuation) = AsyncStream<DemoMediaCache.Activity>.makeStream()
        let store = DemoMediaCache(activity: continuation)
        let cache = PlaybackCacheAdapter(
            resolve: { await store.media(for: $0) },
            prefetch: { try await store.prefetch($0) },
            invalidate: { await store.invalidate($0) }
        )
        let session = PlaybackSession(
            configuration: .init(mode: .vertical, preload: policy.preload, loadTimeout: 30),
            sourceProvider: sourceProvider,
            cache: cache,
            logger: DemoLogging.logger
        )
        self.session = session
        lifecycle = PlaybackLifecycle(session: session)
        if policy == .custom { session.setMediaPrefetchPolicy(customPolicy) }
        session.setItems(items)

        // Keep vertical-mode preloading while choosing episodes explicitly from the host UI.
        let player = SinglePlaybackView(session: session, scaling: .fit)
        player.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(player)
        NSLayoutConstraint.activate([
            player.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            player.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            player.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            player.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor)
        ])
        playerView = player

        let stream = session.events()
        playbackEvents = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .snapshot, .presentationChanged: self.renderActivity()
                case .ended, .queueChanged: break
                }
            }
        }
        cacheEvents = Task { [weak self] in
            for await update in activityStream {
                guard !Task.isCancelled, let self else { return }
                self.routes[update.key] = update.description
                self.renderActivity()
            }
        }
        renderActivity()
        if isVisible { session.activate() }
    }

    private func renderActivity() {
        let text = items.map { item in
            var details = [routes[item.id] ?? "Not requested"]
            if let presentation = session?.presentation(for: item.id) {
                details.append(presentation.firstFrameReady ? "Frame ready" : "Player attached")
            }
            return "Episode \(item.id) · " + details.joined(separator: " · ")
        }.joined(separator: "\n")
        if activity.text != text { activity.text = text }
    }

    deinit {
        playbackEvents?.cancel()
        cacheEvents?.cancel()
    }
}

/// A temporary disk store for the three bundled MP4s. Only completed copies are advertised as hits.
private actor DemoMediaCache {
    struct Activity: Sendable {
        let key: String
        let description: String
    }

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    private let activity: AsyncStream<Activity>.Continuation
    private var files: [String: URL] = [:]

    init(activity: AsyncStream<Activity>.Continuation) {
        self.activity = activity
    }

    func media(for source: PlaybackSource) -> PlaybackMedia {
        if let url = files[source.cacheKey], FileManager.default.isReadableFile(atPath: url.path) {
            report("Cache hit", for: source)
            return PlaybackMedia(url: url, isCached: true)
        }
        report("Source file", for: source)
        return PlaybackMedia(url: source.url)
    }

    func prefetch(_ source: PlaybackSource) throws {
        try Task.checkCancellation()
        if let url = files[source.cacheKey], FileManager.default.isReadableFile(atPath: url.path) { return }
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: source.url, to: destination)
            try Task.checkCancellation()
            files[source.cacheKey] = destination
            report("Prefetched", for: source)
        } catch {
            try? manager.removeItem(at: destination)
            if !(error is CancellationError) { report("Prefetch failed", for: source) }
            throw error
        }
    }

    func invalidate(_ source: PlaybackSource) {
        if let file = files.removeValue(forKey: source.cacheKey) {
            try? FileManager.default.removeItem(at: file)
        }
        report("Cache invalidated", for: source)
    }

    private func report(_ description: String, for source: PlaybackSource) {
        activity.yield(Activity(key: source.cacheKey, description: description))
    }

    deinit {
        activity.finish()
        try? FileManager.default.removeItem(at: directory)
    }
}
