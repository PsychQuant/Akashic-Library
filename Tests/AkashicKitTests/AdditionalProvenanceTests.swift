import XCTest
import Foundation
@testable import AkashicCore

/// #605：一筆 entry 可帶多個 Zotero 來源。主來源維持 `provenance:`（既有記錄零 diff），
/// 附加來源寫在 `provenance_additional:`（sequence of mapping，空則不寫出）。
final class AdditionalProvenanceTests: XCTestCase {

    private func entryWithTwoSources() -> Entry {
        var entry = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-000000000605")!,
                          citekey: "cheng2021likert", type: .periodicalArticle, title: "T")
        entry.provenance = Provenance(zoteroKey: "WDDP9QMR", zoteroVersion: 153, libraryID: 1,
                                      zoteroHash: "h1")
        entry.additionalProvenance = [
            Provenance(zoteroKey: "QFAFGFW5", zoteroVersion: 236, libraryID: 2, zoteroHash: "h2",
                       importedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        ]
        return entry
    }

    func testAdditionalProvenanceRoundTrips() throws {
        let entry = entryWithTwoSources()
        let yaml = try EntryYAML.encode(entry)
        XCTAssertTrue(yaml.contains("provenance_additional:"), yaml)
        let decoded = try EntryYAML.decode(yaml)
        XCTAssertEqual(decoded.additionalProvenance.count, 1)
        XCTAssertEqual(decoded.additionalProvenance.first?.zoteroKey, "QFAFGFW5")
        XCTAssertEqual(decoded.additionalProvenance.first?.libraryID, 2)
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(try EntryYAML.encode(decoded), yaml, "re-encode 要 byte-exact")
    }

    func testEmptyAdditionalProvenanceIsNotWritten() throws {
        var entry = entryWithTwoSources()
        entry.additionalProvenance = []
        let yaml = try EntryYAML.encode(entry)
        XCTAssertFalse(yaml.contains("provenance_additional"), "空清單不寫出——既有記錄零 diff")
    }

    func testPrimaryProvenanceBlockUnchangedByAdditional() throws {
        var single = entryWithTwoSources()
        single.additionalProvenance = []
        let withExtra = try EntryYAML.encode(entryWithTwoSources())
        let without = try EntryYAML.encode(single)
        let primaryBlock = without.components(separatedBy: "provenance:\n").last!
            .components(separatedBy: "\n").prefix(4).joined(separator: "\n")
        XCTAssertTrue(withExtra.contains(primaryBlock), "主來源 mapping 形狀不因附加來源改變")
    }

    func testAdditionalElementMissingZoteroKeyFailsClosed() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000605
        citekey: a2020b
        type: periodical-article
        title: T
        provenance:
          zotero_key: K
          zotero_version: 1
        provenance_additional:
        - zotero_version: 2
          library_id: 2
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testAdditionalElementUnknownKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000605
        citekey: a2020b
        type: periodical-article
        title: T
        provenance_additional:
        - zotero_key: K2
          zotero_version: 2
          sync_source: foo
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testAdditionalProvenanceIsKnownKeyNotPreservedAsUnknown() throws {
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entryWithTwoSources()))
        XCTAssertTrue(decoded.unknownFields.isEmpty, "provenance_additional 必須是已知鍵，不走 tolerant-preserve")
    }
}
