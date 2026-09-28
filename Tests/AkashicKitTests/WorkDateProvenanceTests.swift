import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// work 的頂層 `date` 可以攜帶來源（#655，使用者 2026-09-28 裁決：第 15 條邊開新的一格 `date`，不借 `fields.date`）。
///
/// 在此之前 `enrich` 補進去的 `date` 沒有 reference——store 記得值、不記得它出自哪裡，與 #517 要解決的是同一件事、
/// 只是少了這一格。語意逐條比照 `fields.<鍵>`（`WorkFieldProvenanceTests` 釘住的那一格）。
final class WorkDateProvenanceTests: XCTestCase {

    private let digest = "sha256:" + String(repeating: "c", count: 64)
    private func entry(date: String? = nil, fields: [String: String] = [:]) -> Entry {
        var e = Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T", date: date)
        e.fields = fields
        return e
    }
    private func retrieval() -> ProvenanceReference.Kind {
        .retrieval(url: "https://api.crossref.org/works/10.1037%2Fx", retrieved: "2026-09-28", status: 200,
                   mediaType: "application/json", content: digest)
    }

    // MARK: - 值域：`date` 一格

    /// 正結果：`date` 在場 ＋ 一筆 value 缺席的 retrieval ＝ 這個日期出自這份來源。
    func testDateCanCarryItsSource() {
        var e = entry(date: "2020-04-01")
        e.references = [ProvenanceReference(field: "date", value: nil, kind: retrieval())]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
    }

    /// 負結果：`date` 缺席 ＋ 同一筆 ＝ 查過了，這份來源沒給日期。**不驗 `date` 在場**——那正是負結果的形狀，
    /// 與 `fields.<鍵>` 同一條（`testSearchedAndFoundNothingIsExpressible` 的 `date` 版）。
    func testLookedForAndFoundNoDateIsExpressible() {
        var e = entry()
        e.references = [ProvenanceReference(field: "date", value: nil, kind: retrieval())]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        XCTAssertNil(e.date, "缺席 ＋ 上面那筆 ＝ 查過了、這份來源沒給")
    }

    /// `n.d.`（確認無日期）＋ 一筆 reference ＝「這筆作品沒有日期」出自這份來源——與上一支的「這份來源沒給」是兩件事。
    func testConfirmedNoDateCanCarryItsSource() {
        var e = entry(date: Entry.noDateSentinel)
        e.references = [ProvenanceReference(field: "date", value: nil, kind: retrieval())]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        XCTAssertTrue(e.dateIsConfirmedAbsent)
    }

    /// 純量不收 value（D2）——`date` 恰有一個值，沒有「支持哪一個」可說。
    func testDateReferenceTakesNoValue() {
        var e = entry(date: "2020")
        e.references = [ProvenanceReference(field: "date", value: "2020", kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { err in
            XCTAssertTrue("\(err)".contains("date"), "\(err)")
        }
    }

    /// 離線來源走帶 digest 的 judgement；空 rests-on 在平面 init 就被擋（`date` 不在 `firstOrderRulingFields`）。
    func testOfflineSourceGoesThroughJudgementAndEmptyRestsOnIsRefused() throws {
        var e = entry(date: "1979")
        e.references = [try ProvenanceReference(
            field: "date", value: nil, url: nil, retrieved: nil, status: nil, mediaType: nil, content: nil,
            judgement: "出版年取自紙本卷期封面的掃描件", restsOn: [digest])]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        XCTAssertFalse(ProvenanceReference.firstOrderRulingFields.contains("date"))
        XCTAssertThrowsError(try ProvenanceReference(
            field: "date", value: nil, url: nil, retrieved: nil, status: nil, mediaType: nil, content: nil,
            judgement: "查過了", restsOn: []))
    }

    /// `date` 與 `fields.date` 是兩個格子：前者是頂層 `Entry.date`，後者是 `fields["date"]`。可並存、意義不同。
    func testTopLevelDateAndFieldsDateAreDistinctCells() {
        var e = entry(date: "2020", fields: ["date": "來源給的原字串"])
        e.references = [
            ProvenanceReference(field: "date", value: nil, kind: retrieval()),
            ProvenanceReference(field: "fields.date", value: nil, kind: retrieval()),
        ]
        XCTAssertNoThrow(try e.validateReferenceAttachment())
        XCTAssertEqual(ProvenanceReference.workDateField, "date")
        XCTAssertFalse(ProvenanceReference.workDateField.hasPrefix(ProvenanceReference.workFieldPrefix),
                       "無前綴才能只指頂層那一個")
    }

    /// 擴的是一格，不是拆掉門：`title` 仍拒，訊息列得出合法值域（含 `date`）。
    func testTitleIsStillRefusedAndTheMessageListsDate() {
        var e = entry()
        e.references = [ProvenanceReference(field: "title", value: nil, kind: retrieval())]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { err in
            XCTAssertTrue("\(err)".contains("date、fields.<鍵名>"), "訊息要說得出合法值域：\(err)")
        }
    }
}

/// store format 20 的寫入閘（#655）。format-19 binary 的附著驗證沒有 `date` case → 封閉 default → 整檔 quarantine，
/// 所以 marker 必須先擋。
final class WorkDateReferenceFormatGateTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "d", count: 64)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-655-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func dated(_ ref: String = "date") -> Entry {
        var e = Entry(id: UUID(), citekey: "olsson1979maximum", type: .periodicalArticle, title: "T", date: "1979")
        e.fields["abstract"] = "a"
        e.references = [ProvenanceReference(
            field: ref, value: nil,
            kind: .retrieval(url: "https://x.org/y", retrieved: "2026-09-28", status: 200, mediaType: nil, content: digest))]
        return e
    }

    /// 門檻是 20，且 binary 支援得了它（否則寫入閘會擋掉自己寫得出的東西）。
    func testThresholdIsTwentyAndSupported() {
        XCTAssertEqual(StoreVersion.workDateReferenceFormat, 20)
        XCTAssertLessThanOrEqual(StoreVersion.workDateReferenceFormat, StoreVersion.supported)
    }

    func testFormat19RefusesDateReference() throws {
        try StoreVersion.write(root: root, format: 19)
        XCTAssertThrowsError(try store.writeEntry(dated())) { error in
            // 訊息裡的數字與閘用的常數是同一個——兩份不會安靜分岔
            XCTAssertTrue("\(error)".contains("≥ \(StoreVersion.workDateReferenceFormat)"), "\(error)")
            XCTAssertTrue("\(error)".contains("field: date"), "\(error)")
        }
    }

    /// 閘只擋新語法：format 19 的 store 照樣收 `fields.<鍵>` 的 reference。
    func testFormat19StillWritesOtherWorkReferences() throws {
        try StoreVersion.write(root: root, format: 19)
        XCTAssertNoThrow(try store.writeEntry(dated("fields.abstract")))
    }

    /// format 20：寫得進去，而且讀得回來（decode 走 `validateReferenceAttachment`——讀不回來就是整檔 quarantine）。
    func testFormat20WritesAndLoadsDateReference() throws {
        try StoreVersion.write(root: root, format: 20)
        XCTAssertNoThrow(try store.writeEntry(dated()))
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        let back = try XCTUnwrap(load.entries.first { $0.citekey == "olsson1979maximum" })
        XCTAssertEqual(back.references.map(\.field), ["date"])
    }
}

/// `AddOnlyEnrichment` 對補進去的 `date`／`authors` 的來源處置（#655）。
final class EnrichmentDateAuthorsProvenanceTests: XCTestCase {

    private let digest = "sha256:" + String(repeating: "e", count: 64)
    private func entry(date: String? = nil) -> Entry {
        Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle, title: "T", date: date)
    }
    private func proposal(fields: [String: String] = [:], date: String? = nil, authors: [String] = [],
                          full: Bool = true) -> AddOnlyEnrichment.Proposal {
        AddOnlyEnrichment.Proposal(
            citekey: "a2020x", fields: fields, date: date, authors: authors, sourceDigest: digest,
            sourceURL: full ? "https://api.crossref.org/works/10.1037%2Fx" : nil, sourceRetrieved: "2026-09-28",
            sourceStatus: 200)
    }

    /// 來源齊備 → `date` 一筆（無 value、retrieval），與 `fields` 的鍵同一次寫入；套用後通得過值域檢查。
    func testFullSourceWritesADateReference() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal(fields: ["abstract": "摘"], date: "2020")])
        let o = try XCTUnwrap(r.items.first).outcome
        XCTAssertEqual(o.addedReferences.map(\.field), ["fields.abstract", "date"])
        let dateRef = try XCTUnwrap(o.addedReferences.first { $0.field == "date" })
        XCTAssertNil(dateRef.value)
        guard case .retrieval = dateRef.kind else { return XCTFail("date 的來源是一次取得：\(dateRef.kind)") }
        XCTAssertTrue(o.provenanceOmitted.isEmpty, "\(o.provenanceOmitted)")
        let after = AddOnlyEnrichment.applied(o, to: entry())
        XCTAssertEqual(after.date, "2020")
        XCTAssertNoThrow(try after.validateReferenceAttachment())
    }

    /// 目標 store 收不下（format < 20）→ **值照補**、reference 不寫、理由原樣具名。
    func testUnavailableCellKeepsTheValueAndNamesTheReason() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal(date: "2020")],
                                           dateReference: .unavailable(reason: "本 store 是 format 19"))
        let item = try XCTUnwrap(r.items.first)
        XCTAssertEqual(item.category, .added)
        XCTAssertEqual(item.outcome.addedDate, "2020", "值照補——閘管的是 reference 那一格，不是值")
        XCTAssertTrue(item.outcome.addedReferences.isEmpty)
        XCTAssertEqual(item.outcome.provenanceOmitted["date"], "本 store 是 format 19")
    }

    /// `authors` 一律不寫：`field: authors` 是作者位記錄的格子。理由具名，而且說出是誰佔了那一格。
    func testAuthorsAreNeverReferencedAndTheReasonNamesTheOccupant() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal(authors: ["Some One"])],
                                           includeAbsentAuthors: true)
        let o = try XCTUnwrap(r.items.first).outcome
        XCTAssertEqual(o.addedAuthors, [.literal("Some One")])
        XCTAssertFalse(o.addedReferences.contains { $0.field == "authors" })
        let why = try XCTUnwrap(o.provenanceOmitted["authors"])
        XCTAssertEqual(why, AddOnlyEnrichment.authorsProvenanceOmittedReason)
        XCTAssertTrue(why.contains("field: authors") && why.contains("拆分") && why.contains("移除"), why)
        // 硬寫一筆同名的 retrieval 也過不了值域：那一格要 judgement、要已退役的 value
        var e = entry()
        e.references = [ProvenanceReference(field: "authors", value: nil, kind: .retrieval(
            url: "https://x", retrieved: "2026-09-28", status: 200, mediaType: nil, content: digest))]
        XCTAssertThrowsError(try e.validateReferenceAttachment())
    }

    /// 來源不齊：整筆不寫、理由在 `provenanceSkipped`——`provenanceOmitted` 不重報同一件事。
    func testIncompleteSourceReportsOnlyTheSkip() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry()], proposals: [proposal(date: "2020", authors: ["A B"], full: false)],
                                           includeAbsentAuthors: true)
        let o = try XCTUnwrap(r.items.first).outcome
        XCTAssertNotNil(o.provenanceSkipped)
        XCTAssertTrue(o.provenanceOmitted.isEmpty, "\(o.provenanceOmitted)")
    }

    /// 沒給來源：什麼都不說（`testNoDigestMeansNoNoise` 的同一條）。
    func testNoSourceMeansNoOmissionNoise() throws {
        let p = AddOnlyEnrichment.Proposal(citekey: "a2020x", date: "2020", authors: ["A B"])
        let o = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry()], proposals: [p],
                                                         includeAbsentAuthors: true).items.first).outcome
        XCTAssertTrue(o.addedReferences.isEmpty)
        XCTAssertTrue(o.provenanceOmitted.isEmpty)
    }

    /// `date` 已有值：沒有補，也就沒有 reference、沒有省略——add-only 只替**補進去的**值記來源。
    func testExistingDateGetsNoReference() throws {
        let item = try XCTUnwrap(try AddOnlyEnrichment.plan(entries: [entry(date: "1999")],
                                                            proposals: [proposal(date: "2020")]).items.first)
        XCTAssertEqual(item.category, .skipped)
        XCTAssertTrue(item.alreadyPresent.contains("date"))
        XCTAssertTrue(item.outcome.addedReferences.isEmpty)
        XCTAssertTrue(item.outcome.provenanceOmitted.isEmpty)
    }
}
