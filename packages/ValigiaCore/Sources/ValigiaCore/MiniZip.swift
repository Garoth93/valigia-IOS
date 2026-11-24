import Foundation

/// CRC-32 (IEEE) used by ZIP.
public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: Data, initial: UInt32 = 0) -> UInt32 {
        var c = ~initial
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return ~c
    }
}

public enum ZipError: Error, Equatable {
    case notAZip
    case tooLarge
    case unsupportedCompression(UInt16)
    case corrupted(String)
    case unsafePath(String)
    case crcMismatch(String)
}

public struct ZipEntry: Equatable, Sendable {
    public let name: String
    public let size: Int
    public let crc: UInt32
    public let method: UInt16
    let localHeaderOffset: Int
}

/// Minimal ZIP writer, STORE method only (JPEG/PDF are already compressed:
/// deflate would gain little). From Diario Sonoro's MiniZip. Streams to disk, one file at a time.
/// No ZIP64: up to 65 535 files and 4 GB.
public final class ZipWriter {
    private let handle: FileHandle
    private var central = Data()
    private var count = 0
    private var offset = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    public init(url: URL, date: Date = Date()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: nil) else { throw ZipError.corrupted("create") }
        handle = try FileHandle(forWritingTo: url)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let date: Int = (year << 9) | (month << 5) | day
        dosTime = UInt16(truncatingIfNeeded: time)
        dosDate = UInt16(truncatingIfNeeded: date)
    }

    public func add(_ data: Data, as name: String) throws {
        guard ZipPath.isSafe(name) else { throw ZipError.unsafePath(name) }
        guard data.count < Int(UInt32.max), offset < Int(UInt32.max), count < 65_535 else { throw ZipError.tooLarge }
        let nameData = Data(name.utf8)
        let crc = CRC32.checksum(data)
        var local = Data()
        local.le32(0x0403_4B50)
        local.le16(20)          // version needed
        local.le16(0x0800)      // UTF-8 names
        local.le16(0)           // stored
        local.le16(dosTime)
        local.le16(dosDate)
        local.le32(crc)
        local.le32(UInt32(data.count))
        local.le32(UInt32(data.count))
        local.le16(UInt16(nameData.count))
        local.le16(0)
        local.append(nameData)

        var cd = Data()
        cd.le32(0x0201_4B50)
        cd.le16(20)
        cd.le16(20)
        cd.le16(0x0800)
        cd.le16(0)
        cd.le16(dosTime)
        cd.le16(dosDate)
        cd.le32(crc)
        cd.le32(UInt32(data.count))
        cd.le32(UInt32(data.count))
        cd.le16(UInt16(nameData.count))
        cd.le16(0)              // extra
        cd.le16(0)              // comment
        cd.le16(0)              // disk
        cd.le16(0)              // internal attrs
        cd.le32(0)              // external attrs
        cd.le32(UInt32(offset))
        cd.append(nameData)
        central.append(cd)

        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)
        offset += local.count + data.count
        count += 1
    }

    public func addFile(at url: URL, as name: String) throws {
        try add(try Data(contentsOf: url), as: name)
    }

    public func finish() throws {
        guard offset + central.count < Int(UInt32.max) else { throw ZipError.tooLarge }
        var end = Data()
        end.le32(0x0605_4B50)
        end.le16(0)
        end.le16(0)
        end.le16(UInt16(count))
        end.le16(UInt16(count))
        end.le32(UInt32(central.count))
        end.le32(UInt32(offset))
        end.le16(0)
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.close()
    }

    public var entryCount: Int { count }
}

/// Reads ZIP files written by `ZipWriter` (stored entries; deflated entries
/// are listed but cannot be extracted).
public final class ZipReader {
    public let entries: [ZipEntry]
    private let url: URL

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        guard size >= 22 else { throw ZipError.notAZip }
        let tail = min(size, 65_535 + 22)
        try handle.seek(toOffset: UInt64(size - tail))
        let buf = try handle.read(upToCount: tail) ?? Data()
        let bytes = [UInt8](buf)
        guard let eocd = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
            bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 0x05 && bytes[$0 + 3] == 0x06
        }) else { throw ZipError.notAZip }
        let total = Int(bytes.u16(eocd + 10))
        let cdSize = Int(bytes.u32(eocd + 12))
        let cdOffset = Int(bytes.u32(eocd + 16))
        guard cdOffset + cdSize <= size else { throw ZipError.corrupted("central directory") }
        try handle.seek(toOffset: UInt64(cdOffset))
        let cd = [UInt8](try handle.read(upToCount: cdSize) ?? Data())
        var list: [ZipEntry] = []
        var p = 0
        for _ in 0..<total {
            guard p + 46 <= cd.count, cd.u32(p) == 0x0201_4B50 else { throw ZipError.corrupted("entry header") }
            let method = cd.u16(p + 10)
            let crc = cd.u32(p + 16)
            let usize = Int(cd.u32(p + 24))
            let nlen = Int(cd.u16(p + 28)), xlen = Int(cd.u16(p + 30)), clen = Int(cd.u16(p + 32))
            let local = Int(cd.u32(p + 42))
            guard p + 46 + nlen <= cd.count else { throw ZipError.corrupted("entry name") }
            let name = String(decoding: cd[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            list.append(ZipEntry(name: name, size: usize, crc: crc, method: method, localHeaderOffset: local))
            p += 46 + nlen + xlen + clen
        }
        entries = list
    }

    public func entry(named name: String) -> ZipEntry? { entries.first { $0.name == name } }

    public func data(for entry: ZipEntry) throws -> Data {
        guard entry.method == 0 else { throw ZipError.unsupportedCompression(entry.method) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(entry.localHeaderOffset))
        let header = [UInt8](try handle.read(upToCount: 30) ?? Data())
        guard header.count == 30, header.u32(0) == 0x0403_4B50 else { throw ZipError.corrupted(entry.name) }
        let skip = Int(header.u16(26)) + Int(header.u16(28))
        try handle.seek(toOffset: UInt64(entry.localHeaderOffset + 30 + skip))
        let data = try handle.read(upToCount: entry.size) ?? Data()
        guard data.count == entry.size else { throw ZipError.corrupted(entry.name) }
        guard CRC32.checksum(data) == entry.crc else { throw ZipError.crcMismatch(entry.name) }
        return data
    }

    /// Extracts into `folder/<entry name>`; refuses names escaping the folder.
    public func extract(_ entry: ZipEntry, into folder: URL) throws -> URL {
        guard ZipPath.isSafe(entry.name) else { throw ZipError.unsafePath(entry.name) }
        let out = folder.appendingPathComponent(entry.name)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data(for: entry).write(to: out, options: .atomic)
        return out
    }
}

extension Data {
    mutating func le16(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }

    mutating func le32(_ v: UInt32) {
        for i in 0..<4 { append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }
}

extension Array where Element == UInt8 {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

/// Relative paths allowed inside a backup archive (no "..", no absolute paths).
public enum ZipPath {
    public static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}
