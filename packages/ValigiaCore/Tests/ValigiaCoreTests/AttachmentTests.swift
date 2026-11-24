import XCTest
@testable import ValigiaCore

final class AttachmentTests: XCTestCase {
    private func att(_ name: String, _ kind: AttachmentKind = .pdf, size: Int = 100) -> Attachment {
        Attachment(kind: kind, fileName: name, title: (name as NSString).deletingPathExtension, originalName: name, byteSize: size, createdAt: Synthetic.date(2026, 1, 1))
    }

    func testLegacyPhotoMigratesToFirstAttachment() throws {
        let json = #"{"name":"Passaporto TEST","photoFile":"OLD.jpg"}"#
        let item = try JSONFileStore<Item>.decoder.decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.attachments.count, 1)
        XCTAssertEqual(item.attachments[0].fileName, "OLD.jpg")
        XCTAssertEqual(item.attachments[0].kind, .image)
        // Re-encoded without photoFile, decoded again without duplicates.
        let raw = try JSONFileStore<Item>.encoder().encode(item)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("photoFile"))
        let again = try JSONFileStore<Item>.decoder.decode(Item.self, from: raw)
        XCTAssertEqual(again, item)
        // Both present (half-migrated file): no duplicate.
        let both = #"{"name":"x","photoFile":"A.jpg","attachments":[{"fileName":"A.jpg"}]}"#
        XCTAssertEqual(try JSONFileStore<Item>.decoder.decode(Item.self, from: Data(both.utf8)).attachments.count, 1)
    }

    func testOldBackupWithPhotoStillRestores() throws {
        let json = #"{"format":"valigia-backup","version":1,"data":{"trips":[{"name":"V","luggage":[{"name":"Zaino","items":[{"name":"Foto TEST","photoFile":"P.jpg"}]}]}]},"photos":{"P.jpg":"AQID"}}"#
        let b = try BackupFile.decode(Data(json.utf8))
        XCTAssertEqual(b.data.trips[0].luggage[0].items[0].attachments.first?.fileName, "P.jpg")
        XCTAssertEqual(b.photoData["P.jpg"], Data([1, 2, 3]))
        XCTAssertEqual(b.data.referencedFiles, ["P.jpg"])
    }

    func testTolerantAttachmentDecoding() throws {
        let a = try JSONFileStore<Attachment>.decoder.decode(Attachment.self, from: Data(#"{"fileName":"X.PDF","kind":"hologram"}"#.utf8))
        XCTAssertEqual(a.kind, .other)
        let b = try JSONFileStore<Attachment>.decoder.decode(Attachment.self, from: Data(#"{"fileName":"X.PDF","originalName":"biglietto.pdf"}"#.utf8))
        XCTAssertEqual(b.kind, .pdf)
        XCTAssertEqual(b.title, "biglietto.pdf")
    }

    func testKindsNamesAndTitles() {
        XCTAssertEqual(AttachmentKind.from(fileExtension: "HEIC"), .image)
        XCTAssertEqual(AttachmentKind.from(fileExtension: "pdf"), .pdf)
        XCTAssertEqual(AttachmentKind.from(fileExtension: "pkpass"), .other)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        XCTAssertEqual(Attachment.storedName(forOriginal: "Biglietto.PDF", id: id), "00000000-0000-0000-0000-0000000000AA.pdf")
        XCTAssertEqual(Attachment.storedName(forOriginal: "senza", id: id), "00000000-0000-0000-0000-0000000000AA")
        XCTAssertEqual(Attachment.defaultTitle(forOriginal: "Andata.pdf", kind: .pdf), "Andata")
        XCTAssertEqual(Attachment.defaultTitle(forOriginal: "", kind: .image), "Foto")
        XCTAssertEqual(ByteFormat.string(512), "512 B")
        XCTAssertEqual(ByteFormat.string(850_000), "850 KB")
        XCTAssertEqual(ByteFormat.string(1_234_567), "1,2 MB")
        XCTAssertEqual(ByteFormat.string(45_000_000), "45 MB")
    }

    func testRenameRemoveReorder() {
        var list = [att("A.pdf"), att("B.pdf"), att("C.jpg", .image)]
        XCTAssertTrue(list.rename(list[0].id, to: "  Andata "))
        XCTAssertEqual(list[0].title, "Andata")
        XCTAssertFalse(list.rename(list[0].id, to: "  "))
        XCTAssertTrue(list.move(list[2].id, to: 0))
        XCTAssertEqual(list.map(\.fileName), ["C.jpg", "A.pdf", "B.pdf"])
        XCTAssertTrue(list.shift(list[1].id, by: 1))
        XCTAssertEqual(list.map(\.fileName), ["C.jpg", "B.pdf", "A.pdf"])
        XCTAssertFalse(list.shift(list[0].id, by: -1))
        XCTAssertEqual(list.firstImage?.fileName, "C.jpg")
        XCTAssertNotNil(list.remove(list[0].id))
        XCTAssertNil(list.firstImage)
    }

    func testCopiesShareFilesAndFilesAreReleasedOnlyWhenUnused() {
        var data = ValigiaData()
        let doc = att("DOC.pdf", size: 1000)
        data.templates = [PackTemplate(luggage: Luggage(name: "T", items: [Item(name: "Passaporto TEST", attachments: [doc])]), createdAt: Synthetic.date(2026, 1, 1))]
        let tripID = data.createTrip(TripDraft(name: "V", templateIDs: [data.templates[0].id], includeAlwaysItems: false))
        let tripItem = data.trip(tripID)!.luggage[0].items[0]
        // Same file, new attachment id.
        XCTAssertEqual(tripItem.attachments[0].fileName, "DOC.pdf")
        XCTAssertNotEqual(tripItem.attachments[0].id, doc.id)
        // Removing it from the trip keeps the file (template still uses it).
        let before = data
        let ref = ListRef.trip(tripID: tripID, luggageID: data.trip(tripID)!.luggage[0].id)
        data.editItemAttachments(at: ref, itemID: tripItem.id) { $0.removeAll() }
        XCTAssertTrue(ValigiaData.releasedFiles(before: before, after: data).isEmpty)
        XCTAssertTrue(data.isReferenced("DOC.pdf"))
        // Deleting the template too: now the file is released.
        let before2 = data
        data.deleteTemplate(data.templates[0].id)
        XCTAssertEqual(ValigiaData.releasedFiles(before: before2, after: data), ["DOC.pdf"])
        XCTAssertFalse(data.isReferenced("DOC.pdf"))
    }

    func testDuplicateBranchSharesFiles() {
        var items = [Item(name: "Astuccio TEST", children: [Item(name: "Biglietto TEST", attachments: [att("T.pdf")])])]
        let newID = items.duplicate(items[0].id)!
        let copy = items.find(newID)!
        XCTAssertEqual(copy.allAttachments.map(\.fileName), ["T.pdf"])
        XCTAssertNotEqual(copy.allAttachments[0].id, items[0].allAttachments[0].id)
    }

    func testTripDocumentsWithPathsAndSize() {
        let shared = att("SHARED.pdf", size: 300)
        var trip = Trip(name: "V", luggage: [
            Luggage(name: "Zaino", items: [
                Item(name: "Astuccio documenti", attachments: [att("POUCH.jpg", .image, size: 50)], children: [
                    Item(name: "Passaporto", attachments: [att("PASS.pdf", size: 200), shared])
                ])
            ]),
            Luggage(name: "Trolley", items: [Item(name: "Copia", attachments: [shared.copyWithNewID()])])
        ], attachments: [att("TICKET.pdf", size: 1000)])
        let docs = trip.documents
        XCTAssertEqual(docs.map(\.attachment.fileName), ["TICKET.pdf", "POUCH.jpg", "PASS.pdf", "SHARED.pdf", "SHARED.pdf"])
        XCTAssertEqual(docs[0].source, .trip)
        XCTAssertEqual(docs[0].location, "")
        XCTAssertEqual(docs[2].location, "Zaino › Astuccio documenti › Passaporto")
        XCTAssertEqual(docs[4].location, "Trolley › Copia")
        XCTAssertEqual(Set(docs.map(\.id)).count, docs.count, "unique ids for lists")
        XCTAssertEqual(trip.attachmentsByteSize, 1000 + 50 + 200 + 300, "shared file counted once")
        // Trip documents are editable and not copied by "duplicate trip".
        var data = ValigiaData(trips: [trip])
        data.editTripAttachments(trip.id) { $0.rename($0[0].id, to: "Andata") }
        XCTAssertEqual(data.trips[0].attachments[0].title, "Andata")
        let dup = data.duplicateTrip(trip.id)!
        XCTAssertTrue(data.trip(dup)!.attachments.isEmpty)
        XCTAssertEqual(data.trip(dup)!.documents.count, 4)
        trip.attachments = []
        XCTAssertEqual(trip.documents.count, 4)
    }

    func testFilterWithAttachmentsAndSearchByTitle() {
        let items = [Item(name: "Zaino docs", children: [Item(name: "Passaporto TEST", attachments: [att("P.pdf")]), Item(name: "Penna TEST")]), Item(name: "Altro")]
        XCTAssertEqual(Synthetic.names(ItemFilter(onlyWithAttachments: true).rows(for: items)), ["Zaino docs", "-Passaporto TEST"])
        XCTAssertEqual(Synthetic.names(ItemFilter(query: "P").rows(for: items)).contains("-Passaporto TEST"), true)
        XCTAssertEqual(Synthetic.names(ItemFilter(query: "p.pdf").rows(for: items)), [], "searches titles, not file names")
        var titled = items
        titled.update(titled[0].children[0].id) { $0.attachments[0].title = "Carta imbarco" }
        XCTAssertEqual(Synthetic.names(ItemFilter(query: "imbarco").rows(for: titled)), ["Zaino docs", "-Passaporto TEST"])
    }
}
