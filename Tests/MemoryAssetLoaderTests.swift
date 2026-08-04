import AVFoundation
import XCTest
@testable import WallpaperStudio

final class MemoryAssetLoaderTests: XCTestCase {

    /// The bundled sample video (~800KB, 5s), copied to a temp file so each test
    /// controls its own registry lifetime.
    private func makeTempVideo() throws -> URL {
        // Tests are hosted by the app, so Bundle.main is the app bundle.
        let testBundle = Bundle(for: MemoryAssetLoaderTests.self)
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Fixtures/SampleVideo/sample.mp4"),
            Bundle.main.url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures/SampleVideo"),
            testBundle.url(forResource: "sample", withExtension: "mp4"),
        ]
        guard let source = candidates.compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("sample.mp4 fixture not found in build products")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-memasset-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: source, to: dest)
        addTeardownBlock { try? FileManager.default.removeItem(at: dest) }
        return dest
    }

    // MARK: - End-to-end: AVFoundation can parse a memory-backed asset

    func testMemoryBackedAssetIsPlayable() async throws {
        let url = try makeTempVideo()
        let memory = try XCTUnwrap(MemoryVideoAsset(fileURL: url))
        let asset = memory.makeAsset()

        // Exercises the full delegate path: content info + moov range requests.
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        XCTAssertTrue(playable)
        XCTAssertEqual(CMTimeGetSeconds(duration), 5.0, accuracy: 0.5)

        // Video track present and sized as expected.
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }

    func testMemoryBackedAssetUsesCustomScheme() throws {
        let url = try makeTempVideo()
        let memory = try XCTUnwrap(MemoryVideoAsset(fileURL: url))
        XCTAssertEqual(memory.assetURL.scheme, "wsmem")
        // Extension preserved — extension-less custom URLs can stall loading.
        XCTAssertEqual(memory.assetURL.pathExtension, "mp4")
        XCTAssertGreaterThan(memory.contentLength, 0)
    }

    // MARK: - Registry

    func testRegistrySharesInstanceAcrossCalls() throws {
        let url = try makeTempVideo()
        let first = try XCTUnwrap(MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 200 << 20))
        let second = try XCTUnwrap(MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 200 << 20))
        // Two displays showing one wallpaper share a single mapping.
        XCTAssertTrue(first === second)
    }

    func testRegistryReleasesWhenUnreferenced() throws {
        let url = try makeTempVideo()
        weak var observer: MemoryVideoAsset?
        do {
            let strong = try XCTUnwrap(
                MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 200 << 20)
            )
            observer = strong
            XCTAssertNotNil(observer)
        }
        // With the last renderer's reference gone, the mapping must be freed
        // rather than pinned by the registry (which holds entries weakly).
        XCTAssertNil(observer, "registry must not keep the mapped asset alive")

        // And a later request still yields a usable asset.
        let rebuilt = try XCTUnwrap(MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 200 << 20))
        XCTAssertGreaterThan(rebuilt.contentLength, 0)
    }

    func testRegistryRespectsSizeThreshold() throws {
        let url = try makeTempVideo()
        // Sample is ~800KB; a 1-byte cap must refuse it.
        XCTAssertNil(MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 1))
    }

    func testRegistryDisabledWhenLimitIsZero() throws {
        let url = try makeTempVideo()
        XCTAssertNil(MemoryVideoAssetRegistry.shared.asset(for: url, maxBytes: 0))
    }

    func testRegistryReturnsNilForMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/nope.mp4")
        XCTAssertNil(MemoryVideoAssetRegistry.shared.asset(for: missing, maxBytes: 200 << 20))
    }

    // MARK: - Range resolution (pure function)

    func testResolveRangeNormal() {
        let range = MemoryVideoAsset.resolveRange(offset: 10, length: 20, toEnd: false, total: 100)
        XCTAssertEqual(range, 10..<30)
    }

    func testResolveRangeToEnd() {
        let range = MemoryVideoAsset.resolveRange(offset: 90, length: 2, toEnd: true, total: 100)
        XCTAssertEqual(range, 90..<100)
    }

    func testResolveRangeClampsPastEnd() {
        let range = MemoryVideoAsset.resolveRange(offset: 95, length: 50, toEnd: false, total: 100)
        XCTAssertEqual(range, 95..<100)
    }

    func testResolveRangeRejectsOutOfBounds() {
        XCTAssertNil(MemoryVideoAsset.resolveRange(offset: 100, length: 10, toEnd: false, total: 100))
        XCTAssertNil(MemoryVideoAsset.resolveRange(offset: -1, length: 10, toEnd: false, total: 100))
        XCTAssertNil(MemoryVideoAsset.resolveRange(offset: 0, length: 0, toEnd: false, total: 100))
    }
}
