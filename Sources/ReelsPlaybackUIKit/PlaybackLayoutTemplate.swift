#if canImport(UIKit)
import UIKit

/// An aspect ratio and scaling policy for a host-owned playback viewport.
public struct PlaybackLayoutTemplate: Equatable, Sendable {
    public enum Aspect: String, CaseIterable, Sendable {
        case portrait = "9:16"
        case portraitStandard = "3:4"
        case square = "1:1"
        case standard = "4:3"
        case widescreen = "16:9"
        case ultrawide = "21:9"

        public var ratio: CGFloat {
            switch self {
            case .portrait: 9.0 / 16
            case .portraitStandard: 3.0 / 4
            case .square: 1
            case .standard: 4.0 / 3
            case .widescreen: 16.0 / 9
            case .ultrawide: 21.0 / 9
            }
        }
    }

    public let aspect: Aspect
    public let scaling: PlaybackVideoScaling

    public init(aspect: Aspect, scaling: PlaybackVideoScaling) {
        self.aspect = aspect
        self.scaling = scaling
    }

    public static let presets = Aspect.allCases.flatMap { aspect in
        [Self(aspect: aspect, scaling: .fit), Self(aspect: aspect, scaling: .fill)]
    }

    public func fittedSize(in availableSize: CGSize) -> CGSize {
        guard availableSize.width.isFinite, availableSize.height.isFinite,
              availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let height = min(availableSize.height, availableSize.width / aspect.ratio)
        return CGSize(width: height * aspect.ratio, height: height)
    }
}
#endif
