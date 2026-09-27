import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 同一筆記錄裡 ≥2 筆彼此相等的**非判定** reference（#582）——D64（重複的判定記錄）的鏡像。
///
/// #554 R25／R26 把三個寫入面的去重換成位元組相等之後，只差 NFC／NFD 的兩筆都寫得進來，
/// 而 D64 那一族只看 verdict 欄位——這個狀態在此之前沒有任何面看得見。
final class DuplicateReferenceScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dupref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func paginated(_ statement: String) -> ProvenanceReference {
        ProvenanceReference(field: "paginated", value: "false",
                            kind: .judgement(statement: statement, restsOn: ["sha256:" + String(repeating: "a", count: 64)]))
    }
    private func venue(_ key: String, _ refs: [ProvenanceReference]) throws {
        var v = Venue(key: key, type: .periodical)
        v.names = TimelineOf([TemporalValue(value: key.uppercased(), range: DateRange())])
        v.paginated = false
        v.references = refs
        try store.writeVenue(v)
    }

    func testByteVariantAndByteIdenticalDuplicatesAreReportedSeparately() throws {
        try venue("nfc-nfd", [paginated("Sankhy\u{0101} 不印頁碼"), paginated("Sankhya\u{0304} 不印頁碼")])
        try venue("identical", [paginated("不印頁碼"), paginated("不印頁碼")])
        try venue("distinct", [paginated("第一次判定"), paginated("第二次判定")])
        let found = store.health(from: try store.load()).duplicateReferences
        XCTAssertEqual(found.map(\.owner).sorted(), ["identical", "nfc-nfd"], found.map(\.issue.message).description)
        let variant = try XCTUnwrap(found.first { $0.owner == "nfc-nfd" })
        XCTAssertEqual(variant.issue.severity, .warning)
        XCTAssertEqual(variant.kind, "venue")
        XCTAssertTrue(variant.issue.message.contains("只差位元組（2 種拼法"), variant.issue.message)
        XCTAssertTrue(variant.issue.message.contains("paginated"), variant.issue.message)
        let same = try XCTUnwrap(found.first { $0.owner == "identical" })
        XCTAssertTrue(same.issue.message.contains("位元組完全相同"), same.issue.message)
    }

    /// R1 verify：一組裡同時有拼法變體與逐位元組的複本時兩件事都說（曾只說「只差位元組」）；value 缺席時標點不黏在一起。
    func testMixedGroupNamesBothTheVariantAndTheIdenticalCopy() throws {
        let nfc = ProvenanceReference(field: "paginated", value: nil,
                                      kind: .judgement(statement: "Sankhy\u{0101}", restsOn: ["sha256:" + String(repeating: "b", count: 64)]))
        let nfd = ProvenanceReference(field: "paginated", value: nil,
                                      kind: .judgement(statement: "Sankhya\u{0304}", restsOn: ["sha256:" + String(repeating: "b", count: 64)]))
        try venue("mixed", [nfc, nfc, nfd])
        let m = try XCTUnwrap(store.health(from: try store.load()).duplicateReferences.first?.issue.message)
        XCTAssertTrue(m.contains("paginated 共 3 筆彼此相等"), m)
        XCTAssertTrue(m.contains("只差位元組（2 種拼法"), m)
        XCTAssertTrue(m.contains("其中 1 筆與另一筆位元組完全相同"), m)
    }

    /// 計數的單位是組：同一筆 work 上兩組重複是兩則（`akashic_doctor` 的描述寫明）。entry 側也掃。
    func testEntryHoldingTwoGroupsCountsTwo() throws {
        func retrieval(_ field: String) -> ProvenanceReference {
            ProvenanceReference(field: field, value: nil,
                                kind: .retrieval(url: "https://example.org/a", retrieved: "2026-09-27", status: 200,
                                                 mediaType: "text/html", content: "sha256:" + String(repeating: "c", count: 64)))
        }
        var e = Entry(id: UUID(), citekey: "a2020a", type: .periodicalArticle, title: "T", authors: [.literal("X")], date: "2020")
        e.fields["abstract"] = "A"
        e.fields["volume"] = "1"
        e.references = [retrieval("fields.abstract"), retrieval("fields.abstract"), retrieval("fields.volume"), retrieval("fields.volume")]
        try store.writeEntry(e)
        let found = store.health(from: try store.load()).duplicateReferences
        XCTAssertEqual(found.count, 2, found.map(\.issue.message).description)
        XCTAssertEqual(Set(found.map(\.kind)), ["entry"])
        XCTAssertEqual(Set(found.map(\.owner)), ["a2020a"])
    }

    /// 判定欄位歸 D64 管，本族不重報——同一件事出兩則是雜訊。
    func testVerdictFieldsAreLeftToTheVerdictFamily() throws {
        let v = ProvenanceReference(field: ProvenanceReference.resolutionConfirmedField,
                                    value: "work:a2020a :: A Journal",
                                    kind: .judgement(statement: "same", restsOn: []))
        try venue("verdicts", [v, v])
        let h = store.health(from: try store.load())
        XCTAssertTrue(h.duplicateReferences.isEmpty, h.duplicateReferences.map(\.issue.message).description)
    }
}
