import UIKit

final class DemoMenuViewController: UIViewController {
    private let groups = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backButtonDisplayMode = .minimal
        view.backgroundColor = DemoStyle.canvas

        let featured = makeFeaturedFeed()
        let quick = UIStackView(arrangedSubviews: [
            compactCard("Single video", detail: "Loop and seek", icon: "play.rectangle") { [weak self] in self?.open(.single) },
            compactCard("Landscape video", detail: "Rotate and adjust", icon: "rectangle.landscape.rotate") { [weak self] in
                self?.open(.landscape)
            }
        ])
        quick.spacing = 10
        quick.distribution = .fillEqually

        let tools = section("Playback tools", rows: [
            row("Vertical feed lab", detail: "Inspect prepared-player reuse with film excerpts",
                icon: "rectangle.portrait.on.rectangle.portrait") { [weak self] in self?.open(.feed) },
            row("Video layouts", detail: "12 templates and a resizable mini player", icon: "pip") { [weak self] in
                self?.pushDemo(DemoTemplatesViewController(bundle: .main))
            },
            row("Custom controls", detail: "Resume, skip ahead, and replay", icon: "slider.horizontal.3") { [weak self] in
                self?.open(.custom)
            }
        ])
        let labs = section("Integration labs", rows: [
            row("Cover loading", detail: "Test missing artwork and first-frame timing", icon: "photo") { [weak self] in
                self?.open(.cover)
            },
            row("Cache policies", detail: "Compare prefetch, reuse, and cache hits", icon: "internaldrive") { [weak self] in
                self?.pushDemo(DemoCacheViewController(bundle: .main))
            },
            row("Episode access", detail: "Unlock an episode and retry playback", icon: "lock.open") { [weak self] in
                self?.open(.access)
            },
            row("Remote playback", detail: "Stream HLS or download an MP4 for offline playback", icon: "antenna.radiowaves.left.and.right") { [weak self] in
                self?.promptForURL()
            }
        ])
        groups.axis = .vertical
        groups.alignment = .fill
        groups.spacing = 20
        groups.addArrangedSubview(tools)
        groups.addArrangedSubview(labs)

        let stack = UIStackView(arrangedSubviews: [makeMasthead(), featured, quick, groups])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: quick)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        let preferredWidth = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)
        preferredWidth.priority = .defaultHigh
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 880),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -36),
            preferredWidth
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wide = view.safeAreaLayoutGuide.layoutFrame.width >= 700
        let axis: NSLayoutConstraint.Axis = wide ? .horizontal : .vertical
        guard groups.axis != axis else { return }
        groups.axis = axis
        groups.alignment = wide ? .top : .fill
        groups.distribution = wide ? .fillEqually : .fill
    }

    private func makeMasthead() -> UIView {
        let brand = DemoStyle.label("DramaPlayer", style: .title2, weight: .bold)
        brand.accessibilityTraits.insert(.header)
        let subtitle = DemoStyle.label("Short Drama Player SDK", style: .footnote, weight: .medium, color: DemoStyle.secondary)
        let name = UIStackView(arrangedSubviews: [brand, subtitle])
        name.axis = .vertical
        name.spacing = 1
        let masthead = UIStackView(arrangedSubviews: [iconView("play.fill", size: 41), name, UIView()])
        masthead.alignment = .center
        masthead.spacing = 11
        masthead.accessibilityIdentifier = "demo-masthead"
        return masthead
    }

    private func makeFeaturedFeed() -> UIView {
        let card = UIView()
        DemoStyle.styleSurface(card, radius: 24)
        let artwork = FeaturedArtworkView()
        artwork.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(artwork)

        let title = DemoStyle.label("Drama collection", style: .largeTitle, weight: .bold, color: .white)
        title.accessibilityTraits.insert(.header)
        let description = DemoStyle.label("12 vertical episodes from three open films.", style: .subheadline,
                                          weight: .medium, color: UIColor(white: 0.9, alpha: 1))
        let launch = UIButton(type: .system)
        DemoStyle.styleButton(launch, filled: true)
        var style = launch.configuration
        style?.title = "Open feed"
        style?.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        style?.imagePadding = 8
        launch.configuration = style
        launch.accessibilityIdentifier = "open-featured-feed"
        launch.addAction(UIAction { [weak self] _ in
            self?.pushDemo(DemoSeriesViewController(bundle: .main))
        }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [title, description, launch])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 5
        text.setCustomSpacing(13, after: description)
        text.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(text)
        let readableWidth = text.widthAnchor.constraint(equalTo: card.widthAnchor, multiplier: 0.64)
        readableWidth.priority = .defaultHigh
        let preferredHeight = card.heightAnchor.constraint(equalToConstant: 224)
        preferredHeight.priority = UILayoutPriority(760)
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        description.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: card.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            text.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -18),
            text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
            text.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 20),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 224),
            preferredHeight,
            launch.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            readableWidth
        ])
        return card
    }

    private func section(_ title: String, rows: [UIControl]) -> UIView {
        let heading = DemoStyle.label(title, style: .title3, weight: .bold)
        heading.accessibilityTraits.insert(.header)
        let list = UIStackView()
        list.axis = .vertical
        DemoStyle.styleSurface(list)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = DemoStyle.divider
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                list.addArrangedSubview(line)
            }
            list.addArrangedSubview(row)
        }
        let section = UIStackView(arrangedSubviews: [heading, list])
        section.axis = .vertical
        section.spacing = 9
        return section
    }

    private func row(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> UIControl {
        let text = UIStackView(arrangedSubviews: [
            DemoStyle.label(title, style: .subheadline, weight: .semibold),
            DemoStyle.label(detail, style: .footnote, color: DemoStyle.secondary)
        ])
        text.axis = .vertical
        text.spacing = 3
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
        chevron.tintColor = DemoStyle.secondary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let content = UIStackView(arrangedSubviews: [iconView(icon, size: 35), text, chevron])
        content.alignment = .center
        content.spacing = 11
        return DemoMenuItem(title: title, detail: detail, content: content, inset: 12, action: action)
    }

    private func compactCard(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> UIControl {
        let labels = UIStackView(arrangedSubviews: [
            DemoStyle.label(title, style: .subheadline, weight: .semibold),
            DemoStyle.label(detail, style: .footnote, color: DemoStyle.secondary)
        ])
        labels.axis = .vertical
        labels.spacing = 2
        let content = UIStackView(arrangedSubviews: [iconView(icon, size: 32), labels])
        content.axis = .vertical
        content.alignment = .leading
        content.spacing = 8
        let card = DemoMenuItem(title: title, detail: detail, content: content, inset: 12, action: action)
        DemoStyle.styleSurface(card)
        return card
    }

    private func iconView(_ symbol: String, size: CGFloat) -> UIView {
        let badge = UIView()
        badge.backgroundColor = DemoStyle.accent.withAlphaComponent(0.13)
        badge.layer.cornerRadius = size * 0.30
        badge.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol,
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        icon.tintColor = DemoStyle.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(icon)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: size),
            badge.heightAnchor.constraint(equalTo: badge.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private func promptForURL() {
        let alert = UIAlertController(title: "Remote playback", message: "Paste a direct HTTPS MP4 or HLS playlist URL.",
                                      preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "https://example.com/video.m3u8"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let field = alert.textFields?.first
        let start = UIAlertAction(title: "Play", style: .default) { [weak self, weak field] _ in
            guard let url = Self.httpsURL(from: field?.text) else { return }
            self?.open(.remote(url))
        }
        start.isEnabled = false
        field?.addAction(UIAction { [weak field, weak start] _ in
            start?.isEnabled = Self.httpsURL(from: field?.text) != nil
        }, for: .editingChanged)
        alert.addAction(start)
        alert.addAction(UIAlertAction(title: "Tears of Steel (HLS)", style: .default) { [weak self] _ in
            guard let url = URL(string: "https://test-streams.mux.dev/tos_ismc/main.m3u8") else { return }
            self?.open(.remote(url))
        })
        alert.addAction(UIAlertAction(title: "Sintel Trailer (MP4)", style: .default) { [weak self] _ in
            guard let url = URL(string: "https://media.w3.org/2010/05/sintel/trailer.mp4") else { return }
            self?.open(.remote(url))
        })
        present(alert, animated: true)
    }

    private static func httpsURL(from text: String?) -> URL? {
        guard let input = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: input), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private func open(_ mode: DemoPlayerViewController.Mode) {
        pushDemo(DemoPlayerViewController(mode: mode))
    }

    private func pushDemo(_ player: UIViewController?) {
        guard let player else {
            let alert = UIAlertController(title: "Demo media unavailable",
                                          message: "Build the shared DramaPlayerDemo scheme with its bundled media.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.pushViewController(player, animated: true)
    }

}

private final class DemoMenuItem: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.68 : 1 }
    }

    init(title: String, detail: String, content: UIView, inset: CGFloat, action: @escaping () -> Void) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
        accessibilityValue = detail
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { nil }
}

private final class FeaturedArtworkView: UIView {
    private let shade = CAGradientLayer()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        let stills = ["steel-01", "coffee-02", "charge-03"].map { id in
            let image = DemoSeries.asset(id, "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            return view
        }
        let strip = UIStackView(arrangedSubviews: stills)
        strip.distribution = .fillEqually
        strip.spacing = 3
        strip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        shade.colors = [UIColor.black.withAlphaComponent(0.91).cgColor,
                        UIColor.black.withAlphaComponent(0.58).cgColor,
                        UIColor.black.withAlphaComponent(0.10).cgColor]
        shade.locations = [0, 0.56, 1]
        shade.startPoint = CGPoint(x: 0, y: 0.9)
        shade.endPoint = CGPoint(x: 1, y: 0.15)
        layer.addSublayer(shade)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = bounds
    }
}
