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

    /// b13f R1 verify 第 18 列：處置依種類與欄位。venue 上**位元組不同**的變體有工具面（`update-venue --remove-reference` 以位元組定位，#673）；
    /// 位元組完全相同的重複沒有（`--remove-reference` 對它具名拒絕，`zero-instance-guards` 第 59 列）；`paginated` 與其他種類都沒有。
    /// 首版一律說「目前沒有工具面，手改 YAML」——對 venue 的位元組變體已是過期的出路。
    func testTheDispositionNamesTheRemovalFaceOnlyWhereItReallyWorks() throws {
        let content = "sha256:" + String(repeating: "c", count: 64)
        func namesRef(_ value: String) -> ProvenanceReference {
            ProvenanceReference(field: "names", value: value,
                                kind: .retrieval(url: "https://example.org/a", retrieved: "2026-09-29", status: 200, mediaType: nil, content: content))
        }
        func namedVenue(_ key: String, _ refs: [ProvenanceReference]) throws {
            var v = Venue(key: key, type: .periodical)
            v.names = TimelineOf([TemporalValue(value: "Sankhy\u{0101}", range: DateRange())])
            v.references = refs
            try store.writeVenue(v)
        }
        let nfc = "Sankhy\u{0101}", nfd = "Sankhya\u{0304}"
        try namedVenue("variant", [namesRef(nfc), namesRef(nfd)])                 // 只差位元組
        try namedVenue("identical", [namesRef(nfc), namesRef(nfc)])              // 位元組完全相同
        try namedVenue("mixed", [namesRef(nfc), namesRef(nfc), namesRef(nfd)])   // 兩種都有
        try venue("pag", [paginated("不印頁碼"), paginated("不印頁碼")])           // paginated：移除面明文不收
        func message(_ owner: String) throws -> String {
            try XCTUnwrap(store.health(from: try store.load()).duplicateReferences.first { $0.owner == owner }?.issue.message)
        }
        let variant = try message("variant")
        XCTAssertTrue(variant.contains("update-venue --remove-reference 以位元組定位移除多的那一筆"), variant)
        XCTAssertFalse(variant.contains("目前沒有工具面"), "位元組不同的變體有工具面：\(variant)")
        let identical = try message("identical")
        XCTAssertTrue(identical.contains("目前沒有工具面，手改 YAML") && !identical.contains("--remove-reference"), identical)
        let mixed = try message("mixed")
        XCTAssertTrue(mixed.contains("位元組不同的變體用 update-venue --remove-reference") && mixed.contains("位元組完全相同的重複目前沒有工具面"), mixed)
        let pag = try message("pag")
        XCTAssertTrue(pag.contains("目前沒有工具面，手改 YAML") && !pag.contains("--remove-reference"), "paginated 明文不收：\(pag)")
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

    // MARK: - #564 b33 X1 第 5／12 列：名字分類記錄是有順序的歷史

    private func classified(_ name: String, _ action: NameClassificationRecord.Action, _ reason: String, field: String = "authorized") -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
    private func venueWithHistory(_ key: String, name: String, authorized: Bool, _ refs: [ProvenanceReference]) throws {
        var v = Venue(key: key, type: .periodical, names: Timeline([TemporalValue(value: name)]), authorized: authorized ? [name] : [])
        v.references = refs
        try store.writeVenue(v)
    }

    /// 「指定 R → 撤回 S → 指定 R」是寫入面自己會寫出的合法歷史（只比最後一筆）：不報重複。person 與 venue 都是。
    func testALegitimateRedesignationHistoryIsNotADuplicate() throws {
        try venueWithHistory("vz", name: "Zed Z", authorized: true,
                             [classified("Zed Z", .designate, "R"), classified("Zed Z", .withdraw, "S"), classified("Zed Z", .designate, "R")])
        var p = Person(key: "pz", names: PersonNames(authorized: ["Zed, Z"], variant: []))
        p.references = [classified("Zed, Z", .designate, "R"), classified("Zed, Z", .withdraw, "S"), classified("Zed, Z", .designate, "R")]
        _ = try store.writePerson(p)
        let h = store.health(from: try store.load())
        XCTAssertTrue(h.duplicateReferences.isEmpty, h.duplicateReferences.map(\.issue.message).description)
    }

    /// 相鄰的兩筆彼此相等（手改或舊 binary）照報；處置不叫人「留一筆」把歷史刪成別的形狀，而是說相鄰的多餘那一筆刪掉不改變最後一筆。
    func testAdjacentEqualClassificationRecordsAreReported() throws {
        try venueWithHistory("va", name: "Adj A", authorized: true,
                             [classified("Adj A", .designate, "R"), classified("Adj A", .designate, "R"), classified("Adj A", .withdraw, "S"),
                              classified("Adj A", .designate, "R")])
        try venueWithHistory("vb", name: "Adj B", authorized: false,
                             [classified("Adj B", .designate, "R"), classified("Adj B", .withdraw, "S")])
        let found = store.health(from: try store.load()).duplicateReferences
        XCTAssertEqual(found.map(\.owner), ["va"], found.map(\.issue.message).description)
        let m = try XCTUnwrap(found.first?.issue.message)
        XCTAssertTrue(m.contains("相鄰") && m.contains("2 筆") && m.contains("不改變最後一筆") && m.contains("不相鄰的同一句"), m)
        XCTAssertFalse(m.contains("留一筆"), m)
    }
}
