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
        introduction.text = "Three original motion studies, bundled for offline playback."

        let single = makeButton("Single video", subtitle: "Loop, seek, and change speed", icon: "play.rectangle") { [weak self] in
            self?.open(.single)
        }
        let feed = makeButton("Vertical feed", subtitle: "Swipe through three clips and revisit a prepared clip",
                              icon: "rectangle.portrait.on.rectangle.portrait") { [weak self] in
            self?.open(.feed)
        }

        let stack = UIStackView(arrangedSubviews: [eyebrow, heading, introduction, single, feed])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(28, after: introduction)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }

    private func open(_ mode: DemoPlayerViewController.Mode) {
        guard let player = DemoPlayerViewController(mode: mode) else {
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
