import UIKit

#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
import ReelsPlaybackUIKit
#endif

final class DemoPlayerViewController: UIViewController {
    enum Mode {
        case single, feed

        var title: String { self == .single ? "Single video" : "Vertical feed" }

        var configuration: PlaybackConfiguration {
            switch self {
            case .single: .init(mode: .single, endBehavior: .loop)
            case .feed: .init(mode: .vertical, preload: .preparedPlayer, endBehavior: .advance)
            }
        }
    }

    private let mode: Mode
    private let session: PlaybackSession
    private let lifecycle: PlaybackLifecycle
    private let status = UILabel()
    private var observations: Task<Void, Never>?

    init?(mode: Mode) {
        self.mode = mode
        let ids = mode == .single ? ["01"] : ["01", "02", "03"]
        let movies = ids.compactMap { id in
            Bundle.main.url(forResource: id, withExtension: "mp4").map { (id, $0) }
        }
        guard movies.count == ids.count else { return nil }

        let urls = Dictionary(uniqueKeysWithValues: movies)
        let resolver = PlaybackSourceResolver { item, _ in
            guard let url = urls[item.id] else { return .unavailable }
            return .allowed(.init(url: url, cacheKey: "motion-study/\(item.id)"))
        }
        session = PlaybackSession(configuration: mode.configuration, sourceProvider: resolver)
        lifecycle = PlaybackLifecycle(session: session)
        super.init(nibName: nil, bundle: nil)
        session.setItems(ids.map { id in
            PlaybackItem(id: id, coverURL: Bundle.main.url(forResource: id, withExtension: "jpg"))
        })
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = .black

        let player: UIView
        switch mode {
        case .single: player = SinglePlaybackView(session: session)
        case .feed: player = VerticalPlaybackView(session: session)
        }

        let help = UILabel()
        help.font = .preferredFont(forTextStyle: .caption1)
        help.adjustsFontForContentSizeCategory = true
        help.textColor = .secondaryLabel
        help.textAlignment = .center
        help.numberOfLines = 0
        help.text = mode == .feed ? "Swipe up or down to switch clips" : "Tap the video to play or pause"
        status.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        status.textColor = .systemMint
        status.textAlignment = .center
        status.accessibilityIdentifier = "playback-status"

        let stack = UIStackView(arrangedSubviews: [help, status, player])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let stream = session.events()
        observations = Task { [weak self] in
            for await event in stream {
                guard let self, case .snapshot(let snapshot) = event else { continue }
                let id = snapshot.itemID ?? "—"
                let frame = snapshot.firstFrameReady ? "FRAME READY" : "WAITING FOR FRAME"
                self.status.text = "\(id)  •  \(String(describing: snapshot.state).uppercased())  •  \(frame)"
            }
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

    deinit { observations?.cancel() }
}
