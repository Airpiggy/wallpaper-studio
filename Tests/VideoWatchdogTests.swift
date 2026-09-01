import AVFoundation
import XCTest
@testable import WallpaperStudio

/// Covers the stall watchdog that revives video playback after the Mac sleeps:
/// the pipeline can come back wedged, advancing no further and reporting no
/// error, so detection is by absence of progress rather than by any failure.
@MainActor
final class VideoWatchdogTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - Stall detection

    func testProgressingPlaybackIsNotStalled() {
        let recent = now.addingTimeInterval(-1)
        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: recent, now: now, wantsPlayback: true
        ))
    }

    func testNoProgressBeyondToleranceIsStalled() {
        let stale = now.addingTimeInterval(-(VideoRenderer.stallTolerance + 1))
        XCTAssertTrue(VideoRenderer.isStalled(
            lastHeartbeat: stale, now: now, wantsPlayback: true
        ))
    }

    func testToleranceBoundaryIsNotYetStalled() {
        let edge = now.addingTimeInterval(-VideoRenderer.stallTolerance)
        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: edge, now: now, wantsPlayback: true
        ), "the tolerance itself must not count as a stall")
    }

    /// A deliberately paused wallpaper stops beating; treating that as a stall
    /// would fight the power-saving policy and restart playback behind its back.
    func testPausedPlaybackIsNeverStalled() {
        let ancient = now.addingTimeInterval(-3600)
        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: ancient, now: now, wantsPlayback: false
        ))
    }

    // MARK: - Recovery ladder

    func testLadderEscalatesWhenMemoryBacked() {
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 0, usingMemory: true), .kick)
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 1, usingMemory: true), .rebuild(fromDisk: false))
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 2, usingMemory: true), .rebuild(fromDisk: true))
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 3, usingMemory: true), .giveUp)
    }

    /// Disk-backed playback has no alternate source, so the disk rung is skipped.
    func testLadderSkipsDiskRungWhenAlreadyOnDisk() {
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 0, usingMemory: false), .kick)
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 1, usingMemory: false), .rebuild(fromDisk: false))
        XCTAssertEqual(VideoRenderer.recoveryAction(forAttempt: 2, usingMemory: false), .giveUp)
    }

    func testLadderStaysAtGiveUp() {
        for attempt in 3...10 {
            XCTAssertEqual(
                VideoRenderer.recoveryAction(forAttempt: attempt, usingMemory: true), .giveUp,
                "attempt \(attempt) must not restart the ladder"
            )
        }
    }

    // MARK: - End to end

    private func sampleVideoURL() throws -> URL {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Fixtures/SampleVideo/sample.mp4"),
            Bundle(for: VideoWatchdogTests.self).url(forResource: "sample", withExtension: "mp4"),
        ]
        guard let url = candidates.compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("sample.mp4 fixture not found")
        }
        return url
    }

    /// The watchdog is only useful if a supervised renderer actually advances,
    /// and if the heartbeat it depends on keeps the ladder at rest.
    func testSupervisedPlaybackAdvances() throws {
        let renderer = VideoRenderer(url: try sampleVideoURL(), muted: true, memoryCacheLimitBytes: 200 << 20)
        renderer.view.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        renderer.start()
        defer { renderer.tearDown() }

        RunLoop.current.run(until: Date().addingTimeInterval(3))

        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: renderer.lastHeartbeatForTesting, now: Date(), wantsPlayback: true
        ), "playback should have beaten within the tolerance")
        XCTAssertEqual(renderer.recoveryAttemptForTesting, 0, "healthy playback must not trigger recovery")
    }

    /// Rebuilding is the ladder's main weapon; it has to leave a playing player.
    func testRebuildResumesPlayback() throws {
        let renderer = VideoRenderer(url: try sampleVideoURL(), muted: true, memoryCacheLimitBytes: 200 << 20)
        renderer.view.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        renderer.start()
        defer { renderer.tearDown() }
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        renderer.rebuildForTesting(fromDisk: true)
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: renderer.lastHeartbeatForTesting, now: Date(), wantsPlayback: true
        ), "playback should have resumed after the rebuild")
        XCTAssertFalse(renderer.usesMemoryAssetForTesting, "disk rebuild must drop the memory source")
    }

    /// The whole point of v0.4.2: a player wedged behind the policy layer's back
    /// must be noticed and revived without anyone touching the app.
    func testWedgedPlaybackIsDetectedAndRecovered() throws {
        let renderer = VideoRenderer(url: try sampleVideoURL(), muted: true, memoryCacheLimitBytes: 200 << 20)
        renderer.view.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        renderer.start()
        defer { renderer.tearDown() }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertEqual(renderer.recoveryAttemptForTesting, 0)

        renderer.simulateStallForTesting()
        XCTAssertTrue(VideoRenderer.isStalled(
            lastHeartbeat: renderer.lastHeartbeatForTesting, now: Date(), wantsPlayback: true
        ), "the simulated wedge should read as stalled")

        renderer.checkForStallForTesting()
        XCTAssertEqual(renderer.recoveryAttemptForTesting, 1, "the stall should have been acted on")

        // The first rung is a kick; playback should be beating again shortly.
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(VideoRenderer.isStalled(
            lastHeartbeat: renderer.lastHeartbeatForTesting, now: Date(), wantsPlayback: true
        ), "recovery should have restored playback")
    }

    /// Pausing must stand down the watchdog, or the policy layer's power saving
    /// would be undone a few seconds later.
    func testPauseStopsSupervision() throws {
        let renderer = VideoRenderer(url: try sampleVideoURL(), muted: true, memoryCacheLimitBytes: 0)
        renderer.view.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        renderer.start()
        defer { renderer.tearDown() }
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        renderer.pause()
        XCTAssertFalse(renderer.isSupervisingForTesting, "paused playback must not be supervised")

        renderer.resume()
        XCTAssertTrue(renderer.isSupervisingForTesting, "resuming must restore supervision")
    }
}
