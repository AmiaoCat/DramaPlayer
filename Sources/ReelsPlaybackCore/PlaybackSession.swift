import AVFoundation
import Foundation

@MainActor
public struct PlaybackPresentation {
    public let layer: AVPlayerLayer
    public let firstFrameReady: Bool
}

@MainActor
public final class PlaybackSession {
    private final class Slot {
        enum Phase { case resolving, installed, accessRequired, failed(PlaybackFailure) }

        let item: PlaybackItem
        let driver: any PlaybackDriver
        let purpose: PlaybackPurpose
        var phase: Phase = .resolving
        var source: PlaybackSource?
        var media: PlaybackMedia?
        var work: Task<Void, Never>?
        var initialSeek: Task<Void, Never>?
        var isPositioned: Bool
        var recoveryPosition: TimeInterval?
        var started = false
        var warmed = false
        var ended = false
        var retriedCache = false
        var reportedFrame = false
        var parkedAt = Date.now

        init(item: PlaybackItem, purpose: PlaybackPurpose, driver: any PlaybackDriver) {
            self.item = item
            self.purpose = purpose
            self.driver = driver
            isPositioned = item.resumePosition == 0
        }

        deinit {
            work?.cancel()
            initialSeek?.cancel()
        }
    }

    public let configuration: PlaybackConfiguration
    public private(set) var items: [PlaybackItem] = []
    public private(set) var selectedID: String?
    public private(set) var rate: Float = 1

    private let sourceProvider: any PlaybackSourceProvider
    private let cache: any PlaybackMediaCache
    private let focus: PlaybackFocus
    private let makeDriver: @MainActor () -> any PlaybackDriver
    private var slots: [String: Slot] = [:]
    private var recent: [String] = []
    private var manuallyPaused: Set<String> = []
    private var suspensions: Set<PlaybackSuspension> = []
    private var subscribers: [UUID: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var lastSnapshot: PlaybackSnapshot?
    private var active = false
    private var wantsPlayback = false
    private var scrubPosition: TimeInterval?
    private var seekTask: Task<Void, Never>?
    private var seekID: UUID?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedID: String?
    private var preloadingSuppressed = false

    public convenience init(configuration: PlaybackConfiguration = .init(),
                            sourceProvider: any PlaybackSourceProvider,
                            cache: any PlaybackMediaCache = DirectPlaybackMediaCache(),
                            focus: PlaybackFocus? = nil) {
        self.init(configuration: configuration, sourceProvider: sourceProvider, cache: cache,
                  focus: focus ?? .shared, makeDriver: { AVPlaybackDriver() })
    }

    init(configuration: PlaybackConfiguration, sourceProvider: any PlaybackSourceProvider,
         cache: any PlaybackMediaCache, focus: PlaybackFocus,
         makeDriver: @escaping @MainActor () -> any PlaybackDriver) {
        self.configuration = configuration
        self.sourceProvider = sourceProvider
        self.cache = cache
        self.focus = focus
        self.makeDriver = makeDriver
    }

    public var snapshot: PlaybackSnapshot {
        let slot = selectedSlot
        let driver = slot?.driver
        let position = scrubPosition ?? driver?.position ?? 0
        let buffer = driver?.bufferedUntil ?? position
        return PlaybackSnapshot(
            itemID: selectedID, state: state(for: slot), position: position, duration: driver?.duration,
            bufferedUntil: buffer.isFinite ? max(0, buffer) : position, rate: rate,
            wantsPlayback: wantsPlayback, firstFrameReady: slot.map(isFrameReady) ?? false,
            isScrubbing: scrubPosition != nil
        )
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self, bufferingPolicy: .bufferingNewest(32))
        subscribers[id] = continuation
        continuation.yield(.queueChanged)
        continuation.yield(.snapshot(snapshot))
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Replace the queue, preserving the active item when its descriptor and selection still match.
    public func setItems(_ items: [PlaybackItem], selectedID requested: String? = nil) {
        var seen: Set<String> = []
        let updated = items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        let byID = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        let next = requested.flatMap { byID[$0]?.id } ?? selectedID.flatMap { byID[$0]?.id } ?? updated.first?.id
        let keepsSelection = next == selectedID
            && updated.first(where: { $0.id == next }) == self.items.first(where: { $0.id == next })

        cancelPrefetch()
        for (id, slot) in slots where byID[id] != slot.item { release(id) }
        self.items = updated
        manuallyPaused.formIntersection(seen)
        recent.removeAll { !seen.contains($0) }
        if !keepsSelection {
            switchSelection(to: next)
        } else {
            reconcileWindow()
        }
        emit(.queueChanged)
        publish()
    }

    public func select(_ id: String) {
        guard selectedID != id, items.contains(where: { $0.id == id }) else { return }
        switchSelection(to: id)
        publish()
    }

    /// Call when the owning screen is visible and allowed to take playback focus.
    public func activate() {
        focus.claim(self)
        active = true
        if suspensions.isEmpty { refreshExpiredSelection() }
        reconcileWindow()
        applyPlayback()
        publish()
    }

    public func deactivate() {
        focus.release(self)
        focusWasTaken()
    }

    func focusWasTaken() {
        active = false
        cancelPrefetch()
        cancelUnselectedLoads()
        applyPlayback()
        publish()
    }

    public func setSuspended(_ suspended: Bool, reason: PlaybackSuspension) {
        if suspended {
            suspensions.insert(reason)
            cancelPrefetch()
            cancelUnselectedLoads()
        } else {
            suspensions.remove(reason)
            if active, suspensions.isEmpty { refreshExpiredSelection() }
            reconcileWindow()
        }
        applyPlayback()
        publish()
    }

    public func play() {
        guard let selectedID else { return }
        manuallyPaused.remove(selectedID)
        wantsPlayback = true
        if selectedSlot?.ended == true {
            requestSeek(to: 0)
        } else {
            reconcileWindow()
            applyPlayback()
        }
        publish()
    }

    public func pause() {
        if let selectedID { manuallyPaused.insert(selectedID) }
        wantsPlayback = false
        applyPlayback()
        publish()
    }

    public func togglePlayback() {
        switch snapshot.state {
        case .accessRequired: return
        case .failed: retry()
        case .ended: play()
        default:
            if wantsPlayback { pause() }
            else { play() }
        }
    }

    public func setRate(_ rate: Float) {
        guard configuration.rates.contains(rate), self.rate != rate else { return }
        self.rate = rate
        if let slot = selectedSlot, slot.started, canPlay { slot.driver.play(rate: rate) }
        publish()
    }

    public func beginScrubbing() {
        guard scrubPosition == nil, let slot = selectedSlot, slot.isPositioned, slot.driver.duration != nil else { return }
        cancelSeek()
        scrubPosition = slot.driver.position
        applyPlayback()
        publish()
    }

    public func previewScrub(to position: TimeInterval) {
        guard scrubPosition != nil, let slot = selectedSlot,
              let target = clampedPosition(position, slot: slot) else { return }
        scrubPosition = target
        publish()
    }

    public func endScrubbing(commit: Bool = true) {
        guard let position = scrubPosition else { return }
        scrubPosition = nil
        if commit { requestSeek(to: position) }
        else {
            applyPlayback()
            publish()
        }
    }

    public func seek(to position: TimeInterval) {
        scrubPosition = nil
        requestSeek(to: position)
    }

    public func retry() {
        guard let selectedID else { return }
        cancelSeek()
        scrubPosition = nil
        release(selectedID)
        reconcileWindow()
        publish()
    }

    /// Drop authorization and decoded frames after an account, grant, or rendition change.
    public func invalidateSources() {
        cancelSeek()
        scrubPosition = nil
        cancelPrefetch()
        for id in Array(slots.keys) { release(id) }
        reconcileWindow()
        publish()
    }

    public func discardInactiveItems() {
        preloadingSuppressed = true
        cancelPrefetch()
        for id in Array(slots.keys) where id != selectedID { release(id) }
        publish()
    }

    public func presentation(for id: String) -> PlaybackPresentation? {
        guard let slot = slots[id], case .installed = slot.phase,
              id == selectedID || isReusable(slot) else { return nil }
        return PlaybackPresentation(layer: slot.driver.layer, firstFrameReady: isFrameReady(slot))
    }

    private var selectedSlot: Slot? { selectedID.flatMap { slots[$0] } }

    private var canPlay: Bool {
        active && suspensions.isEmpty && wantsPlayback && scrubPosition == nil && seekID == nil
    }

    private func state(for slot: Slot?) -> PlaybackState {
        guard let slot else { return .idle }
        switch slot.phase {
        case .resolving: return .preparing
        case .accessRequired: return .accessRequired
        case .failed(let failure): return .failed(failure)
        case .installed:
            if slot.ended { return .ended }
            if slot.driver.status != .ready || !slot.isPositioned { return .preparing }
            if !canPlay { return slot.reportedFrame ? .paused : .ready }
            if slot.driver.isPlaying { return .playing }
            return slot.driver.isWaiting ? .buffering : .ready
        }
    }

    private func switchSelection(to id: String?) {
        preloadingSuppressed = false
        cancelSeek()
        scrubPosition = nil
        cancelPrefetch()
        if let old = selectedSlot {
            old.driver.pause()
            old.started = false
            old.warmed = false
            old.parkedAt = .now
        }
        selectedID = id
        wantsPlayback = id.map { configuration.autoplay && !manuallyPaused.contains($0) } ?? false
        if let id {
            recent.removeAll { $0 == id }
            recent.insert(id, at: 0)
            recent = Array(recent.prefix(3))
            if let slot = slots[id] {
                if !isReusable(slot) {
                    release(id)
                } else if slot.ended, wantsPlayback {
                    requestSeek(to: 0)
                }
            }
        }
        reconcileWindow()
        applyPlayback()
    }

    private func isReusable(_ slot: Slot) -> Bool {
        guard case .installed = slot.phase, slot.source?.isValid == true,
              slot.driver.status != .failed else { return false }
        return Date.now.timeIntervalSince(slot.parkedAt) <= configuration.retention
    }

    private func refreshExpiredSelection() {
        guard let id = selectedID, selectedSlot?.source?.isValid == false else { return }
        cancelSeek()
        scrubPosition = nil
        release(id)
    }

    private func isFrameReady(_ slot: Slot) -> Bool {
        if case .installed = slot.phase {
            return slot.isPositioned && slot.driver.isFrameReady
        }
        return false
    }

    private func reconcileWindow() {
        guard let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) else {
            for key in Array(slots.keys) { release(key) }
            return
        }

        var nearby: [String] = []
        if configuration.mode == .vertical {
            let next = index + 1 < items.count ? items[index + 1].id : nil
            let previous = index > 0 ? items[index - 1].id : nil
            nearby = recent.dropFirst().filter { slots[$0].map(isReusable) == true }
            for candidate in [next, previous].compactMap({ $0 }) where !nearby.contains(candidate) {
                nearby.append(candidate)
            }
        }

        let limit = configuration.mode == .single ? 1 : configuration.preparedItemLimit
        nearby = Array(nearby.prefix(max(0, limit - 1)))
        let retained = Set([id] + nearby)
        for (key, slot) in slots where key != id &&
            (!retained.contains(key) || (slot.source != nil && !isReusable(slot))) {
            release(key)
        }

        guard active, suspensions.isEmpty else { return }
        if slots[id] == nil { load(items[index], purpose: .playback) }
        guard !preloadingSuppressed, let current = selectedSlot, current.driver.status == .ready, current.isPositioned,
              case .installed = current.phase else { return }

        switch configuration.preload {
        case .disabled: break
        case .preparedPlayer:
            // Resolve at most one neighboring item at a time so the current stream gets priority.
            guard !slots.values.contains(where: { slot in
                if case .resolving = slot.phase { return true }
                if case .installed = slot.phase { return slot.driver.status != .ready || !slot.isPositioned }
                return false
            }) else { return }
            if let candidate = nearby.first(where: { slots[$0] == nil }),
               let item = items.first(where: { $0.id == candidate }) {
                load(item, purpose: .preload)
            }
        case .mediaBytes:
            if index + 1 < items.count { prefetch(items[index + 1]) }
        }
    }

    private func load(_ item: PlaybackItem, purpose: PlaybackPurpose) {
        let slot = Slot(item: item, purpose: purpose, driver: makeDriver())
        slots[item.id] = slot
        slot.driver.onChange = { [weak self, weak slot] in
            guard let slot else { return }
            self?.driverChanged(slot)
        }
        slot.driver.onEnd = { [weak self, weak slot] in
            guard let slot else { return }
            self?.driverEnded(slot)
        }
        slot.work = Task { [weak self, weak slot, sourceProvider, cache] in
            let access: PlaybackAccess
            do {
                access = try await sourceProvider.source(for: item, purpose: purpose)
            } catch {
                guard let self, let slot, self.isCurrent(slot), !Task.isCancelled else { return }
                self.fail(slot, .sourceUnavailable)
                return
            }
            guard let slot, self?.isCurrent(slot) == true, !Task.isCancelled else { return }
            switch access {
            case .allowed(let source):
                guard source.isValid else {
                    self?.fail(slot, .sourceExpired)
                    return
                }
                let media: PlaybackMedia
                do { media = try await cache.media(for: source) }
                catch { media = PlaybackMedia(url: source.url) }
                guard let self, self.isCurrent(slot), !Task.isCancelled else { return }
                guard source.isValid else {
                    self.fail(slot, .sourceExpired)
                    return
                }
                self.install(media, source: source, in: slot)
            case .requiresUserAction:
                slot.phase = .accessRequired
                self?.publish()
            case .unavailable:
                self?.fail(slot, .sourceUnavailable)
            }
        }
        publish()
    }

    private func install(_ media: PlaybackMedia, source: PlaybackSource, in slot: Slot) {
        slot.source = source
        slot.media = media
        slot.phase = .installed
        slot.started = false
        slot.warmed = false
        slot.driver.load(media.url)
        emit(.presentationChanged(slot.item.id))
        driverChanged(slot)
    }

    private func fail(_ slot: Slot, _ failure: PlaybackFailure) {
        slot.phase = .failed(failure)
        slot.started = false
        slot.driver.clear()
        emit(.presentationChanged(slot.item.id))
        publish()
    }

    private func driverChanged(_ slot: Slot) {
        guard isCurrent(slot), case .installed = slot.phase else { return }
        if slot.driver.status == .failed {
            recover(slot)
            return
        }
        if slot.driver.status == .ready {
            if !slot.isPositioned { positionInitially(slot) }
            else if slot.item.id != selectedID, !slot.warmed, active, suspensions.isEmpty {
                slot.warmed = true
                slot.driver.warm()
            }
        }
        let frame = isFrameReady(slot)
        if frame != slot.reportedFrame {
            slot.reportedFrame = frame
            emit(.presentationChanged(slot.item.id))
        }
        if slot.item.id == selectedID {
            applyPlayback()
            reconcileWindow()
            publish()
        } else if slot.driver.status == .ready {
            reconcileWindow()
        }
    }

    private func positionInitially(_ slot: Slot) {
        guard slot.initialSeek == nil else { return }
        let position = clampedPosition(slot.recoveryPosition ?? slot.item.resumePosition, slot: slot) ?? 0
        slot.initialSeek = Task { [weak self, weak slot] in
            guard let slot else { return }
            _ = await slot.driver.seek(to: position)
            guard let self, self.isCurrent(slot), !Task.isCancelled else { return }
            slot.initialSeek = nil
            slot.isPositioned = true
            self.driverChanged(slot)
        }
    }

    private func driverEnded(_ slot: Slot) {
        guard isCurrent(slot), slot.item.id == selectedID, slot.started else { return }
        slot.ended = true
        slot.started = false
        slot.driver.pause()
        emit(.ended(slot.item.id))
        switch configuration.endBehavior {
        case .loop where canPlay:
            requestSeek(to: 0)
        case .advance where canPlay:
            if let index = items.firstIndex(where: { $0.id == slot.item.id }), index + 1 < items.count {
                select(items[index + 1].id)
            }
        default: break
        }
        publish()
    }

    private func applyPlayback() {
        guard let slot = selectedSlot else { return }
        let installed: Bool
        if case .installed = slot.phase { installed = true } else { installed = false }
        let shouldPlay = installed && canPlay && slot.isPositioned && !slot.ended && slot.driver.status == .ready
        if shouldPlay, !slot.started {
            slot.started = true
            slot.driver.play(rate: rate)
        } else if !shouldPlay, slot.started {
            slot.started = false
            slot.driver.pause()
        }
    }

    private func requestSeek(to position: TimeInterval) {
        guard let slot = selectedSlot, slot.isPositioned, slot.driver.status == .ready,
              let target = clampedPosition(position, slot: slot) else {
            applyPlayback()
            publish()
            return
        }
        cancelSeek()
        let id = UUID()
        seekID = id
        applyPlayback()
        seekTask = Task { [weak self, weak slot] in
            guard let slot else { return }
            let finished = await slot.driver.seek(to: target)
            guard let self, self.seekID == id, self.selectedSlot === slot, !Task.isCancelled else { return }
            self.seekID = nil
            self.seekTask = nil
            if finished { slot.ended = false }
            self.applyPlayback()
            self.publish()
        }
        publish()
    }

    private func clampedPosition(_ position: TimeInterval, slot: Slot) -> TimeInterval? {
        guard position.isFinite else { return nil }
        return max(0, min(position, slot.driver.duration ?? position))
    }

    private func recover(_ slot: Slot) {
        guard slot.item.id == selectedID, slot.media?.isCached == true, !slot.retriedCache,
              let source = slot.source, source.isValid else {
            fail(slot, .playbackFailed)
            return
        }
        slot.retriedCache = true
        let resumePosition = slot.driver.position
        slot.phase = .resolving
        slot.started = false
        slot.driver.clear()
        slot.reportedFrame = false
        emit(.presentationChanged(slot.item.id))
        slot.work = Task { [weak self, weak slot, cache] in
            await cache.invalidate(source)
            guard let self, let slot, self.isCurrent(slot), !Task.isCancelled else { return }
            guard source.isValid else {
                self.fail(slot, .sourceExpired)
                return
            }
            slot.initialSeek?.cancel()
            slot.initialSeek = nil
            slot.recoveryPosition = resumePosition
            slot.isPositioned = resumePosition == 0
            self.install(PlaybackMedia(url: source.url), source: source, in: slot)
        }
        publish()
    }

    private func prefetch(_ item: PlaybackItem) {
        guard prefetchedID != item.id else { return }
        cancelPrefetch()
        prefetchedID = item.id
        prefetchTask = Task(priority: .utility) { [sourceProvider, cache] in
            guard case .allowed(let source) = try? await sourceProvider.source(for: item, purpose: .preload),
                  source.isValid, !Task.isCancelled else { return }
            try? await cache.prefetch(source)
        }
    }

    private func cancelUnselectedLoads() {
        for (id, slot) in slots where id != selectedID {
            if case .resolving = slot.phase { release(id) }
            else { slot.driver.pause() }
        }
    }

    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedID = nil
    }

    private func cancelSeek() {
        seekTask?.cancel()
        seekTask = nil
        seekID = nil
    }

    private func isCurrent(_ slot: Slot) -> Bool { slots[slot.item.id] === slot }

    private func release(_ id: String) {
        guard let slot = slots.removeValue(forKey: id) else { return }
        slot.work?.cancel()
        slot.initialSeek?.cancel()
        slot.driver.onChange = nil
        slot.driver.onEnd = nil
        slot.driver.clear()
        emit(.presentationChanged(id))
    }

    private func publish() {
        let current = snapshot
        guard current != lastSnapshot else { return }
        lastSnapshot = current
        emit(.snapshot(current))
    }

    private func emit(_ event: PlaybackEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    deinit {
        seekTask?.cancel()
        prefetchTask?.cancel()
        for continuation in subscribers.values { continuation.finish() }
    }
}
