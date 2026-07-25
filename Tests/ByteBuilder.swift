import Foundation

/// Little-endian byte builder for constructing synthetic PKG/TEX fixtures in tests.
struct ByteBuilder {
    private(set) var data = Data()

    mutating func int32(_ v: Int32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func uint32(_ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func raw(_ d: Data) { data.append(d) }

    /// int32 length-prefixed UTF-8 (PKG string).
    mutating func lpString(_ s: String) {
        let utf8 = Array(s.utf8)
        int32(Int32(utf8.count))
        bytes(utf8)
    }

    /// Null-terminated ASCII (TEX magic/container token).
    mutating func nullString(_ s: String) {
        bytes(Array(s.utf8))
        bytes([0])
    }
}

/// Fixture builders shared across tests.
enum TexFixture {
    /// A minimal TEXB0002 RGBA8888 texture (no LZ4, no crop).
    static func rgba(width: Int, height: Int, pixels: Data) -> Data {
        var b = ByteBuilder()
        b.nullString("TEXV0005")
        b.nullString("TEXI0001")
        b.int32(0)                       // format RGBA8888
        b.int32(0)                       // flags
        b.int32(Int32(width)); b.int32(Int32(height))   // tex size
        b.int32(Int32(width)); b.int32(Int32(height))   // img size
        b.uint32(0)                      // unk
        b.nullString("TEXB0002")
        b.int32(1)                       // imageCount
        b.int32(1)                       // mipmapCount
        b.int32(Int32(width)); b.int32(Int32(height))
        b.int32(0); b.int32(0)           // isLZ4=0, decompressedSize=0
        b.int32(Int32(pixels.count))
        b.raw(pixels)
        return b.data
    }

    /// A PKG archive wrapping the given named entries.
    static func pkg(entries: [(String, Data)]) -> Data {
        var b = ByteBuilder()
        b.lpString("PKGV0001")
        b.int32(Int32(entries.count))
        var offset = 0
        for (name, data) in entries {
            b.lpString(name)
            b.int32(Int32(offset))
            b.int32(Int32(data.count))
            offset += data.count
        }
        for (_, data) in entries { b.raw(data) }
        return b.data
    }
}
