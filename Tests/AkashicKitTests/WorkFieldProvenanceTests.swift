import XCTest
@testable import AkashicCore

/// work 的非識別碼欄位可以攜帶來源，且「查過了、沒有」寫得出來（#517）。
///
/// 在此之前 `Entry.references` 的值域只收三個識別碼 ＋ `authors`（拆分記錄），所以：
/// 補進去的 `abstract` 永遠是「不知道從哪來的」（與 `replace-endnote-and-zotero` 第 2 條矛盾
/// ——位元組在 `sources/`，記錄卻指不到它）；而「查過 Crossref／OpenAlex，無」只在查證者的
/// NDJSON 裡，store 分不出「沒查」與「查了沒有」（`lossless-intake` 執行細節 3 的形）。
final class WorkFieldProvenanceTests: XCTestCase {

    private let digest = "sha256:" + String(repeating: "a", count: 64)
    private func entry(fields: [String: String] = [:], doi: [DOI] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T")
        e.fields = fields; e.doi = doi
        return e
    }
    private func retrieval(_ url: String = "https://api.crossref.org/works?query=x")
        -> ProvenanceReference.Kind {
        .retrieval(url: url, retrieved: "2026-09-09", status: 200,
                   mediaType: "application/json", content: digest)
    }

    // MARK: - 命名空間（撞名在文法上寫不出來）

    /// `fields` 的鍵與保留字撞名是**已量到的事實**（live store：`doi` ×3、`isbn` ×3）。
    /// 前綴讓 `field: doi` 與 `field: fields.doi` 是兩件不同的事。
    func testPrefixSeparatesFieldsKeysFromReservedNames() throws {
        var e = entry(fields: ["doi": "來源給的原字串"], doi: [try XCTUnwrap(DOI("10.1037/met0000845"))])
        e.references = [
            ProvenanceReference(field: "fields.doi", value: nil, kind: retrieval()),
            ProvenanceReference(field: "doi", value: "10.1037/met0000845", kind: retrieval()),
        ]
        XCTAssertNoThrow(try e.validateReferenceAttachment(),
                         "兩者可以並存且意義不同——前者是 fields[\"doi\"]，後者是結構化清單")
    }

    func testEmptyKeyAfterPrefixIsRefused() {
        var e = entry()
        e.references = [ProvenanceReference(field: "fields.", value: nil, kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment())
    }

    /// 純量欄位不收 value（D2，比照 `note`）——`fields` 的每個鍵恰有一個值。
    func testWorkFieldReferenceTakesNoValue() {
        var e = entry(fields: ["abstract": "…"])
        e.references = [ProvenanceReference(field: "fields.abstract", value: "…", kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment())
    }

    // MARK: - 正結果：這個欄位的值出自這裡

    func testAbstractCanCarryItsSource() {
        var e = entry(fields: ["abstract": "一段摘要"])
        e.references = [ProvenanceReference(field: "fields.abstract", value: nil, kind: retrieval())]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
    }

    /// **離線來源表達得出來**：`retrieval` 的 url 是必填的，而掃描的紙本頁沒有 url。
    /// judgement 走得通，且它的空 rests-on 已被平面 init 擋下——所以必然帶著真的 digest。
    func testOfflineSourceGoesThroughJudgementWithARealDigest() throws {
        var e = entry(fields: ["pages": "233-251"])
        e.references = [try ProvenanceReference(
            field: "fields.pages", value: nil, url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil,
            judgement: "頁碼取自紙本卷期的掃描件", restsOn: [digest])]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
    }

    /// 而**空 rests-on 的 judgement 仍然拒收**——那是本輪沒有選的那條路（選項 B），
    /// 它在結構上就寫不出來：`fields.*` 不在 `firstOrderRulingFields`。
    func testJudgementWithoutEvidenceIsStillRefused() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "fields.pages", value: nil, url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "查過了，沒有", restsOn: []))
    }

    // MARK: - 負結果：查過了，沒有

    /// **欄位空 ＋ 一筆 value 缺席的 retrieval ＝ 查過了，沒有。**
    /// 這是本輪的核心：在此之前這個狀態寫不出來（`doi` 的 reference 必須帶 value，
    /// 而 value 必須是清單成員——清單是空的，所以沒有任何合法的寫法）。
    func testSearchedAndFoundNothingIsExpressible() {
        var e = entry()                                   // doi 是空的
        e.references = [ProvenanceReference(field: "doi", value: nil, kind: retrieval())]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        XCTAssertTrue(e.doi.isEmpty, "欄位空 ＋ 上面那筆 ＝ 查過了，沒有")
    }

    /// value 缺席時**必須**是 retrieval——url 與日期沒有別的地方記。
    func testValuelessIdentifierReferenceMustBeARetrieval() throws {
        var e = entry()
        e.references = [try ProvenanceReference(
            field: "doi", value: nil, url: nil, retrieved: nil, status: nil,
            mediaType: nil, content: nil, judgement: "查過了", restsOn: [digest])]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { err in
            XCTAssertTrue("\(err)".contains("擷取型"), "\(err)")
        }
    }

    /// value 在場時的既有規則不變：必須是清單成員（孤兒偵測）。
    func testValueBearingIdentifierReferenceStillChecksMembership() throws {
        var e = entry(doi: [try XCTUnwrap(DOI("10.1037/met0000845"))])
        e.references = [ProvenanceReference(field: "doi", value: "10.1037/nope0000000", kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment())
    }

    /// 值域之外的欄位仍然拒收——擴的是一格，不是拆掉門。
    func testUnknownFieldIsStillRefused() {
        var e = entry()
        e.references = [ProvenanceReference(field: "title", value: nil, kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { err in
            XCTAssertTrue("\(err)".contains("fields.<鍵名>"), "訊息要說得出合法值域：\(err)")
        }
    }
}

/// `AddOnlyEnrichment` 把 `sourceDigest` 寫進 store（#517 Expected 3）。
///
/// 在此之前它「只回顯不進 store」——那是 #458 的誠實邊界，本輪解除。
final class EnrichmentProvenanceTests: XCTestCase {

    private let digest = "sha256:" + String(repeating: "b", count: 64)
    private func entry() -> Entry {
        Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T")
    }

    /// 四欄齊備（#542 R2 起 status 必要）→ 每個補進去的欄位一筆 retrieval，且與值**同一次寫入**。
    func testFullSourceWritesOneReferencePerAddedField() throws {
        let p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要", "pages": "233-251"],
            sourceDigest: digest, sourceURL: "https://api.crossref.org/works/10.1037/x",
            sourceRetrieved: "2026-09-09", sourceMediaType: "application/json", sourceStatus: 200)
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p])
        let item = try XCTUnwrap(r.items.first)
        XCTAssertNil(item.outcome.provenanceSkipped)
        XCTAssertEqual(Set(item.outcome.addedReferences.map(\.field)),
                       ["fields.abstract", "fields.pages"],
                       "每個補進去的欄位一筆——少了任一筆，那個欄位就沒有來源")

        let after = AddOnlyEnrichment.applied(item.outcome, to: entry())
        XCTAssertEqual(after.fields["abstract"], "一段摘要")
        XCTAssertEqual(after.references.count, 2)
        XCTAssertNoThrow(try after.validateReferenceAttachment(),
                         "寫出來的東西要通得過自己的值域檢查")
    }

    /// D73（R26；R25 verify 第 7／25 列）：`applied` 的冪等比位元組——只差 NFC／NFD 的來源 reference 不得被 canonical `==` 吞掉。
    func testAppliedKeepsReferencesThatDifferOnlyInBytes() throws {
        func ref(_ s: String) -> ProvenanceReference {
            ProvenanceReference(field: "fields.abstract", value: nil,
                                kind: .retrieval(url: "https://x/\(s)", retrieved: "2026-09-09", status: 200, mediaType: nil, content: digest))
        }
        var e = entry(); e.references = [ref("\u{00E1}")]
        let out = AddOnlyEnrichment.Outcome(addedFields: ["abstract": "摘"], addedReferences: [ref("a\u{0301}"), ref("\u{00E1}")])
        let after = AddOnlyEnrichment.applied(out, to: e)
        XCTAssertEqual(after.references.count, 2, "NFC 與 NFD 各一筆；逐位元組相同的不重複加：\(after.references.count)")
    }

    /// **只給 digest → 不寫，且說出為什麼**（不靜默）。
    func testBareDigestIsReportedNotSilentlyDropped() throws {
        let p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要"], sourceDigest: digest)
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p])
        let item = try XCTUnwrap(r.items.first)
        XCTAssertTrue(item.outcome.addedReferences.isEmpty)
        let why = try XCTUnwrap(item.outcome.provenanceSkipped)
        XCTAssertTrue(why.contains("sourceURL"), why)
        XCTAssertTrue(why.contains("sourceRetrieved"), why)
    }

    /// #542 R2 verify（DA）：省略 status 不再補 200。一份離線掃描檔曾因此被記成 HTTP 200——store 斷言了來源沒說過的事。
    func testMissingStatusWritesNoReferenceAndSaysWhy() throws {
        let p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要"], sourceDigest: digest,
            sourceURL: "file:///scan.pdf", sourceRetrieved: "2026-09-09")
        let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]).items.first)
        XCTAssertTrue(item.outcome.addedReferences.isEmpty, "沒有 status 就不寫 reference，不捏造 200")
        XCTAssertTrue(try XCTUnwrap(item.outcome.provenanceSkipped).contains("sourceStatus"))
    }

    /// #542 R2 verify（logic、requirements）：只給 URL 與日期、沒給 digest——先前兩面都一聲不吭。
    func testSourceFieldsWithoutDigestAreReportedToo() throws {
        let p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要"],
            sourceURL: "https://example.org/x", sourceRetrieved: "2026-09-09", sourceStatus: 200)
        let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]).items.first)
        XCTAssertTrue(item.outcome.addedReferences.isEmpty)
        let why = try XCTUnwrap(item.outcome.provenanceSkipped, "給了來源欄位卻寫不成 reference，要說出來")
        XCTAssertTrue(why.contains("sourceDigest"), why)
    }

    /// #542 R2 verify（三席）：URL／取得日期／media type 進 store，要受 #519 的單一字串上限管。
    func testSourceStringsAreLengthCapped() {
        let long = String(repeating: "u", count: AddOnlyEnrichment.maxValueBytes + 1)
        for (url, ret, mt) in [(long, "2026-09-09", "a/b"), ("https://x", long, "a/b"), ("https://x", "2026-09-09", long)] {
            let p = AddOnlyEnrichment.Proposal(citekey: "a2020x", fields: ["abstract": "x"], sourceDigest: digest,
                                               sourceURL: url, sourceRetrieved: ret, sourceMediaType: mt, sourceStatus: 200)
            XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]), "超過上限要整批拒絕")
        }
    }

    /// #542 R2 verify（security）：digest 不合法先前 dry-run 說「會寫」、apply 時才 writeFailed，連合法欄位都沒寫。
    func testMalformedDigestIsRefusedAtPlanTime() {
        let p = AddOnlyEnrichment.Proposal(citekey: "a2020x", fields: ["abstract": "x"], sourceDigest: "sha256:nothex")
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p]))
    }

    /// 沒有 digest 就什麼都不說——`provenanceSkipped` 不得變成每筆都印的雜訊。
    func testNoDigestMeansNoNoise() throws {
        let p = AddOnlyEnrichment.Proposal(citekey: "a2020x", fields: ["abstract": "x"])
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p])
        XCTAssertNil(try XCTUnwrap(r.items.first).outcome.provenanceSkipped)
    }

    /// 冪等：同一份提案跑兩次不會累積兩筆逐字相同的 reference。
    func testApplyingTwiceDoesNotDuplicateTheReference() throws {
        let p = AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: ["abstract": "一段摘要"], sourceDigest: digest,
            sourceURL: "https://example.org/x", sourceRetrieved: "2026-09-09", sourceStatus: 200)
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p])
        let outcome = try XCTUnwrap(r.items.first).outcome
        let once = AddOnlyEnrichment.applied(outcome, to: entry())
        let twice = AddOnlyEnrichment.applied(outcome, to: once)
        XCTAssertEqual(twice.references.count, 1)
    }

    /// 未知的頂層鍵仍然整批拒絕——新增四個鍵不得把那道閘打開。
    func testUnknownTopLevelKeyIsStillRefused() {
        let json = Data(#"[{"citekey":"a2020x","fields":{},"sourceUrl":"x"}]"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([AddOnlyEnrichment.Proposal].self, from: json),
                             "sourceUrl（小寫 u）不在收的鍵裡——駝峰是 sourceURL、蛇形是 source_url")
    }
}
