import UIKit

/// Changes the host layout without moving the player or replacing its session.
@MainActor
final class DemoFullscreenLayout {
    private weak var controller: UIViewController?
    private let workspace: UIStackView
    private let stage: UIView
    private let details: UIView
    private let onScalingChange: (Bool) -> Void
    private let onImmersionChange: (Bool) -> Void
    private let back = UIButton(type: .system)
    private let fit = UIButton(type: .system)
    private let actions = UIStackView()
    private let expand = UIBarButtonItem()
    private var inline: [NSLayoutConstraint] = []
    private var edgeToEdge: [NSLayoutConstraint] = []
    private var sidePanel: [NSLayoutConstraint] = []
    private var wasLandscape = false
    private var showsDetails = false
    private var fillsScreen = false
    private(set) var isFullscreen = false
    private var isImmersive = false

    init(controller: UIViewController, workspace: UIStackView, stage: UIView, details: UIView,
         extraAction: UIAction? = nil, onScalingChange: @escaping (Bool) -> Void,
         onImmersionChange: @escaping (Bool) -> Void) {
        self.controller = controller
        self.workspace = workspace
        self.stage = stage
        self.details = details
        self.onScalingChange = onScalingChange
        self.onImmersionChange = onImmersionChange
        let view = controller.view!
        let safe = view.safeAreaLayoutGuide
        workspace.axis = .vertical
        workspace.spacing = 10
        workspace.translatesAutoresizingMaskIntoConstraints = false
        workspace.addArrangedSubview(stage)
        workspace.addArrangedSubview(details)
        view.addSubview(workspace)
        inline = [
            workspace.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            workspace.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            workspace.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            workspace.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8)
        ]
        edgeToEdge = [
            workspace.topAnchor.constraint(equalTo: view.topAnchor),
            workspace.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            workspace.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            workspace.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        sidePanel = [
            details.widthAnchor.constraint(equalToConstant: 240),
            stage.heightAnchor.constraint(equalTo: workspace.heightAnchor)
        ]
        NSLayoutConstraint.activate(inline)

        configure(back, image: "chevron.backward", label: "Back to examples")
        back.addAction(UIAction { [weak controller] _ in
            controller?.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)
        configure(fit, image: "arrow.up.left.and.arrow.down.right", label: "Fill screen")
        fit.addAction(UIAction { [weak self] _ in self?.toggleScaling() }, for: .touchUpInside)
        let collapse = UIButton(type: .system)
        configure(collapse, image: "rectangle.split.2x1", label: "Show playback details")
        collapse.addAction(UIAction { [weak self] _ in self?.setShowsDetails(true) }, for: .touchUpInside)
        let immerse = UIButton(type: .system)
        configure(immerse, image: "eye.slash", label: "Immersive playback")
        immerse.addAction(UIAction { [weak self] _ in self?.setImmersive(true) }, for: .touchUpInside)
        expand.primaryAction = UIAction { [weak self] _ in self?.setShowsDetails(false) }
        expand.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        expand.accessibilityLabel = "Enter full screen"

        if let extraAction {
            let extra = UIButton(type: .system, primaryAction: extraAction)
            configure(extra, image: "playpause.fill", label: extraAction.title)
            actions.addArrangedSubview(extra)
        }
        actions.addArrangedSubview(fit)
        actions.addArrangedSubview(immerse)
        actions.addArrangedSubview(collapse)
        actions.spacing = 8
        back.isHidden = true
        actions.isHidden = true
        actions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        view.addSubview(actions)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            back.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            actions.topAnchor.constraint(equalTo: back.topAnchor)
        ])
    }

    func update() {
        guard let controller, let view = controller.viewIfLoaded else { return }
        let size = view.bounds.size
        let landscape = size.height > 0 && size.width > size.height
        if landscape != wasLandscape {
            wasLandscape = landscape
            showsDetails = false
        }
        let fullscreen = landscape && !showsDetails
        if fullscreen != isFullscreen {
            isFullscreen = fullscreen
            if !fullscreen { setImmersive(false) }
            NSLayoutConstraint.deactivate(fullscreen ? inline : edgeToEdge)
            NSLayoutConstraint.activate(fullscreen ? edgeToEdge : inline)
            details.isHidden = fullscreen
            stage.layer.cornerRadius = fullscreen ? 0 : 20
            stage.layer.borderWidth = fullscreen ? 0 : 1
            back.isHidden = !fullscreen
            actions.isHidden = !fullscreen
            onScalingChange(fullscreen && fillsScreen)
            controller.setNeedsStatusBarAppearanceUpdate()
        }
        let sideBySide = !fullscreen && landscape && view.safeAreaLayoutGuide.layoutFrame.width >= 590
        let axis: NSLayoutConstraint.Axis = sideBySide ? .horizontal : .vertical
        if workspace.axis != axis {
            NSLayoutConstraint.deactivate(sidePanel)
            workspace.axis = axis
            workspace.alignment = sideBySide ? .top : .fill
            if sideBySide { NSLayoutConstraint.activate(sidePanel) }
        }

        if let navigation = controller.navigationController, navigation.topViewController === controller {
            if navigation.isNavigationBarHidden != fullscreen {
                navigation.setNavigationBarHidden(fullscreen, animated: false)
            }
            let buttons = controller.navigationItem.rightBarButtonItems ?? []
            let containsExpand = buttons.contains { $0 === expand }
            if containsExpand != (landscape && !fullscreen) {
                controller.navigationItem.rightBarButtonItems = containsExpand
                    ? buttons.filter { $0 !== expand } : [expand] + buttons
            }
        }
    }

    @discardableResult
    func exitImmersive() -> Bool {
        guard isImmersive else { return false }
        setImmersive(false)
        return true
    }

    private func setImmersive(_ value: Bool) {
        guard value != isImmersive else { return }
        isImmersive = value
        back.isHidden = value || !isFullscreen
        actions.isHidden = value || !isFullscreen
        onImmersionChange(value)
        if value {
            UIAccessibility.post(notification: .announcement, argument: "Immersive playback. Use Escape to restore controls.")
        }
    }

    private func setShowsDetails(_ value: Bool) {
        showsDetails = value
        update()
    }

    private func toggleScaling() {
        fillsScreen.toggle()
        fit.configuration?.image = UIImage(systemName: fillsScreen
            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        fit.accessibilityLabel = fillsScreen ? "Fit entire video" : "Fill screen"
        onScalingChange(fillsScreen)
    }

    private func configure(_ button: UIButton, image: String, label: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: image)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .black.withAlphaComponent(0.7)
        configuration.baseForegroundColor = .white
        button.configuration = configuration
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
