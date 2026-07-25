import Foundation
import Compression

/// WE texture pixel formats (subset we handle).
enum TexFormat: Int32 {
    case rgba8888 = 0
    case dxt5 = 4
    case dxt3 = 6
    case dxt1 = 7
    case rg88 = 8
    case r8 = 9
}

/// FreeImage container formats used by TEXB0003+ (bytes are a whole image file).
enum FreeImageFormat: Int32 {
    case unknown = -1
    case bmp = 0
    case jpeg = 2
    case png = 13
    case gif = 25
    case mp4 = 35
}

/// Lightweight header info (7 ints after the two magics), read cheaply so the
/// extractor can pick the largest texture without decoding pixels.
struct TexInfo {
    let format: Int32
    let flags: Int32
    let texWidth: Int
    let texHeight: Int
    let imgWidth: Int
    let imgHeight: Int

    static let flagIsGif: Int32 = 4
    var isGif: Bool { (flags & TexInfo.flagIsGif) != 0 }
}

/// The decoded result of a TEX: either a ready-made image file (TEXB0003+ with a
/// FreeImage format) or raw RGBA8888 pixels cropped to the real image size.
enum TEXDecoded {
    case fileBytes(Data, FreeImageFormat)
    case rawRGBA(pixels: [UInt8], width: Int, height: Int)
}

/// Parses the WE `.tex` format.
enum TEXReader {
    /// Read just the header (magics + 7 ints). Throws on bad magic / truncation.
    static func headerOnly(data: Data) throws -> TexInfo {
        var reader = BinaryReader(data)
        try validateMagics(&reader)
        let format = try reader.readInt32()
        let flags = try reader.readInt32()
        let texWidth = Int(try reader.readInt32())
        let texHeight = Int(try reader.readInt32())
        let imgWidth = Int(try reader.readInt32())
        let imgHeight = Int(try reader.readInt32())
        _ = try reader.readUInt32() // unkInt0
        return TexInfo(format: format, flags: flags, texWidth: texWidth, texHeight: texHeight,
                       imgWidth: imgWidth, imgHeight: imgHeight)
    }

    /// Full decode of the first image's first (full-resolution) mipmap.
    static func decode(data: Data) throws -> TEXDecoded {
        var reader = BinaryReader(data)
        try validateMagics(&reader)

        let format = try reader.readInt32()
        _ = try reader.readInt32() // flags
        _ = try reader.readInt32() // texWidth
        _ = try reader.readInt32() // texHeight
        let imgWidth = Int(try reader.readInt32())
        let imgHeight = Int(try reader.readInt32())
        _ = try reader.readUInt32() // unkInt0

        let containerMagic = try reader.readNullTerminatedString()
        guard containerMagic.hasPrefix("TEXB"),
              let version = Int(containerMagic.suffix(4)) else {
            throw PkgParseError.badMagic(containerMagic)
        }

        _ = try reader.readInt32() // imageCount

        var freeImageFormat = FreeImageFormat.unknown
        if version >= 3 {
            let raw = try reader.readInt32()
            freeImageFormat = FreeImageFormat(rawValue: raw) ?? .unknown
        }
        if version == 4 {
            let isVideoMp4 = try reader.readInt32()
            if isVideoMp4 == 1 || freeImageFormat == .mp4 {
                throw PkgParseError.unsupported("视频纹理（mp4）")
            }
        }

        // First image, first mipmap.
        _ = try reader.readInt32() // mipmapCount
        let mipWidth = Int(try reader.readInt32())
        let mipHeight = Int(try reader.readInt32())

        var isLZ4 = false
        var decompressedSize = 0
        if version >= 2 {
            isLZ4 = (try reader.readInt32()) == 1
            decompressedSize = Int(try reader.readInt32())
        }
        let byteCount = Int(try reader.readInt32())
        var payload = try reader.readBytes(byteCount)

        if isLZ4 {
            guard let decompressed = lz4RawDecode(payload, decompressedSize: decompressedSize) else {
                throw PkgParseError.unsupported("LZ4 解压失败")
            }
            payload = decompressed
        }

        // TEXB0003+ with a real image format: bytes are a complete image file.
        if version >= 3, freeImageFormat != .unknown {
            return .fileBytes(payload, freeImageFormat)
        }

        // Raw pixels → RGBA8888 at mip size, then crop to the real image size.
        guard let rgba = decodeRaw(payload, format: format, width: mipWidth, height: mipHeight) else {
            throw PkgParseError.unsupported("纹理格式 \(format)")
        }
        let cropW = min(imgWidth > 0 ? imgWidth : mipWidth, mipWidth)
        let cropH = min(imgHeight > 0 ? imgHeight : mipHeight, mipHeight)
        let cropped = crop(rgba, srcW: mipWidth, srcH: mipHeight, dstW: cropW, dstH: cropH)
        return .rawRGBA(pixels: cropped, width: cropW, height: cropH)
    }

    // MARK: - Internals

    private static func validateMagics(_ reader: inout BinaryReader) throws {
        let m1 = try reader.readNullTerminatedString()
        guard m1 == "TEXV0005" else { throw PkgParseError.badMagic(m1) }
        let m2 = try reader.readNullTerminatedString()
        guard m2 == "TEXI0001" else { throw PkgParseError.badMagic(m2) }
    }

    private static func decodeRaw(_ data: Data, format: Int32, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        switch TexFormat(rawValue: format) {
        case .rgba8888:
            guard data.count >= width * height * 4 else { return nil }
            return [UInt8](data.prefix(width * height * 4))
        case .dxt1:
            return DXTDecoder.decode(data, width: width, height: height, kind: .dxt1)
        case .dxt3:
            return DXTDecoder.decode(data, width: width, height: height, kind: .dxt3)
        case .dxt5:
            return DXTDecoder.decode(data, width: width, height: height, kind: .dxt5)
        case .r8:
            guard data.count >= width * height else { return nil }
            let src = [UInt8](data)
            var out = [UInt8](repeating: 255, count: width * height * 4)
            for i in 0..<(width * height) {
                let v = src[i]
                out[i * 4] = v; out[i * 4 + 1] = v; out[i * 4 + 2] = v
            }
            return out
        case .rg88:
            guard data.count >= width * height * 2 else { return nil }
            let src = [UInt8](data)
            var out = [UInt8](repeating: 255, count: width * height * 4)
            for i in 0..<(width * height) {
                out[i * 4] = src[i * 2]; out[i * 4 + 1] = src[i * 2 + 1]; out[i * 4 + 2] = 0
            }
            return out
        case .none:
            return nil
        }
    }

    /// Top-left crop of an RGBA buffer.
    private static func crop(_ src: [UInt8], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [UInt8] {
        if dstW == srcW && dstH == srcH { return src }
        var out = [UInt8](repeating: 0, count: dstW * dstH * 4)
        for y in 0..<dstH {
            let srcRow = y * srcW * 4
            let dstRow = y * dstW * 4
            for x in 0..<(dstW * 4) {
                out[dstRow + x] = src[srcRow + x]
            }
        }
        return out
    }

    /// Apple Compression raw-LZ4 block decode (matches WE's non-framed LZ4).
    static func lz4RawDecode(_ src: Data, decompressedSize: Int) -> Data? {
        guard decompressedSize > 0 else { return nil }
        var dst = Data(count: decompressedSize)
        let produced = dst.withUnsafeMutableBytes { dstRaw -> Int in
            src.withUnsafeBytes { srcRaw -> Int in
                compression_decode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, decompressedSize,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, src.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard produced == decompressedSize else { return nil }
        return dst
    }
}
