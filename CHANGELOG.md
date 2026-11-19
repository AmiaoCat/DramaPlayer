# Changelog

## Unreleased

- Add a typed diagnostics stream for startup, first frame, rebuffering, cache fallback, and playback outcome.
- Support changing stream preferences and proactive preload policy without replacing the active player.
- Expose native audio and subtitle track discovery and selection for the active media item.
- Route AVFoundation playback-to-end failures through the existing cache fallback and error handling.
- Expand the UIKit demo with episode access, cache comparison, custom playback controls, and a remote HLS sample.
- Add fit and fill scaling for video and posters, keep the selected feed page during resizing, and include an offline landscape demo.
- Add 12 viewport templates and a draggable in-app mini player with custom width and height.
- Add opt-in structured logging, a per-load deadline, and a production configuration reference.
- Add custom media prefetch candidates and live ahead/behind controls in the cache demo.
- Add opt-in landscape swipes for display brightness and session audio level.
- Preserve the 0.1.1 imports, initializer signatures and default UIKit scaling. Hosts opt in to fit, load deadlines and logging. The demo opts in to these features for testing.

## 0.1.1

- Show a centered loading indicator over the poster while the selected video prepares or buffers before its first frame in single-video and vertical-feed views.
- Allow custom UIKit layouts to opt into the indicator by passing the current session snapshot to `PlaybackVideoView.display(_:presentation:snapshot:)`.

## 0.1.0

- Published the Core and UIKit products through Swift Package Manager and CocoaPods.
- Added single-video and vertical-feed playback, shared focus, built-in controls, and host-driven access and cache interfaces.
- Included an offline UIKit demo, integration examples, and core regression tests.
