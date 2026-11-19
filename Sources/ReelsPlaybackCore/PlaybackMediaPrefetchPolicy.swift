import Foundation

/// Chooses which episodes to warm when a session uses `.mediaBytes`.
public struct PlaybackMediaPrefetchPolicy: Sendable {
    public struct Context: Sendable {
        public let items: [PlaybackItem]
        public let selectedIndex: Int
        public var selectedItem: PlaybackItem { items[selectedIndex] }
    }

    public let maxCandidates: Int
    private let select: @Sendable (Context) -> [String]

    /// Return episode IDs in priority order. Keep the selector lightweight and free of side effects.
    public init(maxCandidates: Int = 3, select: @escaping @Sendable (Context) -> [String]) {
        self.maxCandidates = min(8, max(0, maxCandidates))
        self.select = select
    }

    /// Positive offsets select later episodes, negative offsets select earlier episodes.
    public init(offsets: [Int], maxCandidates: Int = 3) {
        self.init(maxCandidates: maxCandidates) { context in
            offsets.compactMap { offset in
                let (index, overflow) = context.selectedIndex.addingReportingOverflow(offset)
                guard !overflow, context.items.indices.contains(index) else { return nil }
                return context.items[index].id
            }
        }
    }

    func candidates(in items: [PlaybackItem], selectedIndex: Int) -> [PlaybackItem] {
        guard maxCandidates > 0 else { return [] }
        let context = Context(items: items, selectedIndex: selectedIndex)
        let ids = select(context)
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var seen = Set([context.selectedItem.id])
        var candidates: [PlaybackItem] = []
        for id in ids {
            guard let item = byID[id], seen.insert(id).inserted else { continue }
            candidates.append(item)
            if candidates.count == maxCandidates { break }
        }
        return candidates
    }
}
