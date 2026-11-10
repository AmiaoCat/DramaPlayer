#if canImport(UIKit)
import AVFoundation
#if SWIFT_PACKAGE
import ReelsPlaybackCore
#endif
import UIKit

/// Retain alongside the session. Screen visibility remains controlled by activate/deactivate.
@MainActor
public final class PlaybackLifecycle {
    private var observers: [NSObjectProtocol] = []

    public init(session: PlaybackSession) {
        let center = NotificationCenter.default
        session.setSuspended(UIApplication.shared.applicationState != .active, reason: .background)
        observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) {
                [weak session] _ in
                Task { @MainActor in session?.setSuspended(true, reason: .background) }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak session] _ in
                Task { @MainActor in session?.setSuspended(false, reason: .background) }
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) {
                [weak session] _ in
                Task { @MainActor in session?.discardInactiveItems() }
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
                [weak session] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                Task { @MainActor in
                    switch type {
                    case .began: session?.setSuspended(true, reason: .interruption)
                    case .ended:
                        if !shouldResume { session?.pause() }
                        session?.setSuspended(false, reason: .interruption)
                    @unknown default: break
                    }
                }
            }
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
#endif
