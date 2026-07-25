import Foundation

/// Decodes DXT1 (BC1), DXT3 (BC2) and DXT5 (BC3) compressed textures to
/// RGBA8888 (memory order R,G,B,A, non-premultiplied). 4×4 block layout,
/// row-major over ceil(w/4) × ceil(h/4) blocks.
enum DXTDecoder {
    enum Kind { case dxt1, dxt3, dxt5 }

    /// Returns `width * height * 4` bytes of RGBA.
    static func decode(_ data: Data, width: Int, height: Int, kind: Kind) -> [UInt8]? {
        let blockBytes = (kind == .dxt1) ? 8 : 16
        let blocksX = (width + 3) / 4
        let blocksY = (height + 3) / 4
        guard data.count >= blocksX * blocksY * blockBytes else { return nil }

        var out = [UInt8](repeating: 0, count: width * height * 4)
        let bytes = [UInt8](data)

        for by in 0..<blocksY {
            for bx in 0..<blocksX {
                let blockOffset = (by * blocksX + bx) * blockBytes
                var colors = [(UInt8, UInt8, UInt8, UInt8)](repeating: (0, 0, 0, 255), count: 16)

                switch kind {
                case .dxt1:
                    decodeColorBlock(bytes, blockOffset, into: &colors, dxt1Alpha: true)
                case .dxt3:
                    decodeColorBlock(bytes, blockOffset + 8, into: &colors, dxt1Alpha: false)
                    decodeDXT3Alpha(bytes, blockOffset, into: &colors)
                case .dxt5:
                    decodeColorBlock(bytes, blockOffset + 8, into: &colors, dxt1Alpha: false)
                    decodeDXT5Alpha(bytes, blockOffset, into: &colors)
                }

                for py in 0..<4 {
                    let y = by * 4 + py
                    guard y < height else { continue }
                    for px in 0..<4 {
                        let x = bx * 4 + px
                        guard x < width else { continue }
                        let c = colors[py * 4 + px]
                        let idx = (y * width + x) * 4
                        out[idx] = c.0; out[idx + 1] = c.1; out[idx + 2] = c.2; out[idx + 3] = c.3
                    }
                }
            }
        }
        return out
    }

    // MARK: - Color block (BC1 body, shared by all three)

    private static func decodeColorBlock(
        _ bytes: [UInt8], _ off: Int,
        into colors: inout [(UInt8, UInt8, UInt8, UInt8)], dxt1Alpha: Bool
    ) {
        let c0 = UInt16(bytes[off]) | (UInt16(bytes[off + 1]) << 8)
        let c1 = UInt16(bytes[off + 2]) | (UInt16(bytes[off + 3]) << 8)
        let indices = UInt32(bytes[off + 4]) | (UInt32(bytes[off + 5]) << 8)
            | (UInt32(bytes[off + 6]) << 16) | (UInt32(bytes[off + 7]) << 24)

        let (r0, g0, b0) = rgb565(c0)
        let (r1, g1, b1) = rgb565(c1)

        var palette = [(UInt8, UInt8, UInt8, UInt8)](repeating: (0, 0, 0, 255), count: 4)
        palette[0] = (r0, g0, b0, 255)
        palette[1] = (r1, g1, b1, 255)
        if c0 > c1 || !dxt1Alpha {
            palette[2] = (mix(r0, r1, 2, 1), mix(g0, g1, 2, 1), mix(b0, b1, 2, 1), 255)
            palette[3] = (mix(r0, r1, 1, 2), mix(g0, g1, 1, 2), mix(b0, b1, 1, 2), 255)
        } else {
            palette[2] = (avg(r0, r1), avg(g0, g1), avg(b0, b1), 255)
            palette[3] = (0, 0, 0, 0) // transparent black
        }

        for i in 0..<16 {
            let sel = Int((indices >> (UInt32(i) * 2)) & 0x3)
            colors[i] = palette[sel]
        }
    }

    // MARK: - DXT3 explicit 4-bit alpha

    private static func decodeDXT3Alpha(
        _ bytes: [UInt8], _ off: Int,
        into colors: inout [(UInt8, UInt8, UInt8, UInt8)]
    ) {
        for i in 0..<16 {
            let byte = bytes[off + i / 2]
            let nibble = (i % 2 == 0) ? (byte & 0x0F) : (byte >> 4)
            let a = (nibble << 4) | nibble
            colors[i].3 = a
        }
    }

    // MARK: - DXT5 interpolated alpha

    private static func decodeDXT5Alpha(
        _ bytes: [UInt8], _ off: Int,
        into colors: inout [(UInt8, UInt8, UInt8, UInt8)]
    ) {
        let a0 = bytes[off]
        let a1 = bytes[off + 1]
        var alpha = [UInt8](repeating: 0, count: 8)
        alpha[0] = a0
        alpha[1] = a1
        if a0 > a1 {
            for i in 1...6 {
                alpha[i + 1] = UInt8((Int(a0) * (7 - i) + Int(a1) * i) / 7)
            }
        } else {
            for i in 1...4 {
                alpha[i + 1] = UInt8((Int(a0) * (5 - i) + Int(a1) * i) / 5)
            }
            alpha[6] = 0
            alpha[7] = 255
        }

        // 48-bit little-endian stream of 3-bit indices.
        var bits: UInt64 = 0
        for i in 0..<6 {
            bits |= UInt64(bytes[off + 2 + i]) << (UInt64(i) * 8)
        }
        for i in 0..<16 {
            let sel = Int((bits >> (UInt64(i) * 3)) & 0x7)
            colors[i].3 = alpha[sel]
        }
    }

    // MARK: - Helpers

    private static func rgb565(_ c: UInt16) -> (UInt8, UInt8, UInt8) {
        let r5 = UInt8((c >> 11) & 0x1F)
        let g6 = UInt8((c >> 5) & 0x3F)
        let b5 = UInt8(c & 0x1F)
        let r = (r5 << 3) | (r5 >> 2)
        let g = (g6 << 2) | (g6 >> 4)
        let b = (b5 << 3) | (b5 >> 2)
        return (r, g, b)
    }

    private static func mix(_ a: UInt8, _ b: UInt8, _ wa: Int, _ wb: Int) -> UInt8 {
        UInt8((Int(a) * wa + Int(b) * wb) / (wa + wb))
    }

    private static func avg(_ a: UInt8, _ b: UInt8) -> UInt8 {
        UInt8((Int(a) + Int(b)) / 2)
    }
}
