import CryptoKit
import Foundation

public enum PlaybackDownloadError: Error, Sendable {
    case unsupportedSource
    case invalidResponse
    case invalidFile
    case operationInProgress
}

/// Persistent, explicitly requested HTTPS MP4 downloads. Scope the directory and
/// source cache keys to your app's accounts and authorization model.
public actor PlaybackDownloadStore: PlaybackMediaCache {
    private let directory: URL
    private let urlSession: URLSession
    private var downloading: Set<String> = []

    /// Use one store per dedicated directory. The directory is excluded from backups.
    public init(directory: URL, urlSession: URLSession = .shared) {
        self.directory = directory
        self.urlSession = urlSession
    }

    public static func supports(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.pathExtension.lowercased() == "mp4"
    }

    public func localURL(for source: PlaybackSource) -> URL? {
        let file = fileURL(for: source.cacheKey)
        return FileManager.default.isReadableFile(atPath: file.path) ? file : nil
    }

    public func media(for source: PlaybackSource) -> PlaybackMedia {
        guard let file = localURL(for: source) else { return .init(url: source.url) }
        return .init(url: file, isCached: true)
    }

    /// Returns an existing copy or downloads the entire file. Cancelling the caller cancels the transfer.
    @discardableResult
    public func download(_ source: PlaybackSource) async throws -> URL {
        try Task.checkCancellation()
        guard Self.supports(source.url), source.isValid else { throw PlaybackDownloadError.unsupportedSource }
        if let file = localURL(for: source) { return file }
        guard downloading.insert(source.cacheKey).inserted else { throw PlaybackDownloadError.operationInProgress }
        defer { downloading.remove(source.cacheKey) }

        let (temporary, response) = try await urlSession.download(from: source.url)
        let manager = FileManager.default
        defer { try? manager.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme?.lowercased() == "https" else {
            throw PlaybackDownloadError.invalidResponse
        }
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 12), header.count == 12,
              header[4..<8].elementsEqual("ftyp".utf8) else {
            throw PlaybackDownloadError.invalidFile
        }

        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let destination = fileURL(for: source.cacheKey)
        let staging = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("partial")
        defer { try? manager.removeItem(at: staging) }
        try manager.moveItem(at: temporary, to: staging)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: destination)
        return destination
    }

    /// Remove only the copy managed by this store. An absent copy is already deleted.
    public func deleteDownload(for source: PlaybackSource) throws {
        guard !downloading.contains(source.cacheKey) else { throw PlaybackDownloadError.operationInProgress }
        do {
            try FileManager.default.removeItem(at: fileURL(for: source.cacheKey))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("mp4")
    }
}
