import XCTest
@testable import ValigiaCore

final class BackupArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("valigia-zip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func sampleData() -> (ValigiaData, [String: Data]) {
        var d = Synthetic.data()
        let pdf = Attachment(kind: .pdf, fileName: "AAA.pdf", title: "Andata TEST", byteSize: 4, createdAt: Synthetic.date(2026, 1, 1))
        let jpg = Attachment(kind: .image, fileName: "BBB.jpg", title: "Foto TEST", byteSize: 3, createdAt: Synthetic.date(2026, 1, 1))
        let id = d.createTrip(TripDraft(name: "V", templateIDs: [d.templates[0].id]), now: Synthetic.date(2026, 2, 1))
        d.editTripAttachments(id) { $0 = [pdf] }
        d.editItems(at: .always) { $0.update($0[0].id) { $0.attachments = [jpg] } }
        return (d, ["AAA.pdf": Data([1, 2, 3, 4]), "BBB.jpg": Data([9, 8, 7])])
    }

    func testZipRoundTripWithAndWithoutAttachments() throws {
        let (data, files) = sampleData()
        let zip = dir.appendingPathComponent("b.zip")
        let src = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        for (n, d) in files { try d.write(to: src.appendingPathComponent(n)) }

        let summary = try BackupArchive.write(data, includeAttachments: true, to: zip, date: Synthetic.date(2026, 3, 1)) { src.appendingPathComponent($0) }
        XCTAssertEqual(summary.files, 2)
        XCTAssertEqual(summary.missingFiles, 0)
        XCTAssertTrue(BackupArchive.isZip(zip))
        var restored: [String: Data] = [:]
        let result = try BackupArchive.read(from: zip) { restored[$0] = $1 }
        XCTAssertEqual(result.data, data)
        XCTAssertEqual(restored, files)
        XCTAssertEqual(result.files, 2)

        // Without attachments: data only.
        let zip2 = dir.appendingPathComponent("b2.zip")
        let s2 = try BackupArchive.write(data, includeAttachments: false, to: zip2) { src.appendingPathComponent($0) }
        XCTAssertEqual(s2.files, 0)
        var r2: [String: Data] = [:]
        XCTAssertEqual(try BackupArchive.read(from: zip2) { r2[$0] = $1 }.data, data)
        XCTAssertTrue(r2.isEmpty)

        // Size estimate close to the real size.
        let size = { (n: String) in files[n]?.count ?? 0 }
        let est = BackupArchive.estimatedSize(of: data, includeAttachments: true, fileSize: size)
        let real = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as! Int
        XCTAssertLessThan(abs(est - real), 200)
        XCTAssertLessThan(BackupArchive.estimatedSize(of: data, includeAttachments: false, fileSize: size), est)
    }

    func testMissingFilesAreCounted() throws {
        let (data, _) = sampleData()
        let zip = dir.appendingPathComponent("m.zip")
        let s = try BackupArchive.write(data, includeAttachments: true, to: zip) { self.dir.appendingPathComponent("nope-\($0)") }
        XCTAssertEqual(s.missingFiles, 2)
        XCTAssertEqual(try BackupArchive.read(from: zip) { _, _ in }.data, data)
    }

    func testOldJSONBackupStillRestores() throws {
        let (data, files) = sampleData()
        let url = dir.appendingPathComponent("old.json")
        try BackupFile(data: data, photos: files).encoded().write(to: url)
        XCTAssertFalse(BackupArchive.isZip(url))
        var restored: [String: Data] = [:]
        let r = try BackupArchive.read(from: url) { restored[$0] = $1 }
        XCTAssertEqual(r.data, data)
        XCTAssertEqual(restored, files)
    }

    func testRejectsZipWithoutDataAndUnsafePaths() throws {
        let zip = dir.appendingPathComponent("x.zip")
        let w = try ZipWriter(url: zip)
        try w.add(Data("ciao".utf8), as: "altro.txt")
        try w.finish()
        XCTAssertThrowsError(try BackupArchive.read(from: zip) { _, _ in }) {
            XCTAssertEqual($0 as? BackupArchive.ArchiveError, .missingData)
        }
        XCTAssertFalse(ZipPath.isSafe("../evil"))
        XCTAssertFalse(ZipPath.isSafe("/abs"))
        XCTAssertTrue(ZipPath.isSafe("Attachments/A.pdf"))
        let w2 = try ZipWriter(url: dir.appendingPathComponent("y.zip"))
        XCTAssertThrowsError(try w2.add(Data(), as: "../x"))
    }

    func testFileNameAndSettingDefault() {
        XCTAssertEqual(BackupArchive.fileName(for: Synthetic.date(2026, 11, 24), calendar: Synthetic.calendar), "valigia-backup-2026-11-24.zip")
        XCTAssertFalse(ValigiaSettings().lockDocuments)
    }

    func testShareTextListsAttachmentTitles() {
        var trip = Trip(name: "V", luggage: [Luggage(name: "Zaino", items: [
            Item(name: "Passaporto TEST", attachments: [Attachment(kind: .pdf, fileName: "P.pdf", title: "Scansione", createdAt: Synthetic.date(2026, 1, 1))])
        ])])
        trip.attachments = [Attachment(kind: .pdf, fileName: "T.pdf", title: "Andata", createdAt: Synthetic.date(2026, 1, 1)),
                            Attachment(kind: .pdf, fileName: "R.pdf", title: "Ritorno", createdAt: Synthetic.date(2026, 1, 1))]
        let text = TextExport.trip(trip)
        XCTAssertTrue(text.contains("📎 Documenti: Andata, Ritorno"))
        XCTAssertTrue(text.contains("☐ Passaporto TEST 📎 Scansione"))
        XCTAssertFalse(TextExport.trip(trip, options: .init(withAttachments: false)).contains("📎"))
    }
}
