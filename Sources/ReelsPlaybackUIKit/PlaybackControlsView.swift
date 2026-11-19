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
    private let standard = UIStackView()
    private let progress = UIProgressView(progressViewStyle: .default)
    private var standardLayout: [NSLayoutConstraint] = []
    private var progressLayout: [NSLayoutConstraint] = []
    private var events: Task<Void, Never>?

    /// Show a thin, read-only playhead indicator in place of the interactive controls.
    public var showsProgressOnly = false {
        didSet {
            guard showsProgressOnly != oldValue else { return }
            if showsProgressOnly, session.snapshot.isScrubbing { session.endScrubbing(commit: false) }
            NSLayoutConstraint.deactivate(showsProgressOnly ? standardLayout : progressLayout)
            standard.isHidden = showsProgressOnly
            progress.isHidden = !showsProgressOnly
            backgroundColor = showsProgressOnly ? .clear : UIColor.black.withAlphaComponent(0.62)
            NSLayoutConstraint.activate(showsProgressOnly ? progressLayout : standardLayout)
        }
    }

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
        [row, slider, buffered].forEach { standard.addArrangedSubview($0) }
        standard.axis = .vertical
        standard.spacing = 2
        standard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(standard)
        progress.progressTintColor = .white
        progress.trackTintColor = UIColor.black.withAlphaComponent(0.65)
        progress.accessibilityLabel = String(localized: "Playback progress")
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progress)
        standardLayout = [
            standard.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            standard.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            standard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            standard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ]
        progressLayout = [
            progress.topAnchor.constraint(equalTo: topAnchor),
            progress.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor)
        ]
        NSLayoutConstraint.activate(standardLayout)
        NSLayoutConstraint.activate([
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
            let fraction = Float(min(1, max(0, snapshot.position / duration)))
            slider.isEnabled = true
            if !slider.isTracking { slider.value = fraction }
            progress.progress = fraction
            buffered.progress = Float(min(1, max(0, snapshot.bufferedUntil / duration)))
        } else {
            slider.isEnabled = false
            slider.value = 0
            progress.progress = 0
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
