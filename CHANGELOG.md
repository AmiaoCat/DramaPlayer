# Changelog

## 0.1.1

- Show a centered loading indicator over the poster while the selected video prepares or buffers before its first frame in single-video and vertical-feed views.
- Allow custom UIKit layouts to opt into the indicator by passing the current session snapshot to `PlaybackVideoView.display(_:presentation:snapshot:)`.

## 0.1.0

- Published the Core and UIKit products through Swift Package Manager and CocoaPods.
- Added single-video and vertical-feed playback, shared focus, built-in controls, and host-driven access and cache interfaces.
- Included an offline UIKit demo, integration examples, and core regression tests.
