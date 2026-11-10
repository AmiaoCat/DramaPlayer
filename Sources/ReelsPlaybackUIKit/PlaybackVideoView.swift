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

@MainActor
public final class PlaybackVideoView: UIView {
    private let cover = UIImageView()
    private let loader: any PlaybackCoverLoader
    private var coverWork: Task<Void, Never>?
    private var coverURL: URL?
    private var itemID: String?
    private var playbackLayer: AVPlayerLayer?
    private var hasRevealed = false

    public init(coverLoader: any PlaybackCoverLoader = URLPlaybackCoverLoader()) {
        loader = coverLoader
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.isAccessibilityElement = false
        addSubview(cover)
    }

    required init?(coder: NSCoder) { nil }

    public override func layoutSubviews() {
        super.layoutSubviews()
        cover.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if playbackLayer?.superlayer === layer { playbackLayer?.frame = bounds }
        CATransaction.commit()
    }

    public func display(_ item: PlaybackItem?, presentation: PlaybackPresentation?) {
        let changedItem = itemID != item?.id
        itemID = item?.id
        if changedItem || coverURL != item?.coverURL {
            updateCover(url: item?.coverURL)
        }

        let nextLayer = presentation?.layer
        let changedLayer = playbackLayer !== nextLayer || (nextLayer != nil && nextLayer?.superlayer !== layer)
        if changedItem || changedLayer {
            if playbackLayer?.superlayer === layer { playbackLayer?.removeFromSuperlayer() }
            playbackLayer = nextLayer
            if let nextLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                nextLayer.frame = bounds
                layer.insertSublayer(nextLayer, below: cover.layer)
                CATransaction.commit()
            }
            hasRevealed = presentation?.firstFrameReady == true
            cover.layer.removeAllAnimations()
            cover.alpha = hasRevealed ? 0 : 1
        } else if presentation?.firstFrameReady == true, !hasRevealed {
            hasRevealed = true
            if UIAccessibility.isReduceMotionEnabled {
                cover.alpha = 0
            } else {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.cover.alpha = 0
                }
            }
        }
    }

    private func updateCover(url: URL?) {
        coverWork?.cancel()
        if coverURL != url { cover.image = nil }
        coverURL = url
        guard let url, cover.image == nil else { return }
        coverWork = Task { [weak self, loader] in
            let image = await loader.image(for: url)
            guard let self, !Task.isCancelled, self.coverURL == url else { return }
            self.cover.image = image
        }
    }

    deinit { coverWork?.cancel() }
}
#endif
