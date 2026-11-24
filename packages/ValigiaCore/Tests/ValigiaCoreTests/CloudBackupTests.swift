import XCTest
@testable import ValigiaCore

final class CloudBackupTests: XCTestCase {
    let rome = TimeZone(identifier: "Europe/Rome")!

    func testNamesEntriesAndPlaceholders() {
        XCTAssertEqual(CloudBackupPlan.dailyName(for: Synthetic.date(2026, 11, 24, 23, 30), timeZone: rome), "Valigia-backup-2026-11-24.zip")
        XCTAssertEqual(CloudBackupPlan.realName(".Valigia-backup-latest.zip.icloud"), "Valigia-backup-latest.zip")
        XCTAssertEqual(CloudBackupPlan.realName("x.zip"), "x.zip")
        let names = ["Valigia-backup-2026-11-20.zip", ".Valigia-backup-2026-11-22.zip.icloud", "Valigia-backup-latest.zip",
                     "Valigia-backup-2026-11-22.zip", "altro.txt", "Tessere-backup-2026-11-21.json", "Valigia-backup-rotto.zip"]
        let entries = CloudBackupPlan.entries(fromFileNames: names, timeZone: rome)
        XCTAssertEqual(entries.map(\.name), ["Valigia-backup-latest.zip", "Valigia-backup-2026-11-22.zip", "Valigia-backup-2026-11-20.zip"])
        XCTAssertTrue(entries[0].isLatest)
    }

    func testPruneKeepsNewest() {
        let names = (1...35).map { String(format: "Valigia-backup-2026-10-%02d.zip", $0 <= 31 ? $0 : 1) } + ["Valigia-backup-latest.zip"]
        let unique = Array(Set(names))
        let prune = CloudBackupPlan.namesToPrune(unique, keep: 30, timeZone: rome)
        XCTAssertEqual(prune, ["Valigia-backup-2026-10-01.zip"])
        XCTAssertTrue(CloudBackupPlan.namesToPrune(["Valigia-backup-latest.zip"], timeZone: rome).isEmpty)
    }

    func testFingerprintChangesWithContentAndAttachmentChoice() {
        var d = Synthetic.data()
        let a = CloudBackupPlan.fingerprint(d, includeAttachments: false)
        XCTAssertEqual(a, CloudBackupPlan.fingerprint(d, includeAttachments: false))
        XCTAssertNotEqual(a, CloudBackupPlan.fingerprint(d, includeAttachments: true))
        d.trips.append(Trip(name: "Nuovo TEST", createdAt: Synthetic.date(2026, 1, 1)))
        XCTAssertNotEqual(a, CloudBackupPlan.fingerprint(d, includeAttachments: false))
        let withFiles = CloudBackupPlan.fingerprint(d, includeAttachments: true)
        d.editItems(at: .always) { $0.update($0[0].id) { $0.attachments = [Attachment(kind: .pdf, fileName: "X.pdf", title: "x", createdAt: Synthetic.date(2026, 1, 1))] } }
        XCTAssertNotEqual(withFiles, CloudBackupPlan.fingerprint(d, includeAttachments: true))
    }

    func testEffectivelyEmpty() {
        var d = ValigiaData()
        d.installSamplesIfNeeded(now: Synthetic.date(2026, 1, 1))
        XCTAssertTrue(d.isEffectivelyEmpty, "fresh install with example templates only")
        var edited = d
        edited.editItems(at: .template(d.templates[0].id), now: Synthetic.date(2026, 1, 2)) { $0.append(Item(name: "Mia TEST")) }
        XCTAssertFalse(edited.isEffectivelyEmpty)
        var withTrip = d
        withTrip.createTrip(TripDraft(name: "V"))
        XCTAssertFalse(withTrip.isEffectivelyEmpty)
        var custom = d
        custom.addTemplate(Luggage(name: "Mio TEST"))
        XCTAssertFalse(custom.isEffectivelyEmpty)
        // Round trip through JSON keeps it empty (dates encoded the same way).
        let raw = try! JSONFileStore<ValigiaData>.encoder().encode(d)
        XCTAssertTrue(try! JSONFileStore<ValigiaData>.decoder.decode(ValigiaData.self, from: raw).isEffectivelyEmpty)
    }

    func testSettingsDefaultsAndPeek() throws {
        let s = ValigiaSettings()
        XCTAssertTrue(s.cloudBackup)
        XCTAssertFalse(s.cloudIncludeAttachments, "attachments (identity documents) not in iCloud unless chosen")
        let old = try JSONFileStore<ValigiaSettings>.decoder.decode(ValigiaSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old, s)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("peek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var d = Synthetic.data()
        d.createTrip(TripDraft(name: "V"), now: Synthetic.date(2026, 1, 1))
        d.editTripAttachments(d.trips[0].id) { $0 = [Attachment(kind: .pdf, fileName: "T.pdf", title: "t", createdAt: Synthetic.date(2026, 1, 1))] }
        try Data([1, 2]).write(to: dir.appendingPathComponent("T.pdf"))
        let zip = dir.appendingPathComponent("b.zip")
        try BackupArchive.write(d, includeAttachments: true, to: zip) { dir.appendingPathComponent($0) }
        XCTAssertEqual(try BackupArchive.peek(zip).data.trips.count, 1)
        XCTAssertEqual(BackupArchive.fileCount(zip), 1)
        let json = dir.appendingPathComponent("b.json")
        try BackupFile(data: d).encoded().write(to: json)
        XCTAssertEqual(try BackupArchive.peek(json).data, d)
        XCTAssertEqual(BackupArchive.fileCount(json), 0)
    }
}
