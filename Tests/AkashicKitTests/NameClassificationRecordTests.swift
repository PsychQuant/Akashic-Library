import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）：名字分類的判定記錄——形狀、單一解析器、錨定在 names 的附著驗證、
/// store format 22 的寫入閘。值逐字取自 spec `authorized-name` 的 Example。
final class NameClassificationRecordTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ncr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ value: String, _ statement: String, restsOn: [String] = []) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value, kind: .judgement(statement: statement, restsOn: restsOn))
    }

    private func venue(names: [String], authorized: [String] = [], variant: [String] = [],
                       references: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: "psychometrika", type: .periodical,
                      names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        v.references = references
        return v
    }

    // MARK: - 單一解析器

    func testParseAcceptsExactlyTheThreeActions() {
        let cases: [(String, NameClassificationRecord.Action, String)] = [
            ("指定：期刊官網刊頭", .designate, "期刊官網刊頭"),
            ("確認：查證後確認", .confirm, "查證後確認"),
            ("撤回：刊名已改", .withdraw, "刊名已改"),
            // 程式組的句子：第一個全形冒號之後全部是理由（理由本身可以含全形冒號）
            ("撤回：同書寫系統改指定「Psychometrika」——期刊官網：刊頭", .withdraw, "同書寫系統改指定「Psychometrika」——期刊官網：刊頭"),
        ]
        for (statement, action, reason) in cases {
            let parsed = NameClassificationRecord.parse(statement)
            XCTAssertEqual(parsed?.action, action, statement)
            XCTAssertEqual(parsed?.reason, reason, statement)
        }
    }

    func testParseRefusesAnythingElse() {
        for statement in ["指定:r", "指定：", "指定：   ", "標記：r", "r", "", " 指定：r", "指定 ：r", "指定理由"] {
            XCTAssertNil(NameClassificationRecord.parse(statement), statement)
        }
    }

    func testStatementRoundTrips() {
        for action in NameClassificationRecord.Action.allCases {
            let s = NameClassificationRecord.statement(action, reason: "理由")
            XCTAssertEqual(NameClassificationRecord.parse(s)?.action, action)
            XCTAssertEqual(NameClassificationRecord.parse(s)?.reason, "理由")
        }
        XCTAssertEqual(NameClassificationRecord.statement(.designate, reason: "r"), "指定：r")
    }

    func testIsRecordNeedsFieldValueJudgementAndGrammar() {
        XCTAssertTrue(NameClassificationRecord.isRecord(record("authorized", "X", "指定：r")))
        XCTAssertTrue(NameClassificationRecord.isRecord(record("variant", "X", "確認：r", restsOn: [digest])))
        XCTAssertFalse(NameClassificationRecord.isRecord(record("names", "X", "指定：r")), "names 不是分割")
        XCTAssertFalse(NameClassificationRecord.isRecord(record("authorized", "X", "來源", restsOn: [digest])), "一般判斷")
        XCTAssertFalse(NameClassificationRecord.isRecord(ProvenanceReference(field: "authorized", value: nil,
                                                                             kind: .judgement(statement: "指定：r", restsOn: []))))
        XCTAssertFalse(NameClassificationRecord.isRecord(ProvenanceReference(
            field: "authorized", value: "X",
            kind: .retrieval(url: "https://example.org", retrieved: "2026-10-01", status: 200, mediaType: nil, content: digest))))
    }

    /// 空 rests-on 經 `firstOrderRulingFields` 放行（名字分類記錄是一階裁決）；verdict 集合不動（它被當 verdict 文法解析）。
    func testFirstOrderRulingFieldsAdmitTheTwoPartitionFields() throws {
        XCTAssertEqual(ProvenanceReference.firstOrderRulingFields,
                       ["resolution-confirmed", "resolution-rejected", "resolution-undecided", "authors", "authorized", "variant"])
        XCTAssertEqual(ProvenanceReference.resolutionVerdictFields,
                       ["resolution-confirmed", "resolution-rejected", "resolution-undecided"])
        XCTAssertNoThrow(try ProvenanceReference(field: "authorized", value: "X", url: nil, retrieved: nil, status: nil,
                                                 mediaType: nil, content: nil, judgement: "指定：r", restsOn: []))
    }

    // MARK: - 附著：錨定在 names（spec「A name-classification record SHALL be anchored to the record's names」）

    /// spec Example「anchoring outcomes」第一列：撤回之後名字離開 authorized，記錄照樣載入。
    func testVenueWithdrawalRecordLoadsAfterTheNameLeftAuthorized() throws {
        let v = venue(names: ["Psychometrika", "PSYCHOMETRIKA"], authorized: ["Psychometrika"], references: [
            record("authorized", "PSYCHOMETRIKA", "指定：bootstrap 之後查證"),
            record("authorized", "PSYCHOMETRIKA", "撤回：同書寫系統改指定「Psychometrika」——期刊官網刊頭"),
            record("authorized", "Psychometrika", "指定：期刊官網刊頭"),
        ])
        XCTAssertNoThrow(try v.validateReferenceAttachment())
        let round = try VenueYAML.decode(try VenueYAML.encode(v))
        XCTAssertEqual(round.references, v.references, "round-trip 不丟、不改記錄")
    }

    /// 第二列：名字是記錄的名字、但不在 authorized（沒有任何指定）——仍載入。
    func testVenueDesignationRecordWithoutAuthorizedStillLoads() throws {
        let v = venue(names: ["Psychometrika"], references: [record("authorized", "Psychometrika", "指定：r")])
        XCTAssertNoThrow(try v.validateReferenceAttachment())
    }

    /// 第三列：value 不是這筆記錄的名字——拒收。
    func testRecordValueThatIsNotANameIsRejected() throws {
        let v = venue(names: ["Psychometrika"], authorized: ["Psychometrika"],
                      references: [record("authorized", "Psychometrica", "指定：r")])
        XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("Psychometrica"), "\(e)")
        }
        XCTAssertThrowsError(try VenueYAML.decode(try VenueYAML.encode(v)), "載入時整檔拒")
    }

    /// 第四列：空 rests-on 的判斷型不符名字分類文法——拒收（平面 init 放行它，附著驗證要補這一道）。
    func testEmptyEvidenceJudgementOutsideTheGrammarIsRejected() throws {
        let v = venue(names: ["Psychometrika"], authorized: ["Psychometrika"],
                      references: [record("authorized", "Psychometrika", "來源")])
        XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("rests-on"), "\(e)")
        }
    }

    /// `field: authorized` 上的既有兩種 reference（擷取型、帶 rests-on 的一般判斷）維持舊語意：value 要在 authorized 內。
    func testLegacyAuthorizedReferencesKeepTheirMeaning() throws {
        let retrieval = ProvenanceReference(field: "authorized", value: "Psychometrika",
            kind: .retrieval(url: "https://example.org", retrieved: "2026-10-01", status: 200, mediaType: nil, content: digest))
        let judged = record("authorized", "Psychometrika", "出版商頁的刊頭", restsOn: [digest])
        XCTAssertNoThrow(try venue(names: ["Psychometrika"], authorized: ["Psychometrika"],
                                   references: [retrieval, judged]).validateReferenceAttachment())
        for r in [retrieval, judged] {
            XCTAssertThrowsError(try venue(names: ["Psychometrika"], references: [r]).validateReferenceAttachment(),
                                 "不在 authorized 的一般 reference 仍是孤兒")
        }
    }

    func testVenueVariantRecordIsAccepted() throws {
        let v = venue(names: ["Psychometrika", "PSYCHOMETRIKA"], authorized: ["Psychometrika"], variant: ["PSYCHOMETRIKA"],
                      references: [record("variant", "PSYCHOMETRIKA", "指定：WoS 大寫形")])
        XCTAssertNoThrow(try v.validateReferenceAttachment())
        XCTAssertEqual(try VenueYAML.decode(try VenueYAML.encode(v)).references, v.references)
    }

    /// `field: variant` 只收名字分類記錄。
    func testVenueVariantFieldAcceptsOnlyRecords() throws {
        let retrieval = ProvenanceReference(field: "variant", value: "PSYCHOMETRIKA",
            kind: .retrieval(url: "https://example.org", retrieved: "2026-10-01", status: 200, mediaType: nil, content: digest))
        let judged = record("variant", "PSYCHOMETRIKA", "WoS 的寫法", restsOn: [digest])
        for r in [retrieval, judged] {
            let v = venue(names: ["Psychometrika", "PSYCHOMETRIKA"], variant: ["PSYCHOMETRIKA"], references: [r])
            XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
                XCTAssertTrue("\(e)".contains("variant"), "\(e)")
            }
        }
    }

    func testPersonRecordIsAnchoredToAllNames() throws {
        var p = Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng"], variant: ["Cheng, Che"]))
        p.references = [record("authorized", "Cheng, Che", "撤回：改用 Che Cheng"),
                        record("authorized", "Che Cheng", "指定：本人署名")]
        XCTAssertNoThrow(try p.validateReferenceAttachment())
        XCTAssertEqual(try PersonYAML.decode(try PersonYAML.encode(p)).references, p.references)
        p.references = [record("authorized", "C. Cheng", "指定：r")]
        XCTAssertThrowsError(try p.validateReferenceAttachment())
    }

    /// person 與 organization 不收 `field: variant`：person 的 variant 分割是「其他名字」、沒有判定面；organization 沒有 variant。
    func testPersonAndOrganizationRejectVariantRecords() throws {
        var p = Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng"], variant: ["Cheng, Che"]))
        p.references = [record("variant", "Cheng, Che", "指定：r")]
        XCTAssertThrowsError(try p.validateReferenceAttachment())
        var o = Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science")]))
        o.references = [record("variant", "Institute of Statistical Science", "指定：r")]
        XCTAssertThrowsError(try o.validateReferenceAttachment())
    }

    func testOrganizationRecordIsAnchoredToNames() throws {
        var o = Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science"),
                                                          TemporalValue(value: "統計科學研究所")]),
                             authorized: ["統計科學研究所"])
        o.references = [record("authorized", "Institute of Statistical Science", "撤回：r"),
                        record("authorized", "統計科學研究所", "指定：所方正式名稱")]
        XCTAssertNoThrow(try o.validateReferenceAttachment())
        XCTAssertEqual(try OrganizationYAML.decode(try OrganizationYAML.encode(o)).references, o.references)
        o.references = [record("authorized", "ISS", "指定：r")]
        XCTAssertThrowsError(try o.validateReferenceAttachment())
    }

    // MARK: - store format 22（spec「Writing a name-classification record SHALL require store format 22」）

    func testSupportedIs22() {
        XCTAssertEqual(StoreVersion.supported, 22)
        XCTAssertEqual(StoreVersion.nameClassificationRecordFormat, 22)
    }

    private func shapes() -> (Venue, Person, Organization) {
        let v = venue(names: ["Psychometrika"], authorized: ["Psychometrika"],
                      references: [record("authorized", "Psychometrika", "指定：期刊官網刊頭")])
        var p = Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng"], variant: []))
        p.references = [record("authorized", "Che Cheng", "指定：本人署名")]
        var o = Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science")]),
                             authorized: ["Institute of Statistical Science"])
        o.references = [record("authorized", "Institute of Statistical Science", "指定：所方正式英文名稱")]
        return (v, p, o)
    }

    func testFormat21RefusesRecordsOnAllThreeShapes() throws {
        try StoreVersion.write(root: root, format: 21)
        let (v, p, o) = shapes()
        for (what, write) in [("venue", { _ = try self.store.writeVenue(v) }),
                              ("person", { _ = try self.store.writePerson(p) }),
                              ("organization", { _ = try self.store.writeOrganization(o) })] as [(String, () throws -> Void)] {
            XCTAssertThrowsError(try write(), what) { e in
                let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
                XCTAssertTrue(m.contains("22"), "\(what)：\(m)")
            }
        }
        XCTAssertTrue(try store.load().venues.isEmpty, "零寫入")
    }

    /// 沒有名字分類記錄的寫入不受這道閘影響（format 21 照寫）。
    func testFormat21StillWritesRecordsWithoutNameRecords() throws {
        try StoreVersion.write(root: root, format: 21)
        XCTAssertNoThrow(try store.writeVenue(venue(names: ["Psychometrika"], authorized: ["Psychometrika"])))
    }

    func testFormat22WritesAndReloadsRecords() throws {
        let (v, p, o) = shapes()
        _ = try store.writeVenue(v)
        _ = try store.writePerson(p)
        _ = try store.writeOrganization(o)
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        XCTAssertEqual(load.venues.first?.references, v.references)
        XCTAssertEqual(load.people.first?.references, p.references)
        XCTAssertEqual(load.organizations.first?.references, o.references)
    }

    // MARK: - 位元組去重的 append

    func testAppendSkipsByteIdenticalRecords() {
        var refs = [record("authorized", "X", "指定：r")]
        let written = NameClassificationRecord.append([record("authorized", "X", "指定：r"),
                                                       record("authorized", "X", "確認：r"),
                                                       record("authorized", "X", "確認：r")], to: &refs)
        XCTAssertEqual(written, 1)
        XCTAssertEqual(refs.count, 2)
        // canonical 相等、位元組不同的是另一筆（零資訊損失的承諾對位元組說，D65）
        let nfd = "Psychometrika\u{0301}"
        var more = [record("authorized", "Psychometriká", "指定：r")]
        XCTAssertEqual(NameClassificationRecord.append([record("authorized", nfd, "指定：r")], to: &more), 1)
    }
}
