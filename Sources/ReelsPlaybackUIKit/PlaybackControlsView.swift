#if canImport(UIKit)
#if SWIFT_PACKAGE
import ReelsPlaybackCore
#endif
import UIKit

/// Optional default controls. Hosts can build their own from PlaybackSession snapshots.
@MainActor
public final class PlaybackControlsView: UIView {
    private let session: PlaybackSession
    private let playPause = UIButton(type: .system)
    private let speed = UIButton(type: .system)
    private let time = UILabel()
    private let slider = UISlider()
    private let buffered = UIProgressView(progressViewStyle: .default)
    private var events: Task<Void, Never>?

    public init(session: PlaybackSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.62)
        tintColor = .white
        layer.cornerRadius = 10

        time.textColor = .white
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.adjustsFontSizeToFitWidth = true
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.accessibilityLabel = String(localized: "Playback position")
        speed.accessibilityLabel = String(localized: "Playback speed")
        speed.showsMenuAsPrimaryAction = true
        speed.menu = UIMenu(children: session.configuration.rates.map { rate in
            UIAction(title: Self.rateText(rate)) { [weak session] _ in session?.setRate(rate) }
        })
        playPause.addAction(UIAction { [weak session] _ in session?.togglePlayback() }, for: .touchUpInside)

        slider.addAction(UIAction { [weak session] _ in session?.beginScrubbing() }, for: .touchDown)
        slider.addAction(UIAction { [weak self] _ in
            guard let self, let duration = session.snapshot.duration else { return }
            let position = Double(slider.value) * duration
            if session.snapshot.isScrubbing { session.previewScrub(to: position) }
            else { session.seek(to: position) }
        }, for: .valueChanged)
        slider.addAction(UIAction { [weak session] _ in session?.endScrubbing() },
                         for: [.touchUpInside, .touchUpOutside])
        slider.addAction(UIAction { [weak session] _ in session?.endScrubbing(commit: false) }, for: .touchCancel)

        let row = UIStackView(arrangedSubviews: [playPause, time, UIView(), speed])
        row.alignment = .center
        row.spacing = 8
        let stack = UIStackView(arrangedSubviews: [row, slider, buffered])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            playPause.widthAnchor.constraint(equalToConstant: 44),
            playPause.heightAnchor.constraint(equalToConstant: 44),
            speed.heightAnchor.constraint(equalToConstant: 44)
        ])
        apply(session.snapshot)
        let stream = session.events()
        events = Task { [weak self] in
            for await event in stream {
                if case .snapshot(let snapshot) = event { self?.apply(snapshot) }
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    private func apply(_ snapshot: PlaybackSnapshot) {
        let pauses = snapshot.wantsPlayback && snapshot.state != .ended
        if case .failed = snapshot.state {
            playPause.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
            playPause.accessibilityLabel = String(localized: "Retry")
        } else {
            playPause.setImage(UIImage(systemName: pauses ? "pause.fill" : "play.fill"), for: .normal)
            playPause.accessibilityLabel = pauses ? String(localized: "Pause") : String(localized: "Play")
        }
        playPause.isEnabled = snapshot.itemID != nil && snapshot.state != .accessRequired
        speed.setTitle(Self.rateText(snapshot.rate), for: .normal)
        time.text = "\(Self.timeText(snapshot.position)) / \(snapshot.duration.map(Self.timeText) ?? "–:–")"
        if let duration = snapshot.duration, duration > 0 {
            slider.isEnabled = true
            if !slider.isTracking { slider.value = Float(min(1, max(0, snapshot.position / duration))) }
            buffered.progress = Float(min(1, max(0, snapshot.bufferedUntil / duration)))
        } else {
            slider.isEnabled = false
            slider.value = 0
            buffered.progress = 0
        }
    }

    private static func rateText(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        let value = Int(min(max(0, seconds.isFinite ? seconds : 0), 86_400 * 365))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    deinit { events?.cancel() }
}
#endif
