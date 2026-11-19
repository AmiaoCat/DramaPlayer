import UIKit

#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
import ReelsPlaybackUIKit
#endif

@MainActor
final class DemoTemplatesViewController: UIViewController {
    private let session: PlaybackSession
    private let lifecycle: PlaybackLifecycle
    private let player: SinglePlaybackView
    private var template = PlaybackLayoutTemplate(aspect: .portrait, scaling: .fit)
    private let templateButton = UIButton(type: .system)
    private let sourcePicker = UISegmentedControl(items: ["Portrait", "Landscape"])
    private let stage = UIView()
    private let viewport = UIView()
    private let miniPlayer = PlaybackMiniPlayerView()
    private let status = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private var observations: Task<Void, Never>?
    private var isMini = false
    private var portraitLayout: [NSLayoutConstraint] = []
    private var landscapeLayout: [NSLayoutConstraint] = []
    private var formatChoices: UIStackView?
    private var playbackActions: UIStackView?
    private var usesSidePanel = false

    init?(bundle: Bundle) {
        guard let portrait = bundle.url(forResource: "01", withExtension: "mp4"),
              let landscape = bundle.url(forResource: "04", withExtension: "mp4") else { return nil }
        let urls = ["01": portrait, "04": landscape]
        let sources = PlaybackSourceResolver { item, _ in
            guard let url = urls[item.id] else { return .unavailable }
            return .allowed(.init(url: url, cacheKey: item.id))
        }
        session = PlaybackSession(configuration: .init(endBehavior: .loop, loadTimeout: 30), sourceProvider: sources,
                                  logger: DemoLogging.logger)
        lifecycle = PlaybackLifecycle(session: session)
        player = SinglePlaybackView(session: session, showsControls: false, scaling: .fit)
        super.init(nibName: nil, bundle: nil)
        session.setItems(["01", "04"].map {
            PlaybackItem(id: $0, coverURL: bundle.url(forResource: $0, withExtension: "jpg"))
        })
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Video layouts"
        view.backgroundColor = DemoStyle.canvas

        sourcePicker.selectedSegmentIndex = 0
        sourcePicker.accessibilityLabel = "Video format"
        sourcePicker.addAction(UIAction { [weak self] _ in
            guard let self, session.items.indices.contains(sourcePicker.selectedSegmentIndex) else { return }
            session.select(session.items[sourcePicker.selectedSegmentIndex].id)
        }, for: .valueChanged)
        templateButton.showsMenuAsPrimaryAction = true
        templateButton.accessibilityIdentifier = "layout-template"
        DemoStyle.styleButton(templateButton)
        updateTemplateMenu()

        DemoStyle.styleSurface(stage, radius: 20)
        viewport.backgroundColor = .black
        viewport.clipsToBounds = true
        stage.addSubview(viewport)
        miniPlayer.isHidden = true
        stage.addSubview(miniPlayer)
        miniPlayer.onExpand = { [weak self] in self?.setMini(false) }
        miniPlayer.onSizeChanged = { [weak self] _ in self?.updateStatus() }

        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = DemoStyle.secondary
        status.textAlignment = .center
        status.numberOfLines = 0
        status.accessibilityIdentifier = "layout-status"

        DemoStyle.styleButton(playButton)
        DemoStyle.styleButton(toggleButton, filled: true)
        playButton.setTitle("Pause", for: .normal)
        playButton.addAction(UIAction { [weak session] _ in session?.togglePlayback() }, for: .touchUpInside)
        toggleButton.setTitle("Mini player", for: .normal)
        toggleButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            setMini(!isMini)
        }, for: .touchUpInside)
        let sizeButton = UIButton(type: .system)
        DemoStyle.styleButton(sizeButton)
        sizeButton.setTitle("Custom size", for: .normal)
        sizeButton.addAction(UIAction { [weak self] _ in self?.promptForSize() }, for: .touchUpInside)

        let playbackRow = UIStackView(arrangedSubviews: [playButton, toggleButton, sizeButton])
        playbackRow.distribution = .fillEqually
        playbackRow.spacing = 8
        for button in [playButton, toggleButton, sizeButton] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        let choices = UIStackView(arrangedSubviews: [sourcePicker, templateButton])
        choices.alignment = .center
        choices.distribution = .fillEqually
        choices.spacing = 8
        let settings = DemoStyle.panel([choices, status], spacing: 5, inset: 10)
        formatChoices = choices
        playbackActions = playbackRow
        for element in [settings, stage, playbackRow] {
            element.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(element)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stage.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            settings.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            settings.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            playbackRow.trailingAnchor.constraint(equalTo: settings.trailingAnchor),
            playbackRow.leadingAnchor.constraint(equalTo: settings.leadingAnchor),
            choices.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
            playbackRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        portraitLayout = [
            settings.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: settings.trailingAnchor),
            stage.topAnchor.constraint(equalTo: settings.bottomAnchor, constant: 10),
            stage.bottomAnchor.constraint(equalTo: playbackRow.topAnchor, constant: -10),
            playbackRow.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4)
        ]
        landscapeLayout = [
            settings.widthAnchor.constraint(equalToConstant: 224),
            stage.trailingAnchor.constraint(equalTo: settings.leadingAnchor, constant: -10),
            stage.topAnchor.constraint(equalTo: settings.topAnchor),
            stage.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),
            playbackRow.topAnchor.constraint(equalTo: settings.bottomAnchor, constant: 10)
        ]
        NSLayoutConstraint.activate(portraitLayout)
        mountPlayer(in: viewport)
        updateStatus()

        let events = session.events()
        observations = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                if case .snapshot = event { self.updateStatus() }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let sizeClass = view.safeAreaLayoutGuide.layoutFrame.size
        let wide = sizeClass.width >= 590 && sizeClass.width > sizeClass.height
        if usesSidePanel != wide {
            usesSidePanel = wide
            NSLayoutConstraint.deactivate(wide ? portraitLayout : landscapeLayout)
            formatChoices?.axis = wide ? .vertical : .horizontal
            formatChoices?.alignment = wide ? .fill : .center
            playbackActions?.axis = wide ? .vertical : .horizontal
            NSLayoutConstraint.activate(wide ? landscapeLayout : portraitLayout)
            view.layoutIfNeeded()
        }
        let size = template.fittedSize(in: stage.bounds.size)
        viewport.frame = CGRect(x: stage.bounds.midX - size.width / 2,
                                y: stage.bounds.midY - size.height / 2, width: size.width, height: size.height)
        miniPlayer.layout(in: stage.bounds.insetBy(dx: 6, dy: 6))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.activate()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.deactivate()
    }

    private func updateTemplateMenu() {
        let label = template.scaling == .fit ? "Fit" : "Fill"
        templateButton.setTitle("\(template.aspect.rawValue) · \(label)", for: .normal)
        templateButton.accessibilityLabel = "Template, \(template.aspect.rawValue), \(label)"
        let groups = PlaybackLayoutTemplate.Aspect.allCases.map { aspect in
            let actions = PlaybackLayoutTemplate.presets.filter { $0.aspect == aspect }.map { preset in
                UIAction(title: preset.scaling == .fit ? "Fit" : "Fill", state: preset == template ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    template = preset
                    player.scaling = preset.scaling
                    updateTemplateMenu()
                    view.setNeedsLayout()
                }
            }
            return UIMenu(title: aspect.rawValue, children: actions)
        }
        templateButton.menu = UIMenu(title: "12 layout templates", children: groups)
    }

    private func mountPlayer(in container: UIView) {
        player.removeFromSuperview()
        player.frame = container.bounds
        player.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(player)
    }

    private func setMini(_ enabled: Bool) {
        guard isMini != enabled else { return }
        isMini = enabled
        viewport.isHidden = enabled
        miniPlayer.isHidden = !enabled
        mountPlayer(in: enabled ? miniPlayer.contentView : viewport)
        toggleButton.setTitle(enabled ? "Expand" : "Mini player", for: .normal)
        view.setNeedsLayout()
        updateStatus()
    }

    private func updateStatus() {
        let snapshot = session.snapshot
        let time = snapshot.position.formatted(.number.precision(.fractionLength(1))) + " s"
        let size = miniPlayer.bounds.size
        let dimensions = isMini && size.width > 0 ? " · \(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt" : ""
        status.text = time + dimensions
        playButton.setTitle(snapshot.wantsPlayback ? "Pause" : "Play", for: .normal)
    }

    private func promptForSize() {
        let alert = UIAlertController(title: "Mini player size",
                                      message: "Enter width and height in points. The window stays inside the available area.",
                                      preferredStyle: .alert)
        let current = isMini ? miniPlayer.bounds.size : miniPlayer.preferredSize
        for (placeholder, value) in [("Width", current.width), ("Height", current.height)] {
            alert.addTextField { field in
                field.placeholder = placeholder
                field.accessibilityLabel = placeholder
                field.keyboardType = .numberPad
                field.text = Double(value).formatted(.number.grouping(.never).precision(.fractionLength(0)))
            }
        }
        let fields = alert.textFields ?? []
        let apply = UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self, let size = Self.size(from: fields) else { return }
            miniPlayer.setPreferredSize(size)
            setMini(true)
        }
        apply.isEnabled = Self.size(from: fields) != nil
        for field in fields {
            field.addAction(UIAction { [weak alert, weak apply] _ in
                apply?.isEnabled = Self.size(from: alert?.textFields ?? []) != nil
            }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(apply)
        present(alert, animated: true)
    }

    private static func size(from fields: [UITextField]) -> CGSize? {
        let values = fields.compactMap { field in
            field.text.flatMap { try? Int($0, format: IntegerFormatStyle<Int>.number) }
        }
        guard values.count == 2, values.allSatisfy({ $0 > 0 }) else { return nil }
        return CGSize(width: values[0], height: values[1])
    }

    deinit { observations?.cancel() }
}
