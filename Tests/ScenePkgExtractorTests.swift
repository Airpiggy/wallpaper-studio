import XCTest
import AppKit
@testable import WallpaperStudio

/// End-to-end: synthetic scene.pkg → PKG parse → TEX decode → PNG on disk.
final class ScenePkgExtractorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-scene-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func rgbaPixels(width: Int, height: Int) -> Data {
        var d = Data()
        for y in 0..<height {
            for x in 0..<width {
                d.append(contentsOf: [UInt8((x * 255) / width), UInt8((y * 255) / height), 128, 255])
            }
        }
        return d
    }

    func testExtractsMainImageViaFallback() throws {
        let tex = TexFixture.rgba(width: 8, height: 8, pixels: rgbaPixels(width: 8, height: 8))
        // scene.json present but empty objects → Plan A yields nil → Plan B picks the tex.
        let sceneJSON = Data(#"{"objects":[]}"#.utf8)
        let pkg = TexFixture.pkg(entries: [
            ("scene.json", sceneJSON),
            ("materials/background.tex", tex),
        ])
        try pkg.write(to: tempDir.appendingPathComponent("scene.pkg"))

        let filename = try ScenePkgExtractor.extract(folder: tempDir)
        let outURL = tempDir.appendingPathComponent(filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))

        let image = try XCTUnwrap(NSImage(contentsOf: outURL))
        XCTAssertEqual(Int(image.size.width), 8)
        XCTAssertEqual(Int(image.size.height), 8)
    }

    func testPicksLargestTexture() throws {
        let small = TexFixture.rgba(width: 4, height: 4, pixels: rgbaPixels(width: 4, height: 4))
        let large = TexFixture.rgba(width: 16, height: 16, pixels: rgbaPixels(width: 16, height: 16))
        let pkg = TexFixture.pkg(entries: [
            ("materials/fx.tex", small),
            ("materials/bg.tex", large),
        ])
        try pkg.write(to: tempDir.appendingPathComponent("scene.pkg"))

        let filename = try ScenePkgExtractor.extract(folder: tempDir)
        let image = try XCTUnwrap(NSImage(contentsOf: tempDir.appendingPathComponent(filename)))
        XCTAssertEqual(Int(image.size.width), 16) // the larger texture won
    }

    func testNoPkgThrows() {
        XCTAssertThrowsError(try ScenePkgExtractor.extract(folder: tempDir))
    }
}
