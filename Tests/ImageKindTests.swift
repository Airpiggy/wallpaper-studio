import XCTest
@testable import WallpaperStudio

final class ImageKindTests: XCTestCase {
    private func classify(_ json: String) -> (WallpaperKind, String?) {
        let p = WEProject.parse(data: Data(json.utf8))!
        return ImportService.classify(project: p, folder: URL(fileURLWithPath: "/tmp"))
    }

    func testExplicitImageType() {
        let (kind, reason) = classify(#"{"title":"I","type":"image","file":"a.png"}"#)
        XCTAssertEqual(kind, .image)
        XCTAssertNil(reason)
        XCTAssertTrue(kind.isSupported)
    }

    func testExtensionFallbackWithEmptyType() {
        let (kind, _) = classify(#"{"title":"W","file":"bg.webp"}"#)
        XCTAssertEqual(kind, .image)
    }

    func testExtensionFallbackGif() {
        let (kind, _) = classify(#"{"title":"G","type":"","file":"loop.gif"}"#)
        XCTAssertEqual(kind, .image)
    }

    func testSceneStillUnsupportedBeforeExtraction() {
        let (kind, _) = classify(#"{"title":"S","type":"scene","file":"scene.pkg"}"#)
        XCTAssertEqual(kind, .sceneUnsupported)
        XCTAssertFalse(kind.isSupported)
    }

    func testUnknownNonImageStaysOther() {
        let (kind, _) = classify(#"{"title":"A","type":"application","file":"a.exe"}"#)
        XCTAssertEqual(kind, .other)
    }
}
