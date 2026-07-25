import XCTest
import Compression
import AppKit
@testable import WallpaperStudio

final class TEXReaderTests: XCTestCase {

    // MARK: - Fixture builder

    private func makeTex(
        container: String, format: Int32, flags: Int32 = 0,
        texW: Int32, texH: Int32, imgW: Int32, imgH: Int32,
        freeImageFormat: Int32? = nil, isVideoMp4: Int32? = nil,
        mipW: Int32, mipH: Int32, isLZ4: Int32? = nil, decompressedSize: Int32? = nil,
        payload: Data
    ) -> Data {
        let version = Int(container.suffix(4)) ?? 1
        var b = ByteBuilder()
        b.nullString("TEXV0005")
        b.nullString("TEXI0001")
        b.int32(format); b.int32(flags)
        b.int32(texW); b.int32(texH); b.int32(imgW); b.int32(imgH)
        b.uint32(0) // unk
        b.nullString(container)
        b.int32(1) // imageCount
        if version >= 3 { b.int32(freeImageFormat ?? -1) }
        if version == 4 { b.int32(isVideoMp4 ?? 0) }
        b.int32(1) // mipmapCount
        b.int32(mipW); b.int32(mipH)
        if version >= 2 { b.int32(isLZ4 ?? 0); b.int32(decompressedSize ?? 0) }
        b.int32(Int32(payload.count))
        b.raw(payload)
        return b.data
    }

    /// 4×4 RGBA where pixel(x,y) = (x*10, y*10, 0, 255), row-major top-to-bottom.
    private func rgba4x4() -> Data {
        var d = Data()
        for y in 0..<4 {
            for x in 0..<4 {
                d.append(contentsOf: [UInt8(x * 10), UInt8(y * 10), 0, 255])
            }
        }
        return d
    }

    private func lz4RawEncode(_ src: Data) -> Data {
        let bound = src.count + 512
        var dst = Data(count: bound)
        let n = dst.withUnsafeMutableBytes { d in
            src.withUnsafeBytes { s in
                compression_encode_buffer(
                    d.bindMemory(to: UInt8.self).baseAddress!, bound,
                    s.bindMemory(to: UInt8.self).baseAddress!, src.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        return dst.prefix(n)
    }

    // MARK: - Tests

    func testHeaderOnly() throws {
        let tex = makeTex(container: "TEXB0002", format: 0, texW: 4, texH: 4, imgW: 2, imgH: 2,
                          mipW: 4, mipH: 4, isLZ4: 0, decompressedSize: 0, payload: rgba4x4())
        let info = try TEXReader.headerOnly(data: tex)
        XCTAssertEqual(info.imgWidth, 2)
        XCTAssertEqual(info.imgHeight, 2)
        XCTAssertFalse(info.isGif)
    }

    func testRGBA8888WithCrop() throws {
        let tex = makeTex(container: "TEXB0002", format: 0, texW: 4, texH: 4, imgW: 2, imgH: 2,
                          mipW: 4, mipH: 4, isLZ4: 0, decompressedSize: 0, payload: rgba4x4())
        guard case .rawRGBA(let pixels, let w, let h) = try TEXReader.decode(data: tex) else {
            return XCTFail("expected rawRGBA")
        }
        XCTAssertEqual(w, 2); XCTAssertEqual(h, 2)
        // Top-left 2×2 of the source pattern.
        XCTAssertEqual(Array(pixels.prefix(4)), [0, 0, 0, 255])       // (0,0)
        XCTAssertEqual(Array(pixels[4..<8]), [10, 0, 0, 255])         // (1,0)
        XCTAssertEqual(Array(pixels[8..<12]), [0, 10, 0, 255])        // (0,1)
    }

    func testLZ4RoundTrip() throws {
        let raw = rgba4x4()
        let compressed = lz4RawEncode(raw)
        let tex = makeTex(container: "TEXB0002", format: 0, texW: 4, texH: 4, imgW: 4, imgH: 4,
                          mipW: 4, mipH: 4, isLZ4: 1, decompressedSize: Int32(raw.count),
                          payload: compressed)
        guard case .rawRGBA(let pixels, let w, let h) = try TEXReader.decode(data: tex) else {
            return XCTFail("expected rawRGBA")
        }
        XCTAssertEqual(w, 4); XCTAssertEqual(h, 4)
        XCTAssertEqual(pixels, [UInt8](raw))
    }

    func testTEXB0003WrappedPNG() throws {
        // Build a real 2×2 PNG and wrap it as FreeImage PNG (13).
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 8, bitsPerPixel: 32)!
        let png = rep.representation(using: .png, properties: [:])!
        let tex = makeTex(container: "TEXB0003", format: 0, texW: 2, texH: 2, imgW: 2, imgH: 2,
                          freeImageFormat: 13, mipW: 2, mipH: 2, isLZ4: 0, decompressedSize: 0,
                          payload: png)
        guard case .fileBytes(let data, let fmt) = try TEXReader.decode(data: tex) else {
            return XCTFail("expected fileBytes")
        }
        XCTAssertEqual(fmt, .png)
        XCTAssertNotNil(NSImage(data: data))
    }

    func testBadMagicThrows() {
        var b = ByteBuilder()
        b.nullString("TEXV9999")
        b.nullString("TEXI0001")
        XCTAssertThrowsError(try TEXReader.decode(data: b.data))
    }
}
