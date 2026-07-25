import Foundation

/// One file entry inside a WE `.pkg` archive.
struct PKGEntry {
    let path: String
    let offset: Int   // relative to the data section start
    let length: Int
}

/// A parsed WE `.pkg` archive: the entry table plus lazy access to entry bytes.
struct PKGArchive {
    let entries: [PKGEntry]
    private let data: Data
    private let dataStart: Int

    init(entries: [PKGEntry], data: Data, dataStart: Int) {
        self.entries = entries
        self.data = data
        self.dataStart = dataStart
    }

    /// Raw bytes of an entry, or nil if the range is out of bounds.
    func data(for entry: PKGEntry) -> Data? {
        let start = dataStart + entry.offset
        let end = start + entry.length
        guard start >= 0, end <= data.count, start <= end else { return nil }
        return data.subdata(in: start..<end)
    }

    /// First entry whose path matches (case-insensitive), or nil.
    func entry(named name: String) -> PKGEntry? {
        entries.first { $0.path.caseInsensitiveCompare(name) == .orderedSame }
    }

    func data(named name: String) -> Data? {
        entry(named: name).flatMap(data(for:))
    }

    func entries(withExtension ext: String) -> [PKGEntry] {
        entries.filter { ($0.path as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame }
    }
}

/// Parses the WE `.pkg` container format.
///
/// Layout (all integers little-endian):
///   magic      : lpString ("PKGV0001" … any "PKGV*")
///   entryCount : int32
///   entry × N  : path lpString; offset int32; length int32
///   <data section starts here; entry.offset is relative to this position>
enum PKGReader {
    static func read(data: Data) throws -> PKGArchive {
        var reader = BinaryReader(data)

        let magic = try reader.readLPStringI32(maxLength: 64)
        guard magic.hasPrefix("PKGV") else { throw PkgParseError.badMagic(magic) }

        let entryCount = Int(try reader.readInt32())
        guard entryCount >= 0, entryCount < 1_000_000 else { throw PkgParseError.truncated }

        var entries: [PKGEntry] = []
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            let path = try reader.readLPStringI32(maxLength: 4096)
            let offset = Int(try reader.readInt32())
            let length = Int(try reader.readInt32())
            guard offset >= 0, length >= 0 else { throw PkgParseError.truncated }
            entries.append(PKGEntry(path: path, offset: offset, length: length))
        }

        let dataStart = reader.position
        return PKGArchive(entries: entries, data: data, dataStart: dataStart)
    }

    static func read(url: URL) throws -> PKGArchive {
        try read(data: try Data(contentsOf: url))
    }
}
