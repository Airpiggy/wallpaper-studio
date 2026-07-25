import XCTest
@testable import WallpaperStudio

@MainActor
final class DisplayAssignmentTests: XCTestCase {
    private let itemA = UUID()
    private let itemB = UUID()
    private let d1 = "display-1"
    private let d2 = "display-2"

    private func needing(
        connected: [String], assignments: [String: UUID],
        current: UUID?, sync: Bool
    ) -> [String] {
        AppState.displaysNeedingAssignment(
            connected: connected, assignments: assignments,
            currentItemID: current, sameOnAllDisplays: sync
        )
    }

    func testSyncNewDisplayNeedsAssignment() {
        // d1 has the wallpaper, d2 (newly connected) has none.
        let result = needing(connected: [d1, d2], assignments: [d1: itemA], current: itemA, sync: true)
        XCTAssertEqual(result, [d2])
    }

    func testSyncAllConsistentNeedsNothing() {
        let result = needing(connected: [d1, d2], assignments: [d1: itemA, d2: itemA], current: itemA, sync: true)
        XCTAssertTrue(result.isEmpty)
    }

    func testSyncStaleAssignmentGetsCovered() {
        // d2 shows a different wallpaper than the current one → must be updated.
        let result = needing(connected: [d1, d2], assignments: [d1: itemA, d2: itemB], current: itemA, sync: true)
        XCTAssertEqual(result, [d2])
    }

    func testIndependentOnlyUnassignedDisplays() {
        // d2 has no assignment → gets the fallback; d1 keeps its own (not returned).
        let result = needing(connected: [d1, d2], assignments: [d1: itemB], current: itemB, sync: false)
        XCTAssertEqual(result, [d2])
    }

    func testIndependentAllAssignedNeedsNothing() {
        let result = needing(connected: [d1, d2], assignments: [d1: itemA, d2: itemB], current: itemA, sync: false)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoCurrentWallpaperNeedsNothing() {
        let result = needing(connected: [d1, d2], assignments: [:], current: nil, sync: true)
        XCTAssertTrue(result.isEmpty)
    }

    func testNoConnectedDisplaysNeedsNothing() {
        let result = needing(connected: [], assignments: [d1: itemA], current: itemA, sync: true)
        XCTAssertTrue(result.isEmpty)
    }
}
