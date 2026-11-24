import Foundation

/// Automatic backups in iCloud Drive: shared container `iCloud.com.garoth93.backup`
/// (same as Tessere and Cresta), sub-folder "Valigia", visible in the Files app as
/// iCloud Drive › Backup › Valigia.
///
/// Files: `Valigia-backup-yyyy-MM-dd.zip` (one per day, overwritten during the
/// day, the last `keepDaily` kept) plus `Valigia-backup-latest.zip`, written
/// with `BackupArchive`. Attachments go in only if the user turned them on.
public enum CloudBackupPlan {
    public static let containerID = "iCloud.com.garoth93.backup"
    public static let folderName = "Valigia"
    public static let prefix = "Valigia-backup-"
    public static let latestName = "Valigia-backup-latest.zip"
    public static let keepDaily = 30

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        /// Day of the backup (nil for "latest").
        public var day: Date?
        public var isLatest: Bool { day == nil }
    }

    private static func dayFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func dailyName(for date: Date, timeZone: TimeZone = .current) -> String {
        "\(prefix)\(dayFormatter(timeZone).string(from: date)).zip"
    }

    /// iCloud placeholder of a file not downloaded yet: ".name.zip.icloud".
    public static func realName(_ fileName: String) -> String {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return fileName }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    /// Backups found in the folder, newest first ("latest" on top).
    public static func entries(fromFileNames names: [String], timeZone: TimeZone = .current) -> [Entry] {
        let f = dayFormatter(timeZone)
        var latest: Entry?
        var daily: [Entry] = []
        for raw in Set(names.map(realName)) {
            if raw == latestName {
                latest = Entry(name: raw, day: nil)
            } else if raw.hasPrefix(prefix), raw.hasSuffix(".zip") {
                let stamp = String(raw.dropFirst(prefix.count).dropLast(4))
                if let d = f.date(from: stamp) { daily.append(Entry(name: raw, day: d)) }
            }
        }
        daily.sort { $0.day! > $1.day! }
        return (latest.map { [$0] } ?? []) + daily
    }

    /// Daily files beyond the newest `keep`.
    public static func namesToPrune(_ names: [String], keep: Int = keepDaily, timeZone: TimeZone = .current) -> [String] {
        let daily = entries(fromFileNames: names, timeZone: timeZone).filter { !$0.isLatest }
        return daily.count > keep ? daily[keep...].map(\.name) : []
    }

    /// Fingerprint of what a backup would contain (data, files, attachments on/off),
    /// not of when: unchanged = no new upload needed. Files never change content,
    /// so their names are enough.
    public static func fingerprint(_ data: ValigiaData, includeAttachments: Bool) -> String {
        guard var bytes = try? JSONFileStore<ValigiaData>.encoder(compact: true).encode(data) else { return "" }
        bytes.append(includeAttachments ? 1 : 0)
        if includeAttachments {
            bytes.append(contentsOf: Array(data.referencedFiles.sorted().joined(separator: "|").utf8))
        }
        var h: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16) + "-" + String(bytes.count)
    }
}

public extension ValigiaData {
    /// Nothing of the user's yet: no trips, only untouched example templates,
    /// no attachments. An empty app never overwrites a backup and may offer to restore one.
    var isEffectivelyEmpty: Bool {
        trips.isEmpty
            && templates.allSatisfy { $0.isSample && $0.updatedAt == $0.createdAt && $0.usageCount == 0 }
            && referencedFiles.isEmpty
    }
}

public extension BackupArchive {
    /// Reads only the data of a backup (zip or JSON), without its files: for previews.
    static func peek(_ url: URL) throws -> BackupFile {
        if isZip(url) {
            let reader = try ZipReader(url: url)
            guard let entry = reader.entry(named: dataEntry) else { throw ArchiveError.missingData }
            return try BackupFile.decode(try reader.data(for: entry))
        }
        return try BackupFile.decode(try Data(contentsOf: url))
    }

    /// Number of attachment files inside a zip backup.
    static func fileCount(_ url: URL) -> Int {
        guard isZip(url), let reader = try? ZipReader(url: url) else { return 0 }
        return reader.entries.filter { $0.name.hasPrefix(filesFolder) }.count
    }
}
