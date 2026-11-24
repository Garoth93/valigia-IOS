import Foundation

/// Backup as a .zip: `valigia-backup.json` (a `BackupFile` without inline files)
/// plus `Attachments/<file>` for every referenced attachment (optional).
/// Restore also accepts the old single-JSON backups (files as base64).
public enum BackupArchive {
    public static let dataEntry = "valigia-backup.json"
    public static let filesFolder = "Attachments/"

    public struct Summary: Equatable, Sendable {
        public let trips: Int
        public let templates: Int
        public let files: Int
        /// Referenced files not found on disk while writing.
        public let missingFiles: Int
    }

    public enum ArchiveError: Error, LocalizedError, Equatable {
        case missingData

        public var errorDescription: String? {
            switch self {
            case .missingData: return "Lo zip non contiene un backup di Valigia."
            }
        }
    }

    /// Bytes the archive will take (data + files + zip headers), for the export screen.
    public static func estimatedSize(of data: ValigiaData, includeAttachments: Bool, fileSize: (String) -> Int) -> Int {
        let json = (try? BackupFile(data: data).encoded().count) ?? 0
        var total = json + entryOverhead(dataEntry) + 22
        if includeAttachments {
            for name in data.referencedFiles {
                let size = fileSize(name)
                if size > 0 { total += size + entryOverhead(filesFolder + name) }
            }
        }
        return total
    }

    static func entryOverhead(_ name: String) -> Int { 30 + 46 + 2 * name.utf8.count }

    /// Writes the archive. `fileURL` gives where an attachment lives on disk.
    @discardableResult
    public static func write(_ data: ValigiaData, includeAttachments: Bool, to zipURL: URL, date: Date = Date(), fileURL: (String) -> URL) throws -> Summary {
        let writer = try ZipWriter(url: zipURL, date: date)
        let json = try BackupFile(data: data, exportedAt: date).encoded()
        try writer.add(json, as: dataEntry)
        var files = 0, missing = 0
        if includeAttachments {
            for name in data.referencedFiles.sorted() {
                guard ZipPath.isSafe(name), let content = try? Data(contentsOf: fileURL(name)) else {
                    missing += 1
                    continue
                }
                try writer.add(content, as: filesFolder + name)
                files += 1
            }
        }
        try writer.finish()
        return Summary(trips: data.trips.count, templates: data.templates.count, files: files, missingFiles: missing)
    }

    /// True for a ZIP file (starts with "PK\u{3}\u{4}").
    public static func isZip(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 4)) ?? Data()
        return head == Data([0x50, 0x4B, 0x03, 0x04])
    }

    /// Reads a backup (zip or old JSON) and writes its files into `filesFolder`
    /// via `store(name, data)`. Returns the data to restore.
    public static func read(from url: URL, store: (String, Data) -> Void) throws -> (data: ValigiaData, files: Int) {
        if isZip(url) {
            let reader = try ZipReader(url: url)
            guard let entry = reader.entry(named: dataEntry) else { throw ArchiveError.missingData }
            let backup = try BackupFile.decode(try reader.data(for: entry))
            var files = 0
            for e in reader.entries where e.name.hasPrefix(filesFolder) {
                let name = String(e.name.dropFirst(filesFolder.count))
                guard !name.isEmpty, !name.contains("/"), ZipPath.isSafe(name) else { continue }
                store(name, try reader.data(for: e))
                files += 1
            }
            // Files inline (should not happen in zips, but harmless).
            for (name, d) in backup.photoData where ZipPath.isSafe(name) { store(name, d) }
            return (backup.data, files + backup.photos.count)
        }
        let backup = try BackupFile.decode(try Data(contentsOf: url))
        var files = 0
        for (name, d) in backup.photoData where ZipPath.isSafe(name) && !name.contains("/") {
            store(name, d)
            files += 1
        }
        return (backup.data, files)
    }

    /// "valigia-backup-2026-11-24.zip"
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "valigia-backup-%04d-%02d-%02d.zip", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
