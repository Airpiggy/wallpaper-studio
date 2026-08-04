import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Serves a video file's bytes to AVFoundation from memory instead of letting
/// AVFoundation stream it off disk.
///
/// Why this exists: AVFoundation re-reads a local file from disk on every loop
/// iteration (there is no public API to make it cache local media), so a looping
/// video wallpaper accumulates disk reads proportional to bitrate × uptime ×
/// number of displays — measured at ~6× the file size per 30s, i.e. tens of GB
/// per day. Feeding the bytes through an `AVAssetResourceLoaderDelegate` on a
/// custom URL scheme keeps every loop in RAM.
///
/// The backing store is a memory-*mapped* `Data` rather than a plain read: the
/// pages are clean and file-backed, so they live in the unified buffer cache,
/// can be reclaimed for free under memory pressure (degrading to an occasional
/// re-read rather than swapping ~200MB of incompressible video out to disk).
final class MemoryVideoAsset: NSObject, @unchecked Sendable {
    /// Custom scheme — the resource loader delegate is only consulted for URLs
    /// that are not file:// or http(s)://.
    static let scheme = "wsmem"

    /// Serve responses off the main queue; AVFoundation may block internal
    /// threads waiting on us, and a main-queue delegate risks deadlock.
    private static let loaderQueue = DispatchQueue(
        label: "com.wallpaperstudio.memoryasset", qos: .userInitiated
    )

    /// Chunk size for responding to data requests. `Data.subdata` copies, so
    /// answering a whole-file request in one shot would transiently double the
    /// memory footprint.
    private static let chunkSize = 4 * 1024 * 1024

    let fileURL: URL
    let assetURL: URL
    private let data: Data
    private let contentType: String

    var contentLength: Int64 { Int64(data.count) }

    /// Map the file into memory. Returns nil if it can't be read at all.
    init?(fileURL: URL) {
        self.fileURL = fileURL

        // .mappedIfSafe declines to map where mapping would be unsafe (e.g.
        // network volumes) and falls back to a regular read on its own.
        guard let mapped = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              !mapped.isEmpty else {
            return nil
        }
        self.data = mapped

        let ext = fileURL.pathExtension
        self.contentType = UTType(filenameExtension: ext)?.identifier ?? UTType.movie.identifier

        // Keep the real filename/extension in the custom URL: extension-less
        // custom URLs have been observed to stall loading on some OS versions.
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = UUID().uuidString
        components.path = "/" + fileURL.lastPathComponent
        guard let url = components.url else { return nil }
        self.assetURL = url

        super.init()
    }

    /// Build an asset that pulls its bytes from this object.
    ///
    /// The resource loader holds its delegate **weakly**, so the caller must
    /// keep this `MemoryVideoAsset` alive for as long as the returned asset is
    /// in use.
    func makeAsset() -> AVURLAsset {
        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(self, queue: Self.loaderQueue)
        return asset
    }

    /// Clamp a requested byte range against the resource size.
    /// Returns nil when the request cannot be satisfied at all.
    static func resolveRange(
        offset: Int64, length: Int, toEnd: Bool, total: Int64
    ) -> Range<Int>? {
        guard offset >= 0, offset < total else { return nil }
        let available = total - offset
        let wanted: Int64 = toEnd ? available : min(Int64(max(length, 0)), available)
        guard wanted > 0 else { return nil }
        let start = Int(offset)
        return start..<(start + Int(wanted))
    }
}

// MARK: - AVAssetResourceLoaderDelegate

extension MemoryVideoAsset: AVAssetResourceLoaderDelegate {
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // Content information request. Answer it and finish — do NOT also serve
        // the small dataRequest that accompanies it; doing so is a known cause
        // of indefinitely stalled playback.
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = contentLength
            info.isByteRangeAccessSupported = true
            loadingRequest.finishLoading()
            return true
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        // Serve from the mapped bytes, in chunks.
        guard let range = Self.resolveRange(
            offset: dataRequest.currentOffset,
            length: dataRequest.requestedLength,
            toEnd: dataRequest.requestsAllDataToEndOfResource,
            total: contentLength
        ) else {
            loadingRequest.finishLoading(with: NSError(
                domain: NSPOSIXErrorDomain, code: Int(EINVAL),
                userInfo: [NSLocalizedDescriptionKey: "Requested range is outside the resource"]
            ))
            return true
        }

        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if loadingRequest.isCancelled { return true }
            let end = min(cursor + Self.chunkSize, range.upperBound)
            dataRequest.respond(with: data.subdata(in: cursor..<end))
            cursor = end
        }
        loadingRequest.finishLoading()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // Nothing async to unwind — responses are served synchronously from memory.
    }
}

/// Shares one mapped blob per file across renderers, so a wallpaper shown on two
/// displays is only held in memory once. Entries are held weakly: when every
/// renderer using a file tears down, the mapping is released automatically.
final class MemoryVideoAssetRegistry {
    static let shared = MemoryVideoAssetRegistry()

    private let lock = NSLock()
    private var entries: [URL: WeakBox] = [:]

    private final class WeakBox {
        weak var value: MemoryVideoAsset?
        init(_ value: MemoryVideoAsset) { self.value = value }
    }

    private init() {}

    /// Returns a shared memory-backed asset for `fileURL`, or nil if the file is
    /// larger than `maxBytes`, caching is disabled (`maxBytes <= 0`), or the
    /// file can't be mapped. Callers fall back to disk-backed playback on nil.
    func asset(for fileURL: URL, maxBytes: Int64) -> MemoryVideoAsset? {
        guard maxBytes > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        // Drop entries whose asset has been released.
        entries = entries.filter { $0.value.value != nil }

        if let existing = entries[fileURL]?.value {
            return existing
        }

        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
            size.int64Value > 0, size.int64Value <= maxBytes else {
            return nil
        }

        guard let asset = MemoryVideoAsset(fileURL: fileURL) else { return nil }
        entries[fileURL] = WeakBox(asset)
        return asset
    }

    /// Test hook: number of live entries.
    var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { $0.value.value != nil }
        return entries.count
    }
}
