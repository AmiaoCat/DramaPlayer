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

Use `session.select(id)` to jump to an episode. Use `setScrollingEnabled(false)` to disable paging while a host interaction requires it. For an existing collection view, use `PlaybackVideoView.display(_:presentation:)` with `session.presentation(for: id)`; mount a given presentation layer in only one view at a time.

## Controls and playback events

Set `showsControls: false` on either player view when supplying your own controls. Use `play()`, `pause()`, `togglePlayback()`, `setRate(_:)`, and `seek(to:)` for direct controls. For an interactive scrubber, call `beginScrubbing()`, `previewScrub(to:)`, then `endScrubbing(commit:)`. Positions and duration are in seconds. The duration may be unavailable during preparation or for a stream without a finite duration.

Keep a task for as long as your screen observes events and cancel it when the screen is released.

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

`renderProgress`, `renderState` and `recordCompletion` are callbacks supplied by the host. The default end behavior is `.stop`; choose `.loop` for a clip or `.advance` for a sequence.

## Focus, lifecycle, and access

Sessions share `PlaybackFocus.shared` by default. Use `activate()` when a screen becomes eligible to play and `deactivate()` when it loses visibility. `PlaybackLifecycle` coordinates backgrounding and audio interruptions on iOS. Configure the app's audio-session category in the host. Suspend playback under a host modal with `setSuspended(true, reason: .overlay)`, and clear the same reason after dismissal.

A resolver receives `.playback` or `.preload`. Return `.allowed(source)` for playable media, `.requiresUserAction` for an item the user must unlock, or `.unavailable` when no source exists. A preload request should only inspect entitlement and should be free of purchases or other side effects. On `.accessRequired`, the host can present its access UI and call `session.retry()` after entitlement changes. Call `invalidateSources()` when an account, entitlement, or quality setting changes. For expiring URLs, set `expiresAt` and resolve a fresh URL when the SDK asks again.

## Preloading and cache integration

| Policy | Behavior |
| --- | --- |
| `.preparedPlayer` | Prepares adjacent authorized items. In vertical mode the bounded pool holds up to three player slots by default. A retained ready player can display without replaying the poster transition. |
| `.mediaBytes` | Hands adjacent media prefetch to the injected `PlaybackMediaCache`. |
| `.disabled` | Disables proactive preloading. |

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
