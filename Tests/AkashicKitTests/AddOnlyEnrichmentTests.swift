import Foundation
import XCTest
@testable import AkashicCore

/// #458（Spectra change `generic-add-only-enrich`）：add-only 政策只有一份、住 `AkashicCore`，
/// Zotero 版是它的 adapter。本檔釘住 spec `add-only-enrichment` 的每個 Requirement 與其 Example
/// （值逐字取自 spec——例子是被同意的規格，不另造）。
final class AddOnlyEnrichmentTests: XCTestCase {
    private func entry(_ citekey: String, doi: [String] = [], fields: [String: String] = [:],
                       date: String? = nil, authors: [Author] = []) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T \(citekey)",
              authors: authors, date: date, fields: fields,
              doi: doi.compactMap { DOI($0) })
    }
    private func proposal(citekey: String? = nil, doi: String? = nil, fields: [String: String] = [:],
                          date: String? = nil, authors: [String] = [], sourceDigest: String? = nil)
        -> AddOnlyEnrichment.Proposal {
        AddOnlyEnrichment.Proposal(citekey: citekey, doi: doi, fields: fields, date: date,
                                   authors: authors, sourceDigest: sourceDigest)
    }

    // MARK: - Requirement: exactly one policy implementation

    /// 既有鍵永不覆寫：entry 已有 `abstract`，提案給不同的 `abstract` → `skipped`，鍵列在 alreadyPresent。
    func testExistingKeyIsNeverOverwritten() throws {
        let e = entry("a2020b", fields: ["abstract": "old"])
        let r = try AddOnlyEnrichment.plan(entries: [e],
                                           proposals: [proposal(citekey: "a2020b", fields: ["abstract": "new"])])
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].category, .skipped)
        XCTAssertEqual(r.items[0].alreadyPresent, ["abstract"])
        XCTAssertEqual(AddOnlyEnrichment.applied(r.items[0].outcome, to: e).fields["abstract"], "old")
    }

    /// `issn` 一律拒（work 不收 ISSN——它識別期刊）：整筆 `rejected`，理由指名 issn。
    func testISSNIsRejected() throws {
        let e = entry("a2020b")
        let r = try AddOnlyEnrichment.plan(entries: [e],
                                           proposals: [proposal(citekey: "a2020b", fields: ["issn": "0033-3123"])])
        XCTAssertEqual(r.items[0].category, .rejected)
        XCTAssertEqual(r.items[0].outcome.refused.count, 1)
        XCTAssertTrue(r.items[0].outcome.refused[0].contains("issn"))
        XCTAssertNil(AddOnlyEnrichment.applied(r.items[0].outcome, to: e).fields["issn"])
    }

    /// 識別碼走結構化欄位；**部分解析**（第三態，#394 R9）時原字串保留在 `fields`（殘留）並報 partial。
    ///
    /// 用 `isbn` 而不是 `doi`：多值吸收**按種類**裁決（`IdentifierTokenizer.absorbsMultipleValues`，
    /// DOI 刻意不吸收——附錄的 DOI 是一句假的身分宣稱），所以第三態只在 ISBN／ISSN 上存在。
    /// fixture 逐字取自 `ZoteroEnrichmentTests.testPartialParseActuallyPreservesTheRawString`。
    func testIdentifierGoesToStructuredFieldWithResidue() throws {
        let e = entry("a2020b")
        let raw = "9781433832161 1-4338-3216"          // 第二個 token 只有 9 碼
        let r = try AddOnlyEnrichment.plan(entries: [e],
                                           proposals: [proposal(citekey: "a2020b", fields: ["isbn": raw])])
        let o = r.items[0].outcome
        XCTAssertEqual(r.items[0].category, .added)
        XCTAssertEqual(o.addedISBNs.map(\.normalized), ["9781433832161"])
        XCTAssertEqual(o.partial.count, 1)
        XCTAssertTrue(o.refused.isEmpty, "部分成功不是拒絕——它有自己的通道")
        let after = AddOnlyEnrichment.applied(o, to: e)
        XCTAssertEqual(after.isbn.map(\.normalized), ["9781433832161"])
        XCTAssertEqual(after.fields["isbn"], raw, "殘留保留供人裁（lossless-intake）")
    }

    /// 解析不出任何形狀的識別碼走 `refused`（不猜）；沒有別的可補 → 整筆 `rejected`。
    /// DOI 不吸收多值，`10.1000/x notadoi` 對 `DOI.init` 是一個整體、後綴含空白 → nil。
    func testUnparseableIdentifierIsRefusedByName() throws {
        let e = entry("a2020b")
        let r = try AddOnlyEnrichment.plan(entries: [e],
                                           proposals: [proposal(citekey: "a2020b", fields: ["doi": "10.1000/x notadoi"])])
        XCTAssertEqual(r.items[0].category, .rejected)
        XCTAssertTrue(r.items[0].outcome.addedDOIs.isEmpty)
        XCTAssertTrue(r.items[0].outcome.refused.contains { $0.contains("doi") }, "\(r.items[0].outcome.refused)")
        XCTAssertNil(AddOnlyEnrichment.applied(r.items[0].outcome, to: e).fields["doi"], "拒絕的不得繞道 fields 種回去")
    }

    /// 全部解析成功 → 不留殘留；entry 已有 DOI 時不動。
    func testFullyParsedIdentifierLeavesNoResidueAndNeverOverwrites() throws {
        let fresh = entry("fresh2020a")
        let has = entry("has2020a", doi: ["10.1000/old"])
        let r = try AddOnlyEnrichment.plan(entries: [fresh, has], proposals: [
            proposal(citekey: "fresh2020a", fields: ["doi": "10.1000/x"]),
            proposal(citekey: "has2020a", fields: ["doi": "10.1000/x"]),
        ])
        let a0 = AddOnlyEnrichment.applied(r.items[0].outcome, to: fresh)
        XCTAssertEqual(a0.doi.map(\.normalized), ["10.1000/x"]); XCTAssertNil(a0.fields["doi"])
        let a1 = AddOnlyEnrichment.applied(r.items[1].outcome, to: has)
        XCTAssertEqual(a1.doi.map(\.normalized), ["10.1000/old"])
        XCTAssertEqual(r.items[1].category, .skipped)
    }

    // MARK: - Requirement: proposals locate a work by citekey or DOI

    /// spec Example「twin works sharing a DOI」：兩筆都帶 `10.1037/x` → `ambiguous`、matches 列兩筆、零改動。
    func testDOIMatchingTwoEntriesIsAmbiguousAndWritesNothing() throws {
        let a = entry("smith2020a", doi: ["10.1037/x"]), b = entry("smith2020b", doi: ["10.1037/x"])
        let r = try AddOnlyEnrichment.plan(entries: [a, b],
                                           proposals: [proposal(doi: "10.1037/x", fields: ["abstract": "…"])])
        XCTAssertEqual(r.items[0].category, .ambiguous)
        XCTAssertEqual(r.items[0].matches, ["smith2020a", "smith2020b"])
        XCTAssertNil(r.items[0].citekey)
        XCTAssertTrue(r.items[0].outcome.nothingToAdd, "ambiguous 不得帶任何 addition")
    }

    /// DOI 比對走正規形（大小寫不敏感）：`10.1037/X` 命中帶 `10.1037/x` 的唯一一筆 → 對回 citekey。
    func testDOIMatchingOneEntryResolvesCitekeyByNormalForm() throws {
        let e = entry("a2020b", doi: ["10.1037/x"])
        let r = try AddOnlyEnrichment.plan(entries: [e],
                                           proposals: [proposal(doi: "10.1037/X", fields: ["abstract": "…"])])
        XCTAssertEqual(r.items[0].citekey, "a2020b")
        XCTAssertEqual(r.items[0].category, .added)
    }

    /// 雙斜線案（design Risks）：`10.1037/x` 與 `10.1037//x` 在 `DOI` 型別的正規形下是**兩個不同的 DOI**
    /// （APA 一九九〇年代的官方形就是雙斜線；`identity-is-judged-not-matched`：「兩個都真的 DOI」）。
    /// 比對不折疊斜線，所以提案 `10.1037//x` 只命中帶雙斜線的那一筆——不是 ambiguous、也不是命中單斜線那筆。
    func testDoubleSlashDOIIsADifferentDOIUnderTheNormalForm() throws {
        let single = entry("smith2020a", doi: ["10.1037/x"]), double = entry("smith2020b", doi: ["10.1037//x"])
        let r = try AddOnlyEnrichment.plan(entries: [single, double],
                                           proposals: [proposal(doi: "10.1037//x", fields: ["abstract": "…"])])
        XCTAssertEqual(r.items[0].category, .added)
        XCTAssertEqual(r.items[0].citekey, "smith2020b")
        XCTAssertTrue(r.items[0].matches.isEmpty)
    }

    func testUnknownDOIIsNotFound() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry("a2020b")],
                                           proposals: [proposal(doi: "10.9999/none", fields: ["abstract": "…"])])
        XCTAssertEqual(r.items[0].category, .notFound)
    }

    func testUnknownCitekeyIsNotFound() throws {
        let r = try AddOnlyEnrichment.plan(entries: [entry("a2020b")],
                                           proposals: [proposal(citekey: "nope2000z", fields: ["abstract": "…"])])
        XCTAssertEqual(r.items[0].category, .notFound)
    }

    /// 兩鍵同給 → 整批拒絕、錯誤指名第幾筆；前面合法的那筆也不得產生任何 item。
    func testBothKeysRejectWholeBatch() {
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry("a2020b")], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": "ok"]),
            proposal(citekey: "a2020b", doi: "10.1037/x", fields: ["abstract": "…"]),
        ])) { error in
            XCTAssertTrue("\(error)".contains("第 2 筆"), "\(error)")
        }
    }

    func testEmptyProposalRejectsWholeBatch() {
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry("a2020b")],
                                                        proposals: [proposal(citekey: "a2020b")]))
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry("a2020b")],
                                                        proposals: [proposal(fields: ["abstract": "…"])]),
                             "兩鍵皆無")
    }

    func testUnnormalizableKeyRejectsWholeBatch() {
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [entry("a2020b")],
                                                        proposals: [proposal(citekey: "a2020b", fields: ["   ": "x"])]))
    }

    // MARK: - Requirement: two abstracts are stored under two keys

    /// spec Example「Spanish second abstract」：`abstract`＋`abstract-es` → `abstract`＋`abstract_es`，兩筆 addition。
    func testTwoAbstractsLandUnderTwoKeys() throws {
        let e = entry("garcia2021")
        let r = try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "garcia2021", fields: ["abstract": "English text", "abstract-es": "Texto español"]),
        ])
        let after = AddOnlyEnrichment.applied(r.items[0].outcome, to: e)
        XCTAssertEqual(after.fields["abstract"], "English text")
        XCTAssertEqual(after.fields["abstract_es"], "Texto español")
        XCTAssertEqual(r.items[0].additions.filter { $0.kind == .field }.count, 2)
    }

    /// 第一個 abstract 已在：只補 `abstract_2`，`abstract` 報 alreadyPresent。
    func testSecondAbstractOnlyWhenFirstExists() throws {
        let e = entry("garcia2021", fields: ["abstract": "English text"])
        let r = try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "garcia2021", fields: ["abstract": "again", "abstract-2": "second"]),
        ])
        let after = AddOnlyEnrichment.applied(r.items[0].outcome, to: e)
        XCTAssertEqual(after.fields["abstract"], "English text")
        XCTAssertEqual(after.fields["abstract_2"], "second")
        XCTAssertEqual(r.items[0].alreadyPresent, ["abstract"])
    }

    // MARK: - date／authors 的既有政策

    func testDateFilledOnlyWhenEmptyAndAuthorsOnlyWithFlag() throws {
        let e = entry("a2020b")
        let noFlag = try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", date: "2020", authors: ["Ulf Olsson"]),
        ])
        var after = AddOnlyEnrichment.applied(noFlag.items[0].outcome, to: e)
        XCTAssertEqual(after.date, "2020"); XCTAssertTrue(after.authors.isEmpty)
        let flag = try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", date: "2020", authors: ["Ulf Olsson"]),
        ], includeAbsentAuthors: true)
        after = AddOnlyEnrichment.applied(flag.items[0].outcome, to: e)
        XCTAssertEqual(after.authors, [.literal("Ulf Olsson")], "只補 literal（literal-first-then-key）")
        let dated = entry("d2020a", date: "1999")
        let keep = try AddOnlyEnrichment.plan(entries: [dated], proposals: [proposal(citekey: "d2020a", date: "2020")])
        XCTAssertEqual(AddOnlyEnrichment.applied(keep.items[0].outcome, to: dated).date, "1999")
    }

    // MARK: - Requirement: source digests are reported, never stored

    func testSourceDigestIsReportedNotStored() throws {
        let e = entry("a2020b")
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let r = try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": "…"], sourceDigest: digest),
        ])
        XCTAssertEqual(r.items[0].sourceDigest, digest)
        let after = AddOnlyEnrichment.applied(r.items[0].outcome, to: e)
        XCTAssertEqual(after.references, e.references, "來源不進 Entry.references（值域只收識別碼，#394 §5）")
    }

    // MARK: - #519 Expected 2：單一字串的位元組上限（fail-closed，整批零寫入）

    /// **上限以 UTF-8 位元組計，不是字元。** 這一格是那個區分的負控：30,000 個 CJK 字元
    /// **字元數低於**上限、**位元組數是它的 1.37 倍**——若改成 `count` 就會放行。
    func testCapCountsBytesNotCharacters() throws {
        let cjk = String(repeating: "あ", count: 30_000)   // 30,000 字元 / 90,000 bytes
        XCTAssertLessThan(cjk.count, AddOnlyEnrichment.maxValueBytes, "前提：字元數低於上限")
        XCTAssertGreaterThan(cjk.utf8.count, AddOnlyEnrichment.maxValueBytes, "前提：位元組數超過上限")
        let e = entry("a2020b")
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": cjk]),
        ])) { err in
            guard case AddOnlyEnrichment.InputError.invalidProposal(let i, let reason) = err else {
                return XCTFail("應是 invalidProposal，得 \(err)")
            }
            XCTAssertEqual(i, 1)
            XCTAssertTrue(reason.contains("abstract"), "訊息要指名是哪個鍵：\(reason)")
            XCTAssertTrue(reason.contains("90000"), "訊息要說實際多長：\(reason)")
            XCTAssertTrue(reason.contains("\(AddOnlyEnrichment.maxValueBytes)"), "訊息要說上限：\(reason)")
        }
    }

    /// 界上剛好通過、界上加一被拒——上限是閉區間。
    func testCapBoundaryIsInclusive() throws {
        let e = entry("a2020b")
        let exact = String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes)
        let over = exact + "a"
        XCTAssertNoThrow(try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": exact]),
        ]), "恰好等於上限應通過")
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": over]),
        ]), "超過一個位元組即拒")
    }

    /// **整批零寫入**：批次裡有一筆超限，其餘完全合法的也不寫。這是 `two-kinds-of-edits`
    /// 對程式編輯的既有義務（「可預期失敗整批擋零寫入」），也是裁決的語意——不是逐筆略過。
    func testOversizedValueRejectsTheWholeBatch() throws {
        let e = entry("a2020b"), f = entry("b2021c")
        let big = String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes + 1)
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e, f], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": "fine"]),
            proposal(citekey: "b2021c", fields: ["abstract": big]),
        ])) { err in
            guard case AddOnlyEnrichment.InputError.invalidProposal(let i, _) = err else {
                return XCTFail("應是 invalidProposal，得 \(err)")
            }
            XCTAssertEqual(i, 2, "要指名是第幾筆")
        }
    }

    /// 上限的判準是「core 收下的字串」而不是欄位名——`date`／`authors`／`doi` 同樣受管。
    /// 這一格擋住「只在 abstract 上檢查」那種寫法（那會讓下一個欄位安靜地不受保護）。
    func testCapAppliesBeyondFieldValues() throws {
        let e = entry("a2020b")
        let big = String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes + 1)
        for (label, p) in [
            ("date", proposal(citekey: "a2020b", fields: ["abstract": "x"], date: big)),
            ("authors", proposal(citekey: "a2020b", fields: ["abstract": "x"], authors: [big])),
            ("doi", proposal(doi: big, fields: ["abstract": "x"])),
        ] {
            XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e], proposals: [p]),
                                 "\(label) 超限也要被擋")
        }
    }

    /// `sourceDigest` 不進 store，但**會回顯進報告**（MCP 面的報告直接進 LLM context），
    /// 所以它也在上限之內。這一格是自審找到的：註解寫「每一個字串」而列舉裡沒有它。
    func testCapCoversSourceDigestEvenThoughItIsNotStored() throws {
        let e = entry("a2020b")
        let big = String(repeating: "a", count: AddOnlyEnrichment.maxValueBytes + 1)
        XCTAssertThrowsError(try AddOnlyEnrichment.plan(entries: [e], proposals: [
            proposal(citekey: "a2020b", fields: ["abstract": "x"], sourceDigest: big),
        ])) { err in
            guard case AddOnlyEnrichment.InputError.invalidProposal(_, let reason) = err else {
                return XCTFail("應是 invalidProposal，得 \(err)")
            }
            XCTAssertTrue(reason.contains("sourceDigest"), "訊息要指名 sourceDigest：\(reason)")
        }
    }

    /// 上限值的**上界錨點**：`AliasEventBudget.maxBytes` 的 1/128。寫成測試是因為那個比例
    /// 是裁決的依據之一，而依據一旦漂移就不再支撐那個裁決（`assertions-must-be-measured`）。
    func testCapIsOneHundredTwentyEighthOfTheRecordBudget() {
        XCTAssertEqual(AddOnlyEnrichment.maxValueBytes * 128, AliasEventBudget.maxBytes)
    }
}
