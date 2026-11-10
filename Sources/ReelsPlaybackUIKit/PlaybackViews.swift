#if canImport(UIKit)
#if SWIFT_PACKAGE
import ReelsPlaybackCore
#endif
import UIKit

@MainActor
public final class SinglePlaybackView: UIView {
    private let session: PlaybackSession
    private let video: PlaybackVideoView
    private var events: Task<Void, Never>?

    public init(session: PlaybackSession, coverLoader: any PlaybackCoverLoader = URLPlaybackCoverLoader(),
                showsControls: Bool = true) {
        self.session = session
        video = PlaybackVideoView(coverLoader: coverLoader)
        super.init(frame: .zero)
        addSubview(video)
        video.frame = bounds
        video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        video.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(togglePlayback)))
        if showsControls { installControls(PlaybackControlsView(session: session), in: self) }
        let stream = session.events()
        events = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                let session = self.session
                let item = session.items.first { $0.id == session.selectedID }
                self.video.display(item, presentation: item.flatMap { session.presentation(for: $0.id) })
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func togglePlayback() { session.togglePlayback() }

    deinit { events?.cancel() }
}

@MainActor
public final class VerticalPlaybackView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let session: PlaybackSession
    private let loader: any PlaybackCoverLoader
    private let collection: UICollectionView
    private var events: Task<Void, Never>?
    private var itemIDs: [String] = []
    private var lastSize: CGSize = .zero

    public init(session: PlaybackSession, coverLoader: any PlaybackCoverLoader = URLPlaybackCoverLoader(),
                showsControls: Bool = true) {
        self.session = session
        loader = coverLoader
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        backgroundColor = .black
        collection.backgroundColor = .black
        collection.dataSource = self
        collection.delegate = self
        collection.isPagingEnabled = true
        collection.showsVerticalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(Page.self, forCellWithReuseIdentifier: Page.reuseID)
        addSubview(collection)
        if showsControls { installControls(PlaybackControlsView(session: session), in: self) }
        itemIDs = session.items.map(\.id)
        let stream = session.events()
        events = Task { [weak self] in
            for await event in stream { self?.receive(event) }
        }
    }

    required init?(coder: NSCoder) { nil }

    public override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = bounds
        if lastSize != bounds.size {
            lastSize = bounds.size
            collection.collectionViewLayout.invalidateLayout()
            positionSelection()
        }
    }

    public func setScrollingEnabled(_ enabled: Bool) {
        collection.isScrollEnabled = enabled
        if !enabled { positionSelection() }
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemIDs.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Page.reuseID, for: indexPath) as! Page
        cell.installCoverLoaderIfNeeded(loader)
        render(cell, at: indexPath)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                               forItemAt indexPath: IndexPath) {
        if let page = cell as? Page { render(page, at: indexPath) }
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard itemIDs.indices.contains(indexPath.item), itemIDs[indexPath.item] == session.selectedID else { return }
        session.togglePlayback()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }

    private func settle() {
        guard collection.bounds.height > 0, !itemIDs.isEmpty else { return }
        let index = Int((collection.contentOffset.y / collection.bounds.height).rounded())
        session.select(itemIDs[min(max(0, index), itemIDs.count - 1)])
    }

    private func receive(_ event: PlaybackEvent) {
        switch event {
        case .queueChanged:
            let next = session.items.map(\.id)
            if next != itemIDs {
                itemIDs = next
                collection.reloadData()
                collection.layoutIfNeeded()
            }
            positionSelection()
        case .snapshot:
            positionSelection()
        case .presentationChanged:
            break
        case .ended:
            return
        }
        for index in collection.indexPathsForVisibleItems {
            if let cell = collection.cellForItem(at: index) as? Page { render(cell, at: index) }
        }
    }

    private func positionSelection() {
        guard !collection.isDragging, !collection.isDecelerating, collection.bounds.height > 0,
              let id = session.selectedID, let index = itemIDs.firstIndex(of: id) else { return }
        let y = CGFloat(index) * collection.bounds.height
        if abs(y - collection.contentOffset.y) > 1 {
            collection.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    private func render(_ cell: Page, at index: IndexPath) {
        guard itemIDs.indices.contains(index.item) else { return }
        let id = itemIDs[index.item]
        let item = session.items.first { $0.id == id }
        cell.video?.display(item, presentation: session.presentation(for: id))
    }

    deinit { events?.cancel() }

    private final class Page: UICollectionViewCell {
        static let reuseID = "PlaybackPage"
        private(set) var video: PlaybackVideoView?

        func installCoverLoaderIfNeeded(_ loader: any PlaybackCoverLoader) {
            guard video == nil else { return }
            let video = PlaybackVideoView(coverLoader: loader)
            video.frame = contentView.bounds
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(video)
            self.video = video
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            video?.display(nil, presentation: nil)
        }
    }
}

@MainActor
private func installControls(_ controls: PlaybackControlsView, in view: UIView) {
    controls.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(controls)
    NSLayoutConstraint.activate([
        controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
    ])
}
#endif
