#if canImport(UIKit)
import AVFoundation
#if SWIFT_PACKAGE
import ReelsPlaybackCore
#endif
import UIKit

@MainActor
public protocol PlaybackCoverLoader {
    func image(for url: URL) async -> UIImage?
}

public struct URLPlaybackCoverLoader: PlaybackCoverLoader {
    public nonisolated init() {}

    public func image(for url: URL) async -> UIImage? {
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            return nil
        }
        return UIImage(data: data)
    }
}

/// The poster request lifecycle, independent of video preparation and playback.
public enum PlaybackCoverState: Equatable, Sendable {
    case noCover, idle, loading, loaded, failed
}

@MainActor
public final class PlaybackVideoView: UIView {
    public private(set) var coverState: PlaybackCoverState = .noCover {
        didSet {
            if coverState != oldValue { onCoverStateChange?(coverState) }
        }
    }

    public var onCoverStateChange: ((PlaybackCoverState) -> Void)?

    /// Adjusts both the poster and the video without changing the active player.
    public var scaling: PlaybackVideoScaling {
        didSet {
            guard scaling != oldValue else { return }
            cover.contentMode = scaling.coverContentMode
            if let playbackLayer, playbackLayer.superlayer === layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playbackLayer.videoGravity = scaling.videoGravity
                CATransaction.commit()
            }
        }
    }

    private let poster = UIView()
    private let cover = UIImageView()
    private let placeholder = UIImageView(image: UIImage(systemName: "film"))
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let loader: any PlaybackCoverLoader
    private var coverWork: Task<Void, Never>?
    private var coverURL: URL?
    private var itemID: String?
    private var playbackLayer: AVPlayerLayer?
    private var hasRevealed = false
    private var isWaitingForVideo = false

    public convenience init(coverLoader: any PlaybackCoverLoader) {
        self.init(coverLoader: coverLoader, scaling: .fill)
    }

    public init(coverLoader: any PlaybackCoverLoader = URLPlaybackCoverLoader(), scaling: PlaybackVideoScaling = .fill) {
        loader = coverLoader
        self.scaling = scaling
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        poster.backgroundColor = .black
        poster.isUserInteractionEnabled = false
        poster.isAccessibilityElement = false
        poster.frame = bounds
        poster.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(poster)
        cover.frame = poster.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.contentMode = scaling.coverContentMode
        cover.clipsToBounds = true
        cover.isAccessibilityElement = false
        poster.addSubview(cover)
        placeholder.tintColor = UIColor.white.withAlphaComponent(0.35)
        placeholder.contentMode = .scaleAspectFit
        placeholder.isAccessibilityElement = false
        placeholder.isHidden = true
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        poster.addSubview(placeholder)
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.isUserInteractionEnabled = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            placeholder.widthAnchor.constraint(equalToConstant: 36),
            placeholder.heightAnchor.constraint(equalTo: placeholder.widthAnchor),
            placeholder.centerXAnchor.constraint(equalTo: poster.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: poster.centerYAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if playbackLayer?.superlayer === layer { playbackLayer?.frame = bounds }
        CATransaction.commit()
    }

    public func display(_ item: PlaybackItem?, presentation: PlaybackPresentation?) {
        display(item, presentation: presentation, snapshot: nil)
    }

    /// Pass the session snapshot to show video loading while the active item waits for its first frame.
    public func display(_ item: PlaybackItem?, presentation: PlaybackPresentation?, snapshot: PlaybackSnapshot?) {
        let changedItem = itemID != item?.id
        let changedCover = changedItem || coverURL != item?.coverURL
        itemID = item?.id
        if changedCover {
            cancelCoverLoad()
            coverURL = item?.coverURL
            cover.image = nil
        }

        let nextLayer = presentation?.layer
        let changedLayer = playbackLayer !== nextLayer || (nextLayer != nil && nextLayer?.superlayer !== layer)
        if changedItem || changedLayer {
            if playbackLayer?.superlayer === layer { playbackLayer?.removeFromSuperlayer() }
            playbackLayer = nextLayer
            if let nextLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                nextLayer.videoGravity = scaling.videoGravity
                nextLayer.frame = bounds
                layer.insertSublayer(nextLayer, below: poster.layer)
                CATransaction.commit()
            }
            hasRevealed = presentation?.firstFrameReady == true
            poster.layer.removeAllAnimations()
            poster.alpha = hasRevealed ? 0 : 1
        } else if presentation?.firstFrameReady == true, !hasRevealed {
            hasRevealed = true
            if UIAccessibility.isReduceMotionEnabled {
                poster.alpha = 0
            } else {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.poster.alpha = 0
                }
            }
        }

        isWaitingForVideo = item != nil && snapshot?.itemID == item?.id
            && snapshot?.wantsPlayback == true
            && (snapshot?.state == .preparing || snapshot?.state == .buffering)
        if changedCover {
            coverState = coverURL == nil ? .noCover : .idle
        }
        if hasRevealed, coverState == .loading {
            cancelCoverLoad()
            coverState = .idle
        }
        loadCoverIfNeeded()
        updateLoadingUI()
    }

    /// Retries a failed poster request while the poster is visible.
    public func retryCoverLoading() {
        guard !hasRevealed, coverState == .failed else { return }
        coverState = .idle
        loadCoverIfNeeded()
    }

    private func cancelCoverLoad() {
        coverWork?.cancel()
        coverWork = nil
    }

    private func loadCoverIfNeeded() {
        guard !hasRevealed, coverState == .idle, let url = coverURL else { return }
        coverWork = Task { [weak self, loader] in
            guard !Task.isCancelled else { return }
            let image = await loader.image(for: url)
            guard let self, !Task.isCancelled, coverURL == url, !hasRevealed else { return }
            coverWork = nil
            cover.image = image
            coverState = image == nil ? .failed : .loaded
            updateLoadingUI()
        }
        coverState = .loading
        updateLoadingUI()
    }

    private func updateLoadingUI() {
        let showLoading = !hasRevealed && (isWaitingForVideo || coverState == .loading)
        placeholder.isHidden = itemID == nil || cover.image != nil || showLoading
        if showLoading {
            loadingIndicator.accessibilityLabel = isWaitingForVideo
                ? String(localized: "Loading video") : String(localized: "Loading cover")
            if !loadingIndicator.isAnimating { loadingIndicator.startAnimating() }
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    deinit { coverWork?.cancel() }
}

public enum PlaybackVideoScaling: Equatable, Sendable {
    /// Preserve the entire image with letterboxing as needed.
    case fit
    /// Fill the viewport, cropping the edges as needed.
    case fill

    fileprivate var videoGravity: AVLayerVideoGravity { self == .fit ? .resizeAspect : .resizeAspectFill }
    fileprivate var coverContentMode: UIView.ContentMode { self == .fit ? .scaleAspectFit : .scaleAspectFill }
}
#endif
