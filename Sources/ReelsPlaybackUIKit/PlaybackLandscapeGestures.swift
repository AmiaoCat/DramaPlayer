#if canImport(UIKit)
#if SWIFT_PACKAGE
import ReelsPlaybackCore
#endif
import UIKit

/// Vertical brightness and playback-volume swipes on a wide playback surface.
@MainActor
public final class PlaybackLandscapeGestures: NSObject, UIGestureRecognizerDelegate {
    public var isEnabled: Bool {
        get { recognizer.isEnabled }
        set {
            recognizer.isEnabled = newValue
            if !newValue { hideIndicator() }
        }
    }

    let recognizer = UIPanGestureRecognizer()
    private let session: PlaybackSession
    private let pagingZone: CGFloat
    private let indicator = UIStackView()
    private let icon = UIImageView()
    private let valueLabel = UILabel()
    private var adjustment: Adjustment?
    private var hideTask: Task<Void, Never>?

    private enum Target {
        case brightness, volume

        var symbol: String { self == .brightness ? "sun.max.fill" : "speaker.wave.2.fill" }
    }

    private struct Adjustment {
        let target: Target
        let start: CGFloat
        let travel: CGFloat
    }

    /// Retain this object while the surface should accept gestures.
    public convenience init(session: PlaybackSession, surface: UIView) {
        self.init(session: session, surface: surface, reservesCenterForPaging: false)
    }

    init(session: PlaybackSession, surface: UIView, reservesCenterForPaging: Bool, indicatorHost: UIView? = nil) {
        self.session = session
        pagingZone = reservesCenterForPaging ? 0.2 : 0
        super.init()
        recognizer.addTarget(self, action: #selector(adjust(_:)))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1
        surface.addGestureRecognizer(recognizer)
        installIndicator(on: indicatorHost ?? surface)
    }

    /// Detaches the gesture and its indicator from a host-managed surface.
    public func invalidate() {
        isEnabled = false
        recognizer.view?.removeGestureRecognizer(recognizer)
        indicator.removeFromSuperview()
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let surface = gestureRecognizer.view, isLandscape(surface) else { return false }
        let velocity = recognizer.velocity(in: surface)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        let fraction = (recognizer.location(in: surface).x - recognizer.translation(in: surface).x
                        - surface.bounds.minX) / surface.bounds.width
        guard abs(fraction - 0.5) >= pagingZone / 2 else { return false }
        return fraction >= 0.5 || brightnessScreen(for: surface) != nil
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view {
            if candidate is UIControl { return false }
            if candidate === gestureRecognizer.view { break }
            view = candidate.superview
        }
        return true
    }

    @objc private func adjust(_ pan: UIPanGestureRecognizer) {
        guard let surface = pan.view, isLandscape(surface) else {
            hideIndicator()
            return
        }
        let translation = pan.translation(in: surface)
        switch pan.state {
        case .began:
            let startX = pan.location(in: surface).x - translation.x
            let target: Target = startX < surface.bounds.midX ? .brightness : .volume
            let start: CGFloat
            if target == .brightness {
                guard let screen = brightnessScreen(for: surface) else { return }
                start = screen.brightness
            } else {
                start = CGFloat(session.volume)
            }
            adjustment = Adjustment(target: target, start: start, travel: max(120, surface.bounds.height * 0.75))
            hideTask?.cancel()
            fallthrough
        case .changed, .ended:
            guard let adjustment else { return }
            let value = min(1, max(0, adjustment.start - translation.y / adjustment.travel))
            switch adjustment.target {
            case .brightness: brightnessScreen(for: surface)?.brightness = value
            case .volume: session.setVolume(Float(value))
            }
            icon.image = UIImage(systemName: adjustment.target.symbol)
            valueLabel.text = Double(value).formatted(.percent.precision(.fractionLength(0)))
            indicator.isHidden = false
            if pan.state == .ended { finishAdjustment() }
        case .cancelled, .failed:
            finishAdjustment()
        default:
            break
        }
    }

    private func isLandscape(_ surface: UIView) -> Bool {
        guard let window = surface.window else { return false }
        return window.bounds.width > window.bounds.height && surface.bounds.width > surface.bounds.height
    }

    private func brightnessScreen(for surface: UIView) -> UIScreen? {
        guard let scene = surface.window?.windowScene, scene.session.role == .windowApplication else { return nil }
        return scene.screen
    }

    private func finishAdjustment() {
        adjustment = nil
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) }
            catch { return }
            self?.hideIndicator()
        }
    }

    private func hideIndicator() {
        adjustment = nil
        hideTask?.cancel()
        hideTask = nil
        indicator.isHidden = true
    }

    private func installIndicator(on surface: UIView) {
        indicator.isUserInteractionEnabled = false
        indicator.accessibilityElementsHidden = true
        indicator.isHidden = true
        indicator.axis = .horizontal
        indicator.alignment = .center
        indicator.spacing = 8
        indicator.isLayoutMarginsRelativeArrangement = true
        indicator.directionalLayoutMargins = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        indicator.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        indicator.layer.cornerRadius = 12
        icon.tintColor = .white
        valueLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        indicator.addArrangedSubview(icon)
        indicator.addArrangedSubview(valueLabel)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    deinit { hideTask?.cancel() }
}
#endif
