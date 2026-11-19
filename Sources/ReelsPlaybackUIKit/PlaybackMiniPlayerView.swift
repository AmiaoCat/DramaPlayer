#if canImport(UIKit)
import UIKit

/// An in-app floating container. The host can move its existing player view into `contentView`.
@MainActor
public final class PlaybackMiniPlayerView: UIView {
    public let contentView = UIView()
    public var onExpand: (() -> Void)?
    public var onSizeChanged: ((CGSize) -> Void)?
    public private(set) var preferredSize: CGSize

    private let moveHandle = UIView()
    private let resizeHandle = UIView()
    private var availableFrame = CGRect.zero
    private var anchor = CGPoint(x: 0, y: 1)
    private var gestureStartFrame = CGRect.zero

    public init(preferredSize: CGSize = CGSize(width: 240, height: 180)) {
        self.preferredSize = Self.valid(preferredSize) ? preferredSize : CGSize(width: 240, height: 180)
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1
        clipsToBounds = true
        accessibilityIdentifier = "playback-mini-player"
        installControls()
    }

    required init?(coder: NSCoder) { nil }

    /// Sets a custom total window size in points. The visible frame is clamped to its container.
    public func setPreferredSize(_ size: CGSize) {
        guard Self.valid(size) else { return }
        preferredSize = size
        updateFrame()
    }

    /// Supply the safe area in the coordinate space of this view's superview on each layout pass.
    public func layout(in availableFrame: CGRect) {
        guard availableFrame.origin.x.isFinite, availableFrame.origin.y.isFinite,
              Self.valid(availableFrame.size) else { return }
        self.availableFrame = availableFrame
        updateFrame()
    }

    private func installControls() {
        moveHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveWindow(_:))))
        let handleIcon = makeIcon("line.3.horizontal", in: moveHandle)
        handleIcon.tintColor = .secondaryLabel

        let expand = UIButton(type: .system)
        expand.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expand.accessibilityLabel = String(localized: "Expand player")
        expand.addAction(UIAction { [weak self] _ in self?.onExpand?() }, for: .touchUpInside)

        contentView.backgroundColor = .black
        contentView.clipsToBounds = true
        resizeHandle.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        resizeHandle.layer.cornerRadius = 8
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeWindow(_:))))
        resizeHandle.isAccessibilityElement = true
        resizeHandle.accessibilityLabel = String(localized: "Resize player")
        resizeHandle.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: String(localized: "Make larger")) { [weak self] _ in
                self?.adjustSize(by: 24) ?? false
            },
            UIAccessibilityCustomAction(name: String(localized: "Make smaller")) { [weak self] _ in
                self?.adjustSize(by: -24) ?? false
            }
        ]
        makeIcon("arrow.down.right", in: resizeHandle).tintColor = .white

        for child in [contentView, moveHandle, expand, resizeHandle] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        let preferredHeaderHeight = moveHandle.heightAnchor.constraint(equalToConstant: 44)
        preferredHeaderHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            moveHandle.topAnchor.constraint(equalTo: topAnchor),
            moveHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            moveHandle.trailingAnchor.constraint(equalTo: expand.leadingAnchor),
            moveHandle.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            preferredHeaderHeight,
            expand.topAnchor.constraint(equalTo: topAnchor),
            expand.trailingAnchor.constraint(equalTo: trailingAnchor),
            expand.widthAnchor.constraint(equalToConstant: 44),
            expand.heightAnchor.constraint(equalTo: moveHandle.heightAnchor),
            contentView.topAnchor.constraint(equalTo: moveHandle.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 44),
            resizeHandle.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeIcon(_ name: String, in container: UIView) -> UIImageView {
        let icon = UIImageView(image: UIImage(systemName: name))
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return icon
    }

    private func adjustSize(by delta: CGFloat) -> Bool {
        guard Self.valid(availableFrame.size) else { return false }
        let previous = bounds.size
        setPreferredSize(clampedSize(CGSize(width: previous.width + delta, height: previous.height + delta)))
        return previous != bounds.size
    }

    private func clampedSize(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(152, size.width), availableFrame.width),
               height: min(max(112, size.height), availableFrame.height))
    }

    private func updateFrame() {
        guard Self.valid(availableFrame.size) else { return }
        let size = clampedSize(preferredSize)
        let origin = CGPoint(x: availableFrame.minX + anchor.x * (availableFrame.width - size.width),
                             y: availableFrame.minY + anchor.y * (availableFrame.height - size.height))
        let oldSize = bounds.size
        frame = CGRect(origin: origin, size: size)
        resizeHandle.accessibilityValue = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
        if oldSize != size { onSizeChanged?(size) }
    }

    private func setAnchor(for origin: CGPoint, size: CGSize) {
        let horizontalTravel = availableFrame.width - size.width
        let verticalTravel = availableFrame.height - size.height
        if horizontalTravel > 0 {
            anchor.x = min(1, max(0, (origin.x - availableFrame.minX) / horizontalTravel))
        }
        if verticalTravel > 0 {
            anchor.y = min(1, max(0, (origin.y - availableFrame.minY) / verticalTravel))
        }
    }

    @objc private func moveWindow(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        if gesture.state == .began { gestureStartFrame = frame }
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let delta = gesture.translation(in: superview)
        setAnchor(for: CGPoint(x: gestureStartFrame.minX + delta.x, y: gestureStartFrame.minY + delta.y),
                  size: frame.size)
        updateFrame()
    }

    @objc private func resizeWindow(_ gesture: UIPanGestureRecognizer) {
        guard let superview, Self.valid(availableFrame.size) else { return }
        if gesture.state == .began { gestureStartFrame = frame }
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let delta = gesture.translation(in: superview)
        let size = clampedSize(CGSize(width: gestureStartFrame.width + delta.x,
                                     height: gestureStartFrame.height + delta.y))
        setAnchor(for: gestureStartFrame.origin, size: size)
        setPreferredSize(size)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
#endif
