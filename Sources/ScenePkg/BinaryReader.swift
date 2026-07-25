import Foundation

/// Errors thrown while parsing WE binary containers.
enum PkgParseError: LocalizedError {
    case truncated
    case badMagic(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .truncated: return "文件数据不完整或已损坏"
        case .badMagic(let m): return "无法识别的格式标识：\(m)"
        case .unsupported(let s): return "暂不支持：\(s)"
        }
    }
}

/// A little-endian forward cursor over `Data`. Every read is bounds-checked and
/// throws `PkgParseError.truncated` on overrun.
struct BinaryReader {
    private let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }
    var position: Int { offset }

    mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= data.count else { throw PkgParseError.truncated }
        offset = newOffset
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw PkgParseError.truncated }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw PkgParseError.truncated }
        let v = data[data.startIndex + offset]
        offset += 1
        return v
    }

    mutating func readInt32() throws -> Int32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { raw in
            Int32(littleEndian: raw.loadUnaligned(as: Int32.self))
        }
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(as: UInt32.self))
        }
    }

    mutating func readFloat() throws -> Float {
        let bits = try readUInt32()
        return Float(bitPattern: bits)
    }

    /// Length-prefixed UTF-8 string: int32 byte count followed by the bytes.
    /// Used by the PKG container. `maxLength` guards against corrupt lengths.
    mutating func readLPStringI32(maxLength: Int = 4096) throws -> String {
        let count = Int(try readInt32())
        guard count >= 0, count <= maxLength else { throw PkgParseError.truncated }
        let bytes = try readBytes(count)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Null-terminated ASCII string. Reads bytes up to and including the null
    /// terminator (consumed but not returned). Used by TEX magic/container tokens
    /// like "TEXV0005\0". `maxBytes` guards against a missing terminator.
    mutating func readNullTerminatedString(maxBytes: Int = 64) throws -> String {
        var bytes: [UInt8] = []
        for _ in 0..<maxBytes {
            let b = try readUInt8()
            if b == 0 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(b)
        }
        throw PkgParseError.truncated
    }
}
