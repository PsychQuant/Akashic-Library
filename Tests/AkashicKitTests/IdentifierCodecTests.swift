import XCTest
@testable import AkashicCore

/// §4：識別碼欄位的 YAML 編解碼。
///
/// 分工逐字取自 design.md 的決策「正規化只在寫入面發生，讀取面寬容保留既有值」：
/// **讀取→`raw`、寫入→`normalized`**。
///
/// **寬容的範圍是「非正規形」，不是「形狀不合法」**（2026-08-24 裁決）。`0003-066x`
/// 是合法 ISSN 的非正規寫法，載入並原樣保留；`12345` 不是 ISSN，整筆拒讀。兩者的
/// 差別是屬性正確性 vs 屬性根本不是這種東西，而不是嚴格程度的刻度。
final class IdentifierCodecTests: XCTestCase {

    // MARK: - task 4.1：讀取保留原樣、寫入輸出正規形

    /// 磁碟上的 `0003-066x` 讀回來必須**還是** `0003-066x`。
    ///
    /// 這一條不是風格潔癖：provenance reference 的 `value` 必須落在該欄位的現值清單內，
    /// 讀取時若把值改寫成正規形，既有 reference 就變成孤兒 → 整筆拒讀（Task 1.1 探針
    /// 實測 `people: 1` → `people: 0`、`quarantined: 1`）。
    func testNonNormalISSNSurvivesReadUntouched() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: american-psychologist
        type: periodical
        issn:
        - value: 0003-066x
        """
        let v = try VenueYAML.decode(yaml)
        XCTAssertEqual(v.issn.count, 1)
        XCTAssertEqual(v.issn.first?.raw, "0003-066x",
                       "讀取面必須原樣保留磁碟上的字串，不得在 decode 當下改寫")
        XCTAssertEqual(v.issn.first?.normalized, "0003-066X")
    }

    /// 同一筆寫回去，磁碟上變成正規形。
    func testWritingTheSameRecordNormalizesTheISSN() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: american-psychologist
        type: periodical
        issn:
        - value: 0003-066x
        """
        let out = try VenueYAML.encode(try VenueYAML.decode(yaml))
        XCTAssertTrue(out.contains("0003-066X"), "寫入面必須輸出正規形：\(out)")
        XCTAssertFalse(out.contains("0003-066x"), "非正規形不得留在寫入結果裡：\(out)")
    }

    /// 形狀不合法 → 整筆 quarantine，錯誤具名該值與預期形狀。
    ///
    /// 與上面兩條同一個決策的另一半（2026-08-24 裁決）：寬容只到非正規形為止。
    func testMalformedISSNIsRefusedAtDecode() {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: bad
        type: periodical
        issn:
        - value: 12345
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml)) { error in
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("12345"), "錯誤須具名被拒的值：\(msg)")
            XCTAssertTrue(msg.contains(ISSN.shapeDescription),
                          "錯誤須具名預期形狀：\(msg)")
        }
    }

    /// format 12 的裸純量形狀在 format 13 起**被拒**，而錯誤要說得出升級路徑。
    ///
    /// 這是本次 bump 為什麼是 non-additive 的可執行證據：舊形狀不是被寬容保留，
    /// 是整檔讀不進來。**寫成測試而不是只寫進 StoreVersion 的 doc comment**——
    /// 那段散文沒有任何東西在驗證它。
    func testBareScalarISSNIsRefusedWithAnUpgradeHint() {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: legacy
        type: periodical
        issn:
        - 0003-066X
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml)) { error in
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("mapping"), "錯誤須具名預期的容器形狀：\(msg)")
            XCTAssertTrue(msg.contains("migrate-identifiers"),
                          "錯誤須指出升級路徑，否則使用者只知道壞了不知道怎麼修：\(msg)")
        }
    }

    /// `qualifier` 缺席 ＝ 還沒查，是合法狀態；在場則原樣讀回。
    func testQualifierRoundTrips() throws {
        var v = Venue(key: "psychological-bulletin", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1939-1455")).withQualifier("electronic"),
                  try XCTUnwrap(ISSN("0033-2909")).withQualifier("print"),
                  try XCTUnwrap(ISSN("1234-5679"))]
        let out = try VenueYAML.encode(v)
        XCTAssertTrue(out.contains("qualifier: electronic"), out)
        let back = try VenueYAML.decode(out)
        XCTAssertEqual(back.issn.map { $0.medium?.rawValue ?? "—" },
                       ["electronic", "print", "—"],
                       "缺席的 medium 讀回來仍是缺席，不得被填成某個預設值")
        XCTAssertFalse(out.contains("qualifier: —"), "缺席就不寫那個鍵：\(out)")
    }

    // MARK: - task 4.2：序列化形狀

    /// 空清單**不序列化**——既有記錄零 diff 靠這一條。
    func testEmptyIdentifierListEmitsNoKey() throws {
        let v = Venue(key: "plain-journal", type: .periodical)
        let out = try VenueYAML.encode(v)
        XCTAssertFalse(out.contains("issn"),
                       "空清單不得寫出鍵，否則全庫既有記錄都會產生 diff：\(out)")
    }

    /// 清單型是序列、純量型是純量。
    func testListIdentifierIsASequenceAndScalarIsAScalar() throws {
        var v = Venue(key: "brm", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1554-351X")), try XCTUnwrap(ISSN("1554-3528"))]
        let venueOut = try VenueYAML.encode(v)
        XCTAssertTrue(venueOut.contains("issn:"), "清單型必須是 YAML 序列：\(venueOut)")
        XCTAssertTrue(venueOut.contains("- value: 1554-351X"),
                      "format 13 起序列元素是 mapping（value ＋選填 qualifier）：\(venueOut)")
        XCTAssertTrue(venueOut.contains("- value: 1554-3528"), venueOut)

        var org = Organization(key: "academia-sinica")
        org.ror = ROR("05bqach95")
        let orgOut = try OrganizationYAML.encode(org)
        XCTAssertTrue(orgOut.contains("ror: 05bqach95"),
                      "純量型必須是 YAML 純量：\(orgOut)")
    }

    /// work 的三種識別碼一起 round-trip。
    func testWorkIdentifiersRoundTrip() throws {
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle,
                      title: "A title")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))]
        e.pmid = [try XCTUnwrap(PMID("12345678"))]
        e.isbn = [try XCTUnwrap(ISBN("978-0-306-40615-7"))]
        let back = try EntryYAML.decode(try EntryYAML.encode(e))
        XCTAssertEqual(back.doi, e.doi)
        XCTAssertEqual(back.pmid, e.pmid)
        XCTAssertEqual(back.isbn, e.isbn)
    }

    /// 識別碼欄位進場之後，未知欄位仍然 tolerant-preserve（不得被新鍵擠掉）。
    func testUnknownFieldsStillPreservedAlongsideIdentifiers() throws {
        var v = Venue(key: "jcgs", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1061-8600"))]
        var text = try VenueYAML.encode(v)
        text += "future_field: hello\n"
        let back = try VenueYAML.decode(text)
        XCTAssertEqual(back.unknownFields.map(\.key), ["future_field"])
        XCTAssertEqual(back.issn, v.issn)
        XCTAssertTrue(try VenueYAML.encode(back).contains("future_field: hello"))
    }

    // MARK: - task 4.3：非正規形要出聲（surfaced，不是靜默）

    /// 非正規形是**警告**不是錯誤：值本身指涉正確、只是寫法不是正規形，而遷移會修它。
    /// 依 #416 的判準，`hasFindings` 只計 error——把它記成 error 會讓一份正常的 store
    /// 常態顯示不健康，那個布林就失去訊號。
    func testNonNormalISSNProducesAWarningNamingTheValue() throws {
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066x"))]
        let issues = v.validate()
        let hit = try XCTUnwrap(issues.first { $0.message.contains("0003-066x") },
                                "diagnostic 必須具名該值，實得：\(issues.map(\.message))")
        XCTAssertEqual(hit.severity, .warning)
        XCTAssertTrue(hit.message.contains("0003-066X"), "同時給出正規形才知道要改成什麼")
    }

    /// 已是正規形的不出聲——否則全庫每一個識別碼都會報一則，訊號被雜訊淹沒。
    func testNormalISSNIsSilent() throws {
        var v = Venue(key: "american-psychologist", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        XCTAssertTrue(v.validate().isEmpty, "正規形不得產生 diagnostic：\(v.validate())")
    }

    /// 四個帶識別碼的記錄型別都要出聲——不是只有 venue。
    func testEveryIdentifierBearingRecordKindReportsNonNormalValues() throws {
        var org = Organization(key: "academia-sinica")
        org.ror = ROR("https://ror.org/05bqach95")
        XCTAssertTrue(org.validate().contains { $0.message.contains("05bqach95") },
                      "organization.ror 非正規形要出聲：\(org.validate())")

        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.orcid = try XCTUnwrap(ORCID("0000-0002-1694-233x"))
        XCTAssertTrue(p.validate().contains { $0.message.contains("0000-0002-1694-233x") },
                      "person.orcid 非正規形要出聲：\(p.validate())")

        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle, title: "T")
        e.doi = [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29 "))]
        XCTAssertTrue(e.validate().contains { $0.message.contains("doi") },
                      "entry.doi 非正規形要出聲：\(e.validate())")
    }
}
