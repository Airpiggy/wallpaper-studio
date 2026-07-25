import XCTest
@testable import WallpaperStudio

final class WEProjectTests: XCTestCase {
    private func parse(_ json: String) -> WEProject? {
        WEProject.parse(data: Data(json.utf8))
    }

    func testVideoProject() {
        let p = parse(#"{"title":"V","type":"Video","file":"a.mp4","preview":"p.jpg"}"#)
        XCTAssertEqual(p?.title, "V")
        XCTAssertEqual(p?.type, "video")            // lowercased
        XCTAssertEqual(p?.file, "a.mp4")
    }

    func testWebProjectWithLooseProperties() {
        // order-as-string, value-as-string number, min/max present.
        let json = #"""
        {"title":"W","type":"web","file":"index.html",
         "general":{"properties":{
           "speed":{"type":"slider","text":"Speed","value":"1.5","min":0,"max":"3","order":"2"},
           "col":{"type":"color","text":"Color","value":"1 0 0","order":1}
         }}}
        """#
        let p = parse(json)
        XCTAssertEqual(p?.type, "web")
        XCTAssertEqual(p?.properties.count, 2)
        // Sorted by order → col(1) before speed(2).
        XCTAssertEqual(p?.properties.first?.key, "col")
        let speed = p?.properties.first { $0.key == "speed" }
        XCTAssertEqual(speed?.kind, .slider)
        XCTAssertEqual(speed?.defaultValue.doubleValue, 1.5)
        XCTAssertEqual(speed?.max, 3)
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(parse("not json at all"))
    }

    func testMissingTypeClassifiesAsOther() {
        let p = parse(#"{"title":"X"}"#)!
        let (kind, reason) = ImportService.classify(project: p, folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(kind, .other)
        XCTAssertNotNil(reason)
    }

    func testSceneClassifiedUnsupported() {
        let p = parse(#"{"title":"S","type":"scene","file":"scene.pkg"}"#)!
        let (kind, _) = ImportService.classify(project: p, folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(kind, .sceneUnsupported)
        XCTAssertFalse(kind.isSupported)
    }

    func testWebmVideoFlaggedUnsupported() {
        let p = parse(#"{"title":"WM","type":"video","file":"clip.webm"}"#)!
        let (kind, reason) = ImportService.classify(project: p, folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(kind, .video)
        XCTAssertNotNil(reason)     // webm flagged
    }
}
