import XCTest
@testable import AkashicCore

/// #394 §5：基數決定 provenance 走哪條驗證分支，以及 §6 的欄位白名單。
///
/// **清單型必須帶 `value`、純量型不得帶 `value`** —— 這不是風格選擇。一筆記錄級的
/// reference 若不說支持的是清單裡的哪一個，其餘的識別碼會**看起來有來源而其實沒有**。
///
/// ## 給 venue 加附著驗證是有風險的動作，所以先量過
///
/// venue **原本完全沒有**附著驗證（`validateReferenceAttachment` 只有 person 與
/// organization 有，`VenueYAML.decode` 也從不呼叫）。也就是說今天一筆 venue reference
/// 可以寫任何欄位名而照樣載入。
///
/// 補上驗證等於突然開始拒絕東西，而實測真實 store 有 **817 筆 venue reference，全部是
/// `resolution-confirmed`**（`resolve-venues` 的判定留下的，封閉列舉第 13 條）。漏掉那
/// 一格的話 405 筆 venue 記錄會全部拒讀——所以本檔第一條測試釘的就是它。
final class IdentifierProvenanceTests: XCTestCase {

    // MARK: - 回歸：既有的 verdict reference 不得被新驗證打死

    /// 實測真實 store 的 venue reference 全是這一種，且 value 的形狀是
    /// `work:<citekey> :: <literal>`——**持有者是作品**（那筆 work 的 venue literal
    /// 被判定成這個 venue），不是 venue 自己。第一版測試憑直覺寫成 `venue:<key> :: …`
    /// 而 parser 只收 work／person／org，測試自己先紅了；改成量出來的形狀（816 筆）。
    func testVenueVerdictReferencesStillLoad() throws {
        var v = Venue(key: "psychometrika", type: .periodical)
        v.references = [ProvenanceReference(
            field: "resolution-confirmed",
            value: "work:burka2008procrastination :: Da Capo Press",
            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try v.validateReferenceAttachment(),
                         "verdict 是封閉列舉第 13 條的邊——新驗證不得把既有的 817 筆打死")
    }

    // MARK: - 清單型：issn 要求 value 且須落在清單內

    func testVenueISSNReferenceRequiresAValueNamingWhichOne() throws {
        var v = Venue(key: "brm", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1554-351X")), try XCTUnwrap(ISSN("1554-3528"))]
        v.references = [ProvenanceReference(field: "issn", value: nil, kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("value"), "錯誤要說明缺的是 value：\(e)")
        }
    }

    func testVenueISSNReferenceWithAValueInTheListLoads() throws {
        var v = Venue(key: "brm", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1554-351X")), try XCTUnwrap(ISSN("1554-3528"))]
        v.references = [ProvenanceReference(field: "issn", value: "1554-351X",
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try v.validateReferenceAttachment())
    }

    /// 孤兒 value 要具名——值被改寫後 reference 失錨，這是既有 `names` 分支的同一紀律。
    func testVenueISSNReferenceWithAnOrphanValueIsRefused() throws {
        var v = Venue(key: "brm", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1554-351X"))]
        v.references = [ProvenanceReference(field: "issn", value: "0000-0000",
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("0000-0000"), "孤兒 value 要具名：\(e)")
        }
    }

    /// **比對走正規形**——磁碟上是非正規形時，reference 的 value 仍應對得上。
    /// 少了這一條，遷移前的記錄會因為大小寫而整筆拒讀。
    func testISSNMembershipComparesByNormalForm() throws {
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066x"))]   // 磁碟上的非正規形
        v.references = [ProvenanceReference(field: "issn", value: "0003-066X",
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try v.validateReferenceAttachment(),
                         "成員判定不得因大小寫而失敗——否則遷移前的記錄會整筆拒讀")
    }

    /// venue 原本接受任何欄位名（零驗證）。補上驗證之後未知欄位要被拒，且訊息列出合法值。
    func testVenueRejectsAnUnknownReferenceField() throws {
        var v = Venue(key: "brm", type: .periodical)
        v.references = [ProvenanceReference(field: "not-a-field", value: nil,
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try v.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("issn"), "訊息要列出合法欄位：\(e)")
        }
    }

    // MARK: - 純量型：ror 不收 value

    func testOrganizationRORReferenceRejectsAValue() throws {
        var org = Organization(key: "academia-sinica")
        org.ror = ROR("05bqach95")
        org.references = [ProvenanceReference(field: "ror", value: "05bqach95",
                                             kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try org.validateReferenceAttachment()) { e in
            XCTAssertTrue("\(e)".contains("純量"), "純量欄位不收 value：\(e)")
        }
    }

    func testOrganizationRORReferenceWithoutValueLoads() throws {
        var org = Organization(key: "academia-sinica")
        org.ror = ROR("05bqach95")
        org.references = [ProvenanceReference(field: "ror", value: nil,
                                             kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try org.validateReferenceAttachment())
    }

    /// 欄位不存在時拒絕——reference 指名的欄位必須存在（既有 `orcid` 分支的同一紀律）。
    func testOrganizationRORReferenceWithoutTheFieldIsRefused() throws {
        var org = Organization(key: "academia-sinica")
        org.references = [ProvenanceReference(field: "ror", value: nil,
                                             kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try org.validateReferenceAttachment())
    }

    // MARK: - work 的識別碼要能攜帶來源（Entry.references，本輪新增的邊）

    func testEntryCarriesReferencesAtAll() throws {
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))]
        e.references = [ProvenanceReference(field: "doi", value: "10.1037/0003-066x.59.1.29",
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertNoThrow(try e.validateReferenceAttachment(),
                         "DOI 大小寫不敏感——比對走正規形")
    }

    func testEntryDOIReferenceRequiresAValue() throws {
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))]
        e.references = [ProvenanceReference(field: "doi", value: nil,
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        XCTAssertThrowsError(try e.validateReferenceAttachment())
    }

    func testEntryReferencesRoundTripThroughYAML() throws {
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        e.isbn = [try XCTUnwrap(ISBN("978-0-306-40615-7"))]
        e.references = [ProvenanceReference(field: "isbn", value: "9780306406157",
                                            kind: .judgement(statement: "查證", restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        let back = try EntryYAML.decode(try EntryYAML.encode(e))
        XCTAssertEqual(back.references.count, 1)
        XCTAssertEqual(back.references.first?.field, "isbn")
    }

    /// 空清單不序列化——既有 work 記錄零 diff。
    func testEntryWithNoReferencesEmitsNoKey() throws {
        let e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        XCTAssertFalse(try EntryYAML.encode(e).contains("references"))
    }

    // MARK: - task 6.1 的驗證目標：帶 field: issn 的 venue 記錄可載入且 reference 讀得回

    func testVenueISSNReferenceRoundTripsThroughYAML() throws {
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        v.references = [ProvenanceReference(
            field: "issn", value: "0003-066X",
            kind: .judgement(statement: "查 ISSN Portal",
                             restsOn: ["sha256:" + String(repeating: "a", count: 64)]))]
        let back = try VenueYAML.decode(try VenueYAML.encode(v))
        XCTAssertEqual(back.references.count, 1, "reference 必須出現在讀回的記錄上")
        XCTAssertEqual(back.references.first?.field, "issn")
        XCTAssertEqual(back.references.first?.value, "0003-066X")
        XCTAssertEqual(back.issn, v.issn)
    }
}
