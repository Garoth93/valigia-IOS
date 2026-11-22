import Foundation

/// Minimal JSON persistence for any `Codable` value.
/// Used by the app to save its state in Application Support; used by
/// tests with a temporary directory. Works on Linux.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL
    /// Compact output for big files (the visit history), pretty for small ones.
    public let compact: Bool

    public init(url: URL, compact: Bool = false) {
        self.url = url
        self.compact = compact
    }

    /// Copy of the previous good file, kept next to the main one.
    public var backupURL: URL { url.appendingPathExtension("bak") }

    /// Returns `nil` when the file does not exist yet.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(Value.self, from: data)
    }

    /// Loads the backup copy written by `save(_:keepBackup:)`, if any.
    public func loadBackup() throws -> Value? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        let data = try Data(contentsOf: backupURL)
        return try Self.decoder.decode(Value.self, from: data)
    }

    /// Writes atomically, creating the parent directory if needed.
    /// With `keepBackup` the previous file is first copied to `backupURL`,
    /// so a crash or a bad write never loses the last good state.
    public func save(_ value: Value, keepBackup: Bool = false) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder(compact: compact).encode(value)
        if keepBackup, fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    public static func encoder(compact: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
