import XCTest
@testable import WallpaperStudio

final class DXTDecoderTests: XCTestCase {
    private func px(_ rgba: [UInt8], _ x: Int, _ y: Int, w: Int = 4) -> [UInt8] {
        let i = (y * w + x) * 4
        return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]]
    }

    func testBC1SolidRed() throws {
        // color0 = color1 = RGB565 pure red (0xF800); all indices 0.
        let block: [UInt8] = [0x00, 0xF8, 0x00, 0xF8, 0x00, 0x00, 0x00, 0x00]
        let out = try XCTUnwrap(DXTDecoder.decode(Data(block), width: 4, height: 4, kind: .dxt1))
        XCTAssertEqual(px(out, 0, 0), [255, 0, 0, 255])
        XCTAssertEqual(px(out, 3, 3), [255, 0, 0, 255])
    }

    func testBC1FourColorMode() throws {
        // color0=0xFFFF (white) > color1=0x0000 (black) → 4-color interpolation.
        // indices first byte 0xE4 → texel0=0,1=1,2=2,3=3.
        let block: [UInt8] = [0xFF, 0xFF, 0x00, 0x00, 0xE4, 0x00, 0x00, 0x00]
        let out = try XCTUnwrap(DXTDecoder.decode(Data(block), width: 4, height: 4, kind: .dxt1))
        XCTAssertEqual(px(out, 0, 0), [255, 255, 255, 255]) // palette 0
        XCTAssertEqual(px(out, 1, 0), [0, 0, 0, 255])       // palette 1
        XCTAssertEqual(px(out, 2, 0)[0], 170)               // (2*255+0)/3
        XCTAssertEqual(px(out, 3, 0)[0], 85)                // (255+0*2)/3
    }

    func testBC1ThreeColorTransparent() throws {
        // color0=0x0000 < color1=0xFFFF → 3-color, palette3 = transparent black.
        let block: [UInt8] = [0x00, 0x00, 0xFF, 0xFF, 0xE4, 0x00, 0x00, 0x00]
        let out = try XCTUnwrap(DXTDecoder.decode(Data(block), width: 4, height: 4, kind: .dxt1))
        XCTAssertEqual(px(out, 0, 0), [0, 0, 0, 255])       // palette 0 black opaque
        XCTAssertEqual(px(out, 1, 0), [255, 255, 255, 255]) // palette 1 white
        XCTAssertEqual(px(out, 3, 0), [0, 0, 0, 0])         // palette 3 transparent
    }

    func testBC3AlphaEndpoints() throws {
        // Alpha block: a0=255, a1=0 (a0>a1). Index stream: texel0=0, texel1=1.
        // Color block: white 4-color, all index 0 → all white.
        let block: [UInt8] = [
            255, 0,                    // alpha0, alpha1
            0x08, 0x00, 0x00, 0x00, 0x00, 0x00, // 48-bit indices: texel1 = 1
            0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // color block (white)
        ]
        let out = try XCTUnwrap(DXTDecoder.decode(Data(block), width: 4, height: 4, kind: .dxt5))
        XCTAssertEqual(px(out, 0, 0)[3], 255) // alpha index 0 → alpha0
        XCTAssertEqual(px(out, 1, 0)[3], 0)   // alpha index 1 → alpha1
        XCTAssertEqual(px(out, 0, 0)[0], 255) // color white
    }
}
