import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicEntity

/// #450（Spectra change `split-verdict-historical-reference`）：拆分的判定持久化到 work 側——
/// 第 15 條邊（`Entry.references`）值域加 `authors`、value＝被拆掉的原 literal（逐字）、
/// statement 走 `SplitRecordValue` 單一文法、空 rests-on 經 `firstOrderRulingFields` 放行、
/// format 16 閘。值逐字取自 spec `split-record-reference` 的 Example。
final class SplitRecordReferenceTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-srr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func splitRef(_ retired: String, parts: [String], reason: String) throws -> ProvenanceReference {
        let v = try XCTUnwrap(SplitRecordValue(parts: parts, reason: reason))
        return ProvenanceReference(field: "authors", value: retired,
                                   kind: .judgement(statement: v.encoded, restsOn: []))
    }
    private func chen2020a(authors: [Author] = [.literal("某人"), .literal("雷庚玲")]) throws -> Entry {
        var e = Entry(id: UUID(), citekey: "chen2020a", type: .periodicalArticle, title: "T", authors: authors)
        e.references = [try splitRef("某人與雷庚玲", parts: ["某人", "雷庚玲"], reason: "兩位作者被匯出黏成一格")]
        return e
    }
    private var digest: String { "sha256:" + String(repeating: "ab", count: 32) }

    // MARK: - 1.1 單一解析器

    /// spec「Round trip is verbatim」。
    func testSplitRecordValueRoundTripsVerbatim() throws {
        let v = try XCTUnwrap(SplitRecordValue(parts: ["某人", "雷庚玲"], reason: "兩位作者被匯出黏成一格"))
        XCTAssertEqual(v.encoded, "拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格")
        let back = try XCTUnwrap(SplitRecordValue.parse(v.encoded))
        XCTAssertEqual(back.parts, ["某人", "雷庚玲"])
        XCTAssertEqual(back.reason, "兩位作者被匯出黏成一格")
        XCTAssertEqual(back, v)
        // 段內可含空白與冒號（design）：仍逐字 round-trip
        let tricky = try XCTUnwrap(SplitRecordValue(parts: ["Smith, J.", "Lee: Ann"], reason: "r：含全形冒號"))
        XCTAssertEqual(SplitRecordValue.parse(tricky.encoded), tricky)
    }

    /// spec Example「Statements and verdicts」：表格四列逐字。
    func testSplitRecordValueRejectsMalformed() {
        let ok = SplitRecordValue.parse("拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格")
        XCTAssertEqual(ok?.parts, ["某人", "雷庚玲"]); XCTAssertEqual(ok?.reason, "兩位作者被匯出黏成一格")
        XCTAssertNil(SplitRecordValue.parse("拆為 ⟦某人⟧：理由"), "one part")
        XCTAssertNil(SplitRecordValue.parse("拆為 ⟦某人⟧ ⟦雷庚玲⟧："), "empty reason")
        XCTAssertNil(SplitRecordValue.parse("拆為 ⟦某人 ⟦雷庚玲⟧：理由"), "unbalanced")
        XCTAssertNil(SplitRecordValue.parse("⟦某人⟧ ⟦雷庚玲⟧：理由"), "缺 prefix")
        XCTAssertNil(SplitRecordValue.parse("拆為 ⟦⟧ ⟦雷庚玲⟧：理由"), "空段")
        // 保留字元：init 與 parse 同一條規則
        XCTAssertNil(SplitRecordValue(parts: ["甲⟧", "乙"], reason: "r"))
        XCTAssertNil(SplitRecordValue(parts: ["甲"], reason: "r"))
        XCTAssertNil(SplitRecordValue(parts: ["甲", "乙"], reason: "  "))
        XCTAssertNil(SplitRecordValue(parts: ["甲", ""], reason: "r"))
    }

    // MARK: - 2.1 值域加 authors

    func testAuthorsReferenceDecodes() throws {
        try store.writeEntry(try chen2020a())
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        let back = try XCTUnwrap(load.entries.first { $0.citekey == "chen2020a" })
        XCTAssertEqual(back.references.count, 1)
        XCTAssertEqual(back.references[0].field, "authors")
        XCTAssertEqual(back.references[0].value, "某人與雷庚玲")
        guard case .judgement(let statement, let restsOn) = back.references[0].kind else { return XCTFail() }
        XCTAssertEqual(statement, "拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格")
        XCTAssertTrue(restsOn.isEmpty)
        XCTAssertEqual(back.splitRecords.map(\.retired), ["某人與雷庚玲"])
        XCTAssertEqual(back.splitRecords.first?.record.parts, ["某人", "雷庚玲"])
    }

    /// spec「Any other field on a work reference is still rejected」：訊息列四個合法 field。
    func testUnknownFieldStillRejectedAndMessageListsFour() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        e.references = [ProvenanceReference(field: "title", value: "T",
                                            kind: .judgement(statement: "s", restsOn: [digest]))]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { error in
            let msg = String(describing: error)
            XCTAssertTrue(msg.contains("doi、pmid、isbn、authors"), msg)
        }
    }

    // MARK: - 2.2 已退役值：decode 只驗形狀

    /// spec「Retired value is accepted on load」：value 不在作者位，statement 有一段在 → 載入、不 quarantine。
    func testRetiredValueIsAcceptedOnLoad() throws {
        try store.writeEntry(try chen2020a(authors: [.key("p-one"), .literal("雷庚玲")]))
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.entries.first?.references.count, 1)
    }

    /// spec「Malformed statements are rejected at decode」：手改檔成一段 → 整檔 quarantine。
    func testMalformedStatementIsQuarantinedAtDecode() throws {
        let e = try chen2020a()
        let url = try store.writeEntry(e)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("⟦雷庚玲⟧"), text)
        try text.replacingOccurrences(of: " ⟦雷庚玲⟧", with: "")
            .write(to: url, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1, "一段的拆分記錄要被拒：\(load.quarantined)")
        XCTAssertTrue(load.entries.isEmpty)
    }

    // MARK: - 2.3 firstOrderRulingFields

    /// spec「Split record with empty rests-on is accepted」；`resolutionVerdictFields` 不動。
    func testEmptyRestsOnAcceptedForAuthors() throws {
        XCTAssertNoThrow(try ProvenanceReference(
            field: "authors", value: "x與y", url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: "拆為 ⟦x⟧ ⟦y⟧：r", restsOn: []))
        XCTAssertThrowsError(try ProvenanceReference(
            field: "doi", value: "10.1000/x", url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: "s", restsOn: []), "識別碼欄位的空 rests-on 仍拒")
        XCTAssertEqual(ProvenanceReference.resolutionVerdictFields, ["resolution-confirmed", "resolution-rejected"],
                       "封閉對不動——三處把它當 verdict 文法解析")
        XCTAssertEqual(ProvenanceReference.firstOrderRulingFields,
                       ["resolution-confirmed", "resolution-rejected", "authors"])
    }

    /// spec「Resolution verdict parsing ignores split records」：ledger（demote 走它）、死 verdict 掃描各零 verdict。
    func testResolutionParsersIgnoreSplitRecords() throws {
        try store.writeEntry(try chen2020a())
        let load = try store.load()
        let entry = try XCTUnwrap(load.entries.first)
        let (verdicts, malformed) = ResolutionLedger.verdicts(references: entry.references)
        XCTAssertTrue(verdicts.isEmpty, "\(verdicts)")
        XCTAssertTrue(malformed.isEmpty, "authors 不是 verdict 欄位，不得算 malformed：\(malformed)")
        XCTAssertTrue(store.deadVerdictIssues(in: load).isEmpty)
        // demote 走同一個解析器（#418：「自己再寫一個解析器＝第二份文法」）——源碼釘住
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"),
                                 encoding: .utf8)
        guard let start = service.range(of: "private func demoteVenues(") else { return XCTFail("找不到 demoteVenues") }
        XCTAssertTrue(String(service[start.lowerBound...].prefix(6000)).contains("ResolutionLedger.verdicts(references:"),
                      "demote 沒走唯一解析器")
    }

    // MARK: - 3.1 format 16

    /// spec「Writing a split record to a format-15 store is refused」：零寫入、訊息指名 16。
    func testFormat15StoreRefusesSplitRecord() throws {
        try StoreVersion.write(root: root, format: 15)
        XCTAssertThrowsError(try store.writeEntry(try chen2020a())) { error in
            XCTAssertTrue(String(describing: error).contains("16"), "\(error)")
        }
        XCTAssertTrue(try store.load().entries.isEmpty, "被閘擋下＝零寫入")
    }

    /// spec「Format-16 store accepts the record」。
    func testFormat16StoreAcceptsSplitRecord() throws {
        XCTAssertEqual(StoreVersion.supported, 16)
        try StoreVersion.write(root: root, format: 16)
        try store.writeEntry(try chen2020a())
        XCTAssertEqual(try store.load().entries.first?.references.count, 1)
    }
}
