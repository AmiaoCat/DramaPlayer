import UIKit

final class DemoMenuViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DramaPlayer"
        view.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1)

        let eyebrow = UILabel()
        eyebrow.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        eyebrow.textColor = .systemMint
        eyebrow.text = "AVFOUNDATION  /  UIKIT"

        let heading = UILabel()
        heading.font = .preferredFont(forTextStyle: .largeTitle).bold()
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0
        heading.text = "Playback lab"

        let introduction = UILabel()
        introduction.font = .preferredFont(forTextStyle: .body)
        introduction.adjustsFontForContentSizeCategory = true
        introduction.textColor = .secondaryLabel
        introduction.numberOfLines = 0
        introduction.text = "Try playback, episode access, and caching with bundled clips, or test your own HTTPS video."

        let single = makeButton("Single video", subtitle: "Loop, seek, and change speed", icon: "play.rectangle") { [weak self] in
            self?.open(.single)
        }
        let landscape = makeButton("Landscape video", subtitle: "Rotate the screen while a 16:9 clip plays",
                                   icon: "rectangle.landscape.rotate") { [weak self] in
            self?.open(.landscape)
        }
        let templates = makeButton("Video layouts", subtitle: "Try 12 templates and a resizable mini player",
                                   icon: "pip") { [weak self] in
            self?.pushDemo(DemoTemplatesViewController(bundle: .main))
        }
        let feed = makeButton("Vertical feed", subtitle: "Swipe through three clips and revisit a prepared clip",
                              icon: "rectangle.portrait.on.rectangle.portrait") { [weak self] in
            self?.open(.feed)
        }
        let custom = makeButton("Custom controls", subtitle: "Resume from a saved position and control playback",
                                icon: "slider.horizontal.3") { [weak self] in
            self?.open(.custom)
        }
        let access = makeButton("Episode access", subtitle: "Unlock a gated episode and retry playback",
                                icon: "lock.open") { [weak self] in
            self?.open(.access)
        }
        let cache = makeButton("Cache policies", subtitle: "Compare player preparation, disk prefetch, and on-demand playback",
                               icon: "internaldrive") { [weak self] in
            self?.pushDemo(DemoCacheViewController(bundle: .main))
        }
        let remote = makeButton("Remote playback", subtitle: "Try an HTTPS MP4 or HLS URL",
                                icon: "link") { [weak self] in
            self?.promptForURL()
        }

        let stack = UIStackView(arrangedSubviews: [eyebrow, heading, introduction, single, landscape, templates, feed, custom, access, cache, remote])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(28, after: introduction)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        let preferredWidth = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 36),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            preferredWidth
        ])
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
        alert.addAction(UIAlertAction(title: "Apple HLS sample", style: .default) { [weak self] _ in
            guard let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8") else { return }
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
        navigationController?.pushViewController(player, animated: true)
    }

    private func makeButton(_ title: String, subtitle: String, icon: String,
                            action: @escaping () -> Void) -> UIButton {
        var style = UIButton.Configuration.filled()
        style.title = title
        style.subtitle = subtitle
        style.image = UIImage(systemName: icon)
        style.imagePadding = 12
        style.titlePadding = 4
        style.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        style.cornerStyle = .large
        style.baseBackgroundColor = UIColor(red: 0.13, green: 0.20, blue: 0.24, alpha: 1)
        style.baseForegroundColor = .white
        let button = UIButton(configuration: style, primaryAction: UIAction { _ in action() })
        button.contentHorizontalAlignment = .leading
        return button
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
