import AVFoundation
import XCTest
@testable import WallpaperStudio

/// Measures real disk reads through the production `VideoRenderer` path.
///
/// Opt-in (slow, timing dependent):
///     WS_DISKIO_TEST=1 xcodebuild ... test
@MainActor
final class VideoRendererDiskIOTests: XCTestCase {

    private func sampleVideoURL() throws -> URL {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Fixtures/SampleVideo/sample.mp4"),
            Bundle(for: VideoRendererDiskIOTests.self).url(forResource: "sample", withExtension: "mp4"),
        ]
        guard let url = candidates.compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("sample.mp4 fixture not found")
        }
        // Use a unique copy so the page cache/registry state is per-run.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-diskio-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: url, to: dest)
        addTeardownBlock { try? FileManager.default.removeItem(at: dest) }
        return dest
    }

    /// Loop a video through VideoRenderer and return bytes physically read
    /// during the measurement window (after a warm-up pass).
    private func measureReads(url: URL, limitBytes: Int64, seconds: TimeInterval) throws -> UInt64 {
        let renderer = VideoRenderer(url: url, muted: true, memoryCacheLimitBytes: limitBytes)
        // Give the layer a size so decoding actually runs.
        renderer.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        renderer.start()
        defer { renderer.tearDown() }

        // Warm up: let the first pass through the file complete.
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        guard let start = DiskIOStats.currentBytesRead() else {
            throw XCTSkip("disk IO counters unavailable")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        guard let end = DiskIOStats.currentBytesRead() else {
            throw XCTSkip("disk IO counters unavailable")
        }
        return end - start
    }

    func testMemoryBackedPlaybackDoesNotReadFromDisk() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WS_DISKIO_TEST"] == "1",
            "set WS_DISKIO_TEST=1 to run the disk-IO measurement"
        )
        let window: TimeInterval = 25

        let diskURL = try sampleVideoURL()
        let diskBytes = try measureReads(url: diskURL, limitBytes: 0, seconds: window)

        let memURL = try sampleVideoURL()
        let memBytes = try measureReads(url: memURL, limitBytes: 200 << 20, seconds: window)

        print("""
        --- VideoRenderer disk IO over \(Int(window))s ---
        disk-backed:   \(DiskIOStats.format(diskBytes))
        memory-backed: \(DiskIOStats.format(memBytes))
        """)

        // The whole point of v0.4.0: looping must not keep hitting the disk.
        XCTAssertLessThan(memBytes, 1 << 20, "memory-backed playback should read ~nothing from disk")
        XCTAssertLessThan(memBytes, max(diskBytes / 4, 1), "memory-backed must read far less than disk-backed")
    }
}
