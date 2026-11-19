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
- Track poster requests independently of video startup, cancel stale work, and show a fallback when artwork is unavailable.
- Refresh the demo with grouped scenarios, an artwork-led home screen, and an adaptive playback inspector.

### Drama collection, full screen, and offline downloads

- Add a 12-episode offline demo using excerpts from three open films, each with its own poster. The feed supports episode selection, auto-advance, and resuming the last episode and position.
- Use film excerpts in the playback labs, including a widescreen clip with its original audio. Remote playback offers Tears of Steel on Mux HLS and the Sintel trailer as an HTTPS MP4. [Media credits and licenses](Demo/Media/Series/ATTRIBUTION.md)
- Enter full screen automatically in landscape and choose between fitting and filling the screen. Immersive mode shows only the progress bar. Tapping the video restores controls without toggling playback.
- Clear temporary prefetch files from the cache lab. The opt-in `PlaybackDownloadStore` manages persistent HTTPS MP4 downloads and deletion separately. The HLS example remains available for streaming.
- Keep the `0.1.1` package imports, initializer signatures, and default UIKit behavior. Existing integrations can opt in to `showsProgressOnly`, `onVideoTap`, and the download store. [Chinese integration guide](Docs/Quickstart.zh-CN.md)

## 0.1.1

- Show a centered loading indicator over the poster while the selected video prepares or buffers before its first frame in single-video and vertical-feed views.
- Allow custom UIKit layouts to opt into the indicator by passing the current session snapshot to `PlaybackVideoView.display(_:presentation:snapshot:)`.

## 0.1.0

- Published the Core and UIKit products through Swift Package Manager and CocoaPods.
- Added single-video and vertical-feed playback, shared focus, built-in controls, and host-driven access and cache interfaces.
- Included an offline UIKit demo, integration examples, and core regression tests.
