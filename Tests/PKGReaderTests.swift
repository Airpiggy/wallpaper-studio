import XCTest
@testable import WallpaperStudio

final class PKGReaderTests: XCTestCase {
    /// Build a synthetic pkg with two entries (one nested path).
    private func makePkg(magic: String) -> (Data, payloadA: Data, payloadB: Data) {
        let payloadA = Data("scene-json-bytes".utf8)
        let payloadB = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        var b = ByteBuilder()
        b.lpString(magic)
        b.int32(2) // entryCount
        // entry 0
        b.lpString("scene.json")
        b.int32(0)                    // offset
        b.int32(Int32(payloadA.count))
        // entry 1 (nested)
        b.lpString("materials/bg.tex")
        b.int32(Int32(payloadA.count)) // offset right after A
        b.int32(Int32(payloadB.count))
        // data section
        b.raw(payloadA)
        b.raw(payloadB)
        return (b.data, payloadA, payloadB)
    }

    func testParsesEntriesAndData() throws {
        let (data, payloadA, payloadB) = makePkg(magic: "PKGV0001")
        let archive = try PKGReader.read(data: data)

        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(archive.entries[0].path, "scene.json")
        XCTAssertEqual(archive.entries[1].path, "materials/bg.tex")
        XCTAssertEqual(archive.data(named: "scene.json"), payloadA)
        XCTAssertEqual(archive.data(named: "materials/bg.tex"), payloadB)
    }

    func testAcceptsAnyPKGVVersion() throws {
        let (data, _, _) = makePkg(magic: "PKGV9999")
        let archive = try PKGReader.read(data: data)
        XCTAssertEqual(archive.entries.count, 2)
    }

    func testEntriesWithExtension() throws {
        let (data, _, _) = makePkg(magic: "PKGV0001")
        let archive = try PKGReader.read(data: data)
        XCTAssertEqual(archive.entries(withExtension: "tex").count, 1)
    }

    func testBadMagicThrows() {
        var b = ByteBuilder()
        b.lpString("ZIPV0001")
        b.int32(0)
        XCTAssertThrowsError(try PKGReader.read(data: b.data))
    }

    func testTruncatedTableThrows() {
        // Cut inside the entry table (30 bytes lands mid second entry path),
        // so header parsing hits the end of data.
        let (data, _, _) = makePkg(magic: "PKGV0001")
        XCTAssertThrowsError(try PKGReader.read(data: Data(data.prefix(30))))
    }

    func testTruncatedDataSectionIsLazy() throws {
        // Truncating only the data section is not a parse error — entry data
        // simply resolves to nil.
        let (data, _, _) = makePkg(magic: "PKGV0001")
        let archive = try PKGReader.read(data: Data(data.prefix(data.count - 3)))
        XCTAssertNil(archive.data(named: "materials/bg.tex"))
    }
}
