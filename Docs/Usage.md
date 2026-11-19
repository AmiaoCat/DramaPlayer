# Integration guide

The examples use the public APIs of `ReelsPlaybackCore` and `ReelsPlaybackUIKit`. Import `DramaPlayer` when using CocoaPods. Create and operate sessions and UIKit views on the main actor. Providers and caches are `Sendable` and can use actors for shared state.

## Vertical feed

Give each item a stable, unique identifier. Keep the session and lifecycle adapter as properties of the host controller, pin the player to its video area, then activate and deactivate it with the same lifecycle hooks as the single-player example. Calling `setItems` again updates the feed; when possible, the current selection is retained.

```swift
@MainActor
func makeFeed(urls: [String: URL], orderedIDs: [String], initialID: String?)
    -> (PlaybackSession, VerticalPlaybackView, PlaybackLifecycle) {
    let resolver = PlaybackSourceResolver { item, _ in
        guard let url = urls[item.id] else { return .unavailable }
        return .allowed(.init(url: url, cacheKey: item.id))
    }
    let session = PlaybackSession(
        configuration: .init(mode: .vertical, preload: .preparedPlayer, endBehavior: .advance),
        sourceProvider: resolver
    )
    let feed = VerticalPlaybackView(session: session)
    let lifecycle = PlaybackLifecycle(session: session)
    session.setItems(orderedIDs.map { PlaybackItem(id: $0) }, selectedID: initialID)
    return (session, feed, lifecycle)
}
```

Use `session.select(id)` to jump to an episode. Use `setScrollingEnabled(false)` to disable paging while a host interaction requires it. For an existing collection view, call `PlaybackVideoView.display(_:presentation:snapshot:)` with `session.presentation(for: id)` and `session.snapshot` to show the loading indicator over the cover while the selected video prepares or buffers; mount a given presentation layer in only one view at a time.

## Controls and playback events

Set `showsControls: false` on either player view to hide its control bar and keep its tap-to-toggle behavior. Use `PlaybackVideoView` directly when the host owns gestures and controls. The [Custom controls demo](../Demo/Sources/DemoPlayerViewController.swift) binds the selected item and its presentation to this view, renders progress from snapshots, and updates its buttons from the playback state.

Use `play()`, `pause()`, `togglePlayback()`, `setRate(_:)`, and `seek(to:)` for direct controls. Choose a rate from `session.configuration.rates`. For an interactive scrubber, call `beginScrubbing()`, `previewScrub(to:)`, then `endScrubbing(commit:)` with `false` if the gesture was cancelled. Positions, duration and `bufferedUntil` are in seconds. The duration may be unavailable during preparation or for a stream without a finite duration. To resume across visits, save the position from a snapshot under the item's stable ID and pass it to `PlaybackItem(resumePosition:)` when building the next screen.

Retain the observation task as a screen property and cancel it in `deinit`. If the task calls back into the view controller, capture it weakly.

```swift
let observations = Task { @MainActor [weak session] in
    guard let stream = session?.events() else { return }
    for await event in stream {
        switch event {
        case .snapshot(let snapshot):
            renderProgress(snapshot.position, snapshot.duration, snapshot.bufferedUntil)
            renderState(snapshot.state, snapshot.firstFrameReady)
        case .ended(let id):
            recordCompletion(id)
        case .queueChanged, .presentationChanged:
            break
        }
    }
}
```

`renderProgress`, `renderState` and `recordCompletion` are callbacks supplied by the host. A new subscription emits a queue event and the current snapshot. Use `wantsPlayback` for play/pause intent and `state` for preparing, buffering, access, and failure UI. An `.ended(id)` event can also occur before a loop or an automatic advance, so use the ID carried by that event when recording completion. The default end behavior is `.stop`. Choose `.loop` for a clip or `.advance` for a sequence that stops at its last item.

## Focus, lifecycle, and access

Sessions share `PlaybackFocus.shared` by default. Use `activate()` when a screen becomes eligible to play and `deactivate()` when it loses visibility. `PlaybackLifecycle` coordinates backgrounding and audio interruptions on iOS. Configure the app's audio-session category in the host. Suspend playback under a host modal with `setSuspended(true, reason: .overlay)`, and clear the same reason after dismissal.

A resolver receives `.playback` or `.preload`. Return `.allowed(source)` for playable media, `.requiresUserAction` for an item the user must unlock, or `.unavailable` when no source exists. A preload request should only inspect entitlement and should be free of purchases or other side effects. On `.accessRequired`, the host can present its access UI and call `session.retry()` after entitlement changes. Call `invalidateSources()` when an account, entitlement, or quality setting changes. For expiring URLs, set `expiresAt` and resolve a fresh URL when the SDK asks again.

For an unlock flow, capture the episode ID before awaiting the host's entitlement update. Before calling `retry()`, confirm that the same episode is still selected and in `.accessRequired`. Invalidate all sources for broader changes that also affect retained items, such as signing out. The [Episode access demo](../Demo/Sources/DemoPlayerViewController.swift) uses an in-memory entitlement and follows this flow.

| Snapshot state | Host action |
| --- | --- |
| `.accessRequired` | Show your access UI. Retry the selected item after the grant succeeds. |
| `.failed(.sourceUnavailable)` | Check the episode-to-URL mapping or the source service, then retry. A thrown resolver error also maps to this state. |
| `.failed(.sourceExpired)` | Have the resolver obtain a fresh signed URL on retry. |
| `.failed(.playbackFailed)` | Offer retry and check whether the URL delivers media supported by AVFoundation. |

For a direct remote URL, pass the HTTPS MP4 or HLS playlist URL to `PlaybackSource` the same way you would pass a local file URL. Use the **Remote playback** demo to try it. Open the demo with a different URL when testing a replacement source. Signed URLs may contain credentials, so keep them out of display strings and telemetry.

## Preloading and cache integration

| Policy | Behavior |
| --- | --- |
| `.preparedPlayer` | Prepares adjacent authorized items. In vertical mode the bounded pool holds up to three player slots by default. A retained ready player can display without replaying the poster transition. |
| `.mediaBytes` | Hands prefetch of the next item to the injected `PlaybackMediaCache`. |
| `.disabled` | Disables proactive preloading. |

### Custom media prefetch

```swift
session.setMediaPrefetchPolicy(.init(offsets: [1, 2, -1]))
session.setPreloadPolicy(.mediaBytes)
```

Use signed offsets for nearby episodes or initialize the policy with a lightweight selector that returns episode IDs in priority order. The selector receives the queue and current index on the main actor. The SDK skips the current item, duplicates, and IDs outside the queue. It limits each plan to `maxCandidates` (3 by default, 0–8), resolves each candidate with `.preload`, and sends eligible sources to the cache sequentially. Candidates that fail access or prefetch are skipped. Apply a new policy when user or network preferences change. Changes cancel queued prefetch work and preserve playback. Passing `nil` restores next-episode prefetch. Cache eviction and storage limits remain controlled by the injected `PlaybackMediaCache`. Providers and caches should honor cancellation for in-progress work.

The [Cache policies demo](../Demo/Sources/DemoCacheViewController.swift) uses bundled MP4s to compare these policies offline. **Off** loads each episode on demand. **Players** lets you see a neighboring player attach in advance. **Media bytes** copies the next episode into a temporary file and reports a cache hit when you play it. Changing policies or pressing **Reset** starts a new session with an empty cache.

The default media cache plays the source URL directly. A disk cache, a streaming proxy, and offline downloads are supplied by the host. The following wraps a store you implement; `localURL(for:)` returns a completed readable local resource or nil.

```swift
let mediaCache = PlaybackCacheAdapter(
    resolve: { source in
        if let local = await store.localURL(for: source.cacheKey) {
            return PlaybackMedia(url: local, isCached: true)
        }
        return PlaybackMedia(url: source.url)
    },
    prefetch: { source in
        try await store.prefetch(source.url, key: source.cacheKey)
    },
    invalidate: { source in
        await store.remove(source.cacheKey)
    }
)
let session = PlaybackSession(
    configuration: .init(mode: .vertical, preload: .mediaBytes),
    sourceProvider: resolver,
    cache: mediaCache
)
```

Use a cache key scoped to the account, asset version, and rendition when they affect the bytes. Set `isCached` only for a confirmed hit. On failure of a confirmed cached source the session invalidates it and tries the original source once. The host cache owns quotas, eviction, offline retention, HLS segment policy, and data protection.

## Troubleshooting

- **A poster appears when revisiting an item.** A session can reuse a prepared player while its slot is retained and has a displayable frame. Eviction, an expired source, or an item that has never reached its first frame may require the poster.
- **Two screens compete for playback.** Pair `activate()` with `deactivate()` and use shared playback focus across those screens.
- **A remote clip fails.** Check the URL, authorization, expiry, App Transport Security and AVFoundation support for the stream. Use a bundled demo clip to isolate network and source issues.
- **A CocoaPods import fails.** Open the generated workspace, verify the pod is linked to the target, and import `DramaPlayer`.

## Streaming preferences and media tracks

Use `PlaybackConfiguration(streamPreferences:)` to set initial AVFoundation preferences. Change them on the fly when the viewer switches between automatic and data-saver modes.

```swift
session.setStreamPreferences(.init(
    preferredPeakBitRate: 1_200_000,
    preferredPeakBitRateForExpensiveNetworks: 600_000,
    preferredForwardBufferDuration: 4
))
session.setPreloadPolicy(.disabled)
```

Bitrates are in bits per second and buffer duration is in seconds. Zero delegates the setting to AVFoundation. These are preferences for automatic adaptation, so report them as data-saver settings in the UI. A fixed resolution depends on the stream source. Changing preload policy drops inactive slots and cancels media prefetch while the selected episode keeps playing.

Load subtitle or audio options when opening a track picker. Use the returned group's selected track ID to display the current choice.

```swift
if let group = await session.mediaTrackGroup(for: .subtitles) {
    if let spanish = group.tracks.first(where: { $0.languageTag?.hasPrefix("es") == true }) {
        session.selectMediaTrack(.track(spanish.id), in: group)
    }
}
```

Use `.audio` for alternate audio and `.automatic` to restore system selection. Offer `.off` when `allowsDisabling` is true. Reload the group after changing sources. A selection from an old asset returns `false`.

## Playback diagnostics

Subscribe before calling `activate()` to capture startup. The live stream has a bounded buffer and no history. Retain and cancel its consumer task just like the task for `events()`.

```swift
let stream = session.diagnostics()
let observation = Task {
    for await event in stream {
        reportPlaybackQuality(event)
    }
}
```

The host implements `reportPlaybackQuality`. Correlate events by `attemptID` and use an opaque episode ID as `PlaybackItem.id`. Diagnostic events carry that host-supplied ID and omit resolved URLs and underlying error messages.

| Event | Meaning |
| --- | --- |
| `.started` | The selected episode has play intent, is active and can begin playback. |
| `.firstFrame(seconds:)` | Elapsed monotonic time until playback is running with a displayable frame. A reused player can already have a displayable frame. |
| `.rebufferingEnded(seconds:recovered:)` | An SDK-observed buffering interval after first frame. Startup buffering and active seeks are excluded. `recovered` distinguishes playback resuming from an interrupted interval. |
| `.cachedMediaFallback` | The selected cached asset failed and the session is trying its origin URL. |
| `.finished` | The attempt completed, was interrupted, required access, or failed. Pausing, changing episodes or losing focus ends the attempt. Resuming eligible playback begins a fresh attempt. |

## Landscape, portrait, and resizable windows

```swift
let player = SinglePlaybackView(session: session, scaling: .fit)
let feed = VerticalPlaybackView(session: session, scaling: .fill)
```

`PlaybackVideoScaling.fit` keeps the full frame visible. `.fill` fills the viewport with proportional cropping and remains the default for the UIKit player views. The scaling setting applies to the poster and the AVPlayer layer. You can update the view's `scaling` property as its bounds change without resetting the session. The Demo opts in to fit for single-video previews and switches its portrait feed to fit on wider viewports.

The host decides which interface orientations to support. Keep the player pinned to its container and place interactive controls inside the safe area. Use window-scene geometry and the view's current bounds to adapt when the device rotates or a foldable display or Split View changes the window size. Keep the same session so the selected episode and playback progress survive the resize. For full-display behavior on iPhone Duo, build the host app with the iOS 27.1 SDK or later and validate the outer and inner displays, rotation, and fold poses in Device Hub. [Apple's iPhone Duo preparation guide](https://developer.apple.com/iphone-duo/prepare/)

### Landscape brightness and volume gestures

Set `isLandscapeAdjustmentEnabled = true` on `SinglePlaybackView` or `VerticalPlaybackView`. Swipe vertically on the left of a wide video surface to adjust screen brightness, and on the right to adjust the playback session's volume. The feed reserves its center fifth for paging. For custom layouts, retain a `PlaybackLandscapeGestures(session:surface:)` on the video surface and call `invalidate()` to detach it. Place native controls above or outside that surface.

`session.setVolume(_:)` applies a relative gain from 0 to 1 across active, prepared and future players. Use the system volume buttons or a host-provided `MPVolumeView` for the device's output level. [Apple AVPlayer volume](https://developer.apple.com/documentation/avfoundation/avplayer/volume)

## Layout presets and an in-app mini player

`PlaybackLayoutTemplate.presets` provides all 12 combinations of six aspect ratios and fit or fill scaling. Choose 9:16, 3:4, 1:1, 4:3, 16:9, or 21:9. The aspect ratio sizes the viewport, while the scaling setting positions the video and poster inside it.

```swift
let template = PlaybackLayoutTemplate(aspect: .square, scaling: .fill)
player.scaling = template.scaling
let viewportSize = template.fittedSize(in: availableSize)
```

Use `PlaybackMiniPlayerView` for a floating player within your app. Add it as a subview and call `layout(in:)` with the safe-area frame in its superview's coordinates whenever the host lays out. The top grip moves the window, and the lower-right grip changes width and height. `setPreferredSize(_:)` also accepts a size in points. The view clamps the visible size to the available space and retains the requested size across window changes.

Move the existing player view into `miniPlayer.contentView` when opening it. Wire `onExpand` to move it back to the original viewport. Keep the same session and its activation state when moving between these containers. If the host leaves the playback screen, its usual lifecycle rules still apply. [Runnable example](../Demo/Sources/DemoTemplatesViewController.swift).
