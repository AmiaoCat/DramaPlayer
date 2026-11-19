import UIKit

#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
import ReelsPlaybackUIKit
#endif

struct DemoSeries {
    struct Episode {
        let id: String
        let title: String
    }

    let title: String
    let genre: String
    let license: String
    let source: String
    let episodes: [Episode]

    static let catalog: [Self] = [
        .init(title: "Tears of Steel", genre: "Live-action sci-fi", license: "CC BY 3.0",
              source: "https://commons.wikimedia.org/wiki/File:Tears_of_Steel_in_4k_-_Official_Blender_Foundation_release.webm",
              episodes: [
                .init(id: "steel-01", title: "The Briefing"),
                .init(id: "steel-02", title: "The Bridge"),
                .init(id: "steel-03", title: "The Experiment"),
                .init(id: "steel-04", title: "The Last Stand")
              ]),
        .init(title: "Coffee Run", genre: "Animated drama", license: "CC BY 4.0",
              source: "https://commons.wikimedia.org/wiki/File:Coffee_Run_-_Blender_Open_Movie-full_movie.webm",
              episodes: [
                .init(id: "coffee-01", title: "The First Sip"),
                .init(id: "coffee-02", title: "A Life Together"),
                .init(id: "coffee-03", title: "Letting Go"),
                .init(id: "coffee-04", title: "Moving Forward")
              ]),
        .init(title: "Charge", genre: "Animated sci-fi", license: "CC BY 4.0",
              source: "https://commons.wikimedia.org/wiki/File:Charge_-_Blender_Open_Movie-full_movie.webm",
              episodes: [
                .init(id: "charge-01", title: "Power Shortage"),
                .init(id: "charge-02", title: "The Break-in"),
                .init(id: "charge-03", title: "Security Breach"),
                .init(id: "charge-04", title: "Back Home")
              ])
    ]

    static let labEpisodeIDs = ["charge-01", "charge-02", "charge-03"]
    static let landscapeID = "charge-landscape"

    static func asset(_ id: String, _ ext: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: id, withExtension: ext, subdirectory: "Series")
    }
}

@MainActor
final class DemoSeriesViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private static let resumeKey = "DramaPlayerDemo.SeriesResume.v1"
    private let session: PlaybackSession
    private let lifecycle: PlaybackLifecycle
    private let player: VerticalPlaybackView
    private let context = DemoStyle.label(style: .caption1, weight: .semibold, color: DemoStyle.accent)
    private let headline = DemoStyle.label(style: .headline, weight: .bold)
    private let playbackState = DemoStyle.label(style: .footnote, color: DemoStyle.secondary)
    private let recovery = UIButton(type: .system)
    private let sound = UIBarButtonItem()
    private var audibleVolume: Float = 1
    private var events: Task<Void, Never>?
    private let episodes = DemoSeries.catalog.flatMap(\.episodes)
    private let layout = UIStackView()
    private var fullscreenLayout: DemoFullscreenLayout?

    override var prefersStatusBarHidden: Bool { fullscreenLayout?.isFullscreen ?? false }

    init?(bundle: Bundle) {
        var videos: [String: URL] = [:]
        var queue: [PlaybackItem] = []
        let resume = UserDefaults.standard.dictionary(forKey: Self.resumeKey)
        let resumeID = resume?["id"] as? String
        let resumePosition = resume?["position"] as? Double ?? 0
        for series in DemoSeries.catalog {
            for episode in series.episodes {
                guard let video = DemoSeries.asset(episode.id, "mp4", bundle: bundle),
                      let cover = DemoSeries.asset(episode.id, "jpg", bundle: bundle) else { return nil }
                videos[episode.id] = video
                queue.append(.init(id: episode.id, coverURL: cover,
                                   resumePosition: episode.id == resumeID ? resumePosition : 0))
            }
        }
        let sources = videos
        let resolver = PlaybackSourceResolver { item, _ in
            guard let url = sources[item.id] else { return .unavailable }
            return .allowed(.init(url: url, cacheKey: item.id))
        }
        session = PlaybackSession(configuration: .init(mode: .vertical, preload: .preparedPlayer, endBehavior: .advance,
                                                       loadTimeout: 15), sourceProvider: resolver, logger: DemoLogging.logger)
        lifecycle = PlaybackLifecycle(session: session)
        player = VerticalPlaybackView(session: session, scaling: .fit)
        super.init(nibName: nil, bundle: nil)
        session.setItems(queue, selectedID: resumeID)
        session.setVolume(0)
        player.isLandscapeAdjustmentEnabled = true
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Drama feed"
        view.backgroundColor = DemoStyle.canvas
        DemoStyle.styleSurface(player, radius: 20, color: .black)
        context.accessibilityIdentifier = "series-episode-index"
        headline.accessibilityIdentifier = "series-episode-title"
        DemoStyle.styleButton(recovery)
        recovery.setTitle("Retry episode", for: .normal)
        recovery.addAction(UIAction { [weak session] _ in session?.retry() }, for: .touchUpInside)
        let details = DemoStyle.panel([context, headline, playbackState, recovery], spacing: 4, inset: 12)

        sound.primaryAction = UIAction { [weak self] _ in self?.toggleSound() }
        let browse = UIBarButtonItem(title: "Episodes", primaryAction: UIAction { [weak self] _ in
            self?.showCatalog()
        })
        navigationItem.rightBarButtonItems = [browse, sound]

        fullscreenLayout = DemoFullscreenLayout(controller: self, workspace: layout, stage: player, details: details,
                                                onScalingChange: {
            [weak player] fill in player?.scaling = fill ? .fill : .fit
        }, onImmersionChange: { [weak self] immersive in
            self?.player.showsProgressOnly = immersive
            self?.player.onVideoTap = immersive ? { [weak self] in _ = self?.fullscreenLayout?.exitImmersive() } : nil
        })
        render(session.snapshot)
        let stream = session.events()
        events = Task { [weak self] in
            for await event in stream {
                if case .snapshot(let snapshot) = event { self?.render(snapshot) }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fullscreenLayout?.update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fullscreenLayout?.update()
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
        let snapshot = session.snapshot
        if let id = snapshot.itemID {
            let closeToEnd = snapshot.duration.map { $0 - snapshot.position < 0.5 } ?? false
            UserDefaults.standard.set(["id": id, "position": closeToEnd ? 0 : snapshot.position], forKey: Self.resumeKey)
        }
        session.deactivate()
    }

    private func render(_ snapshot: PlaybackSnapshot) {
        guard let index = episodes.firstIndex(where: { $0.id == snapshot.itemID }),
              let series = DemoSeries.catalog.first(where: { $0.episodes.contains { $0.id == snapshot.itemID } }) else { return }
        context.text = "EP \(index + 1) / \(episodes.count)  •  \(series.genre)"
        headline.text = "\(series.title)  ·  \(episodes[index].title)"
        switch snapshot.state {
        case .preparing: playbackState.text = "Preparing video…"
        case .buffering: playbackState.text = "Buffering…"
        case .failed: playbackState.text = "Couldn’t play this episode."
        case .ended: playbackState.text = "Episode complete"
        case .paused: playbackState.text = "Paused"
        default: playbackState.text = index + 1 < episodes.count ? "Swipe up for the next episode" : "Final episode"
        }
        if case .failed = snapshot.state { recovery.isHidden = false } else { recovery.isHidden = true }
        updateSoundButton()
    }

    private func toggleSound() {
        if session.volume > 0 {
            audibleVolume = session.volume
            session.setVolume(0)
        } else {
            session.setVolume(audibleVolume)
        }
        updateSoundButton()
    }

    private func updateSoundButton() {
        let muted = session.volume == 0
        sound.image = UIImage(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        sound.accessibilityLabel = muted ? "Unmute" : "Mute"
    }

    private func showCatalog() {
        guard presentedViewController == nil else { return }
        let catalog = DemoEpisodePicker(selectedID: session.selectedID)
        let navigation = UINavigationController(rootViewController: catalog)
        navigation.navigationBar.tintColor = DemoStyle.accent
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        navigation.presentationController?.delegate = self
        catalog.onSelect = { [weak self] id in
            self?.session.select(id)
            self?.closeCatalog()
        }
        catalog.onClose = { [weak self] in self?.closeCatalog() }
        session.setSuspended(true, reason: .overlay)
        present(navigation, animated: true)
    }

    private func closeCatalog() {
        dismiss(animated: true) { [weak self] in
            self?.session.setSuspended(false, reason: .overlay)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        session.setSuspended(false, reason: .overlay)
    }

    deinit { events?.cancel() }
}

@MainActor
private final class DemoEpisodePicker: UIViewController {
    var onSelect: ((String) -> Void)?
    var onClose: (() -> Void)?
    private let selectedID: String?

    init(selectedID: String?) {
        self.selectedID = selectedID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "12 episodes"
        view.backgroundColor = DemoStyle.canvas
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.onClose?()
        })
        let links = DemoSeries.catalog.map { series in
            UIAction(title: "\(series.title) · \(series.license)", image: UIImage(systemName: "arrow.up.right.square")) { _ in
                if let url = URL(string: series.source) { UIApplication.shared.open(url) }
            }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Credits", menu: UIMenu(title: "Blender Foundation", children: links))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        var number = 1
        for series in DemoSeries.catalog {
            let title = DemoStyle.label(series.title, style: .title3, weight: .bold)
            title.accessibilityTraits.insert(.header)
            let credit = DemoStyle.label("\(series.genre) · Blender Foundation · \(series.license)",
                                         style: .caption1, color: DemoStyle.secondary)
            let row = UIStackView(arrangedSubviews: series.episodes.map { episode in
                defer { number += 1 }
                return makeTile(episode, number: number)
            })
            row.spacing = 8
            row.distribution = .fillEqually
            let section = UIStackView(arrangedSubviews: [title, credit, row])
            section.axis = .vertical
            section.spacing = 5
            section.setCustomSpacing(9, after: credit)
            stack.addArrangedSubview(section)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        let width = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -28)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -22),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 540),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -28),
            width
        ])
    }

    private func makeTile(_ episode: DemoSeries.Episode, number: Int) -> UIButton {
        let tile = UIButton(type: .custom)
        DemoStyle.styleSurface(tile, radius: 12)
        tile.accessibilityLabel = "Episode \(number), \(episode.title)"
        tile.accessibilityIdentifier = "series-select-\(episode.id)"
        if selectedID == episode.id {
            tile.layer.borderColor = DemoStyle.accent.cgColor
            tile.layer.borderWidth = 2
            tile.accessibilityTraits.insert(.selected)
        }
        tile.addAction(UIAction { [weak self] _ in self?.onSelect?(episode.id) }, for: .touchUpInside)

        let poster = UIImageView(image: DemoSeries.asset(episode.id, "jpg").flatMap { UIImage(contentsOfFile: $0.path) })
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        let caption = DemoStyle.label("\(number)  \(episode.title)", style: .caption2, weight: .medium)
        caption.numberOfLines = 2
        let content = UIStackView(arrangedSubviews: [poster, caption])
        content.axis = .vertical
        content.spacing = 5
        content.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 6, trailing: 0)
        content.isLayoutMarginsRelativeArrangement = true
        content.isUserInteractionEnabled = false
        content.accessibilityElementsHidden = true
        content.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: tile.topAnchor),
            content.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor),
            poster.heightAnchor.constraint(equalTo: poster.widthAnchor, multiplier: 1.34),
            caption.heightAnchor.constraint(greaterThanOrEqualToConstant: 29)
        ])
        return tile
    }
}
