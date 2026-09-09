import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicExport
@testable import AkashicMCPKit

/// #457：`dropAuthors` 是「這一格裝的不是作者」的唯一出口。
///
/// 在此之前 `Author` 的三態都假設那一格背後有一個作者，而 PsycInfo 的
/// `No authorship indicated`（實測 21 筆）不是——它在 `.bib` 裡是
/// `AUTHOR = {indicated, No authorship}`，一個被捏造出來的人。
final class DropAuthorTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func seed(_ authors: [Author], citekey: String = "anon2002a") throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T")
        e.authors = authors
        try store.writeEntry(e)
    }
    private func loaded(_ citekey: String = "anon2002a") throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.citekey == citekey })
    }

    // MARK: - 文法

    /// `移除：理由` 與 `拆為 ⟦…⟧：理由` **在文法上互斥**——同一筆 reference 不會被兩邊取到。
    /// 這是本設計不重用 `SplitRecordValue` 的直接理由：段數放寬到 0 會讓 `unsplitAuthors`
    /// 把一次移除讀成可還原的拆分，並把字串塞回作者位——正好是本面要消除的東西。
    func testTheTwoGrammarsAreMutuallyExclusive() throws {
        let removal = try XCTUnwrap(AuthorRemovalRecordValue(reason: "不是人")).encoded
        let split = try XCTUnwrap(SplitRecordValue(parts: ["甲", "乙"], reason: "黏在一起")).encoded
        XCTAssertNil(SplitRecordValue.parse(removal), "拆分解析器不得認得移除記錄")
        XCTAssertNil(AuthorRemovalRecordValue.parse(split), "移除解析器不得認得拆分記錄")
        XCTAssertEqual(AuthorRemovalRecordValue.parse(removal)?.reason, "不是人")
    }

    /// `encoded` 的輸出必然解析回相等的值（同 `SplitRecordValue` 的既有性質）。
    func testEncodedRoundTrips() throws {
        for reason in ["不是人", "含 ASCII : 冒號", "含全形：冒號", "  前後空白  "] {
            let v = try XCTUnwrap(AuthorRemovalRecordValue(reason: reason))
            XCTAssertEqual(AuthorRemovalRecordValue.parse(v.encoded), v, "理由「\(reason)」往返失敗")
        }
    }

    /// 空理由寫不成合法 statement——判定會錯，沒有理由的判定事後不可分辨。
    func testEmptyReasonIsRefusedAtTheTypeLevel() {
        XCTAssertNil(AuthorRemovalRecordValue(reason: ""))
        XCTAssertNil(AuthorRemovalRecordValue(reason: "   \n "))
    }

    // MARK: - 行為

    /// **主線**：移除唯一的作者位 → 0 個作者、記錄留下被移除的字串逐字。
    func testDroppingTheOnlyAuthorLeavesTheWorkUnattributed() throws {
        try seed([.literal("No authorship indicated")])
        let out = try json(try service.dropAuthors(
            ["anon2002a:No authorship indicated=PsycInfo 的無署名佔位字串，不是人"]))
        XCTAssertEqual(out["count"] as? Int, 1)
        let rows = try XCTUnwrap(out["dropped"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["authorsLeft"] as? Int, 0)

        let e = try loaded()
        XCTAssertEqual(e.authors, [], "APA7 §9.12 的無署名形要求作者位是空的")
        XCTAssertEqual(e.authorRemovalRecords.count, 1)
        XCTAssertEqual(e.authorRemovalRecords[0].removed, "No authorship indicated",
                       "被移除的字串逐字留著——資訊沒有丟（lossless-intake）")
        XCTAssertEqual(e.authorRemovalRecords[0].record.reason,
                       "PsycInfo 的無署名佔位字串，不是人")
        XCTAssertEqual(e.splitRecords.count, 0, "移除記錄不得被拆分解析器取到")
    }

    /// 多個作者位時只移除指名的那一個，其餘逐字不動。
    func testOtherAuthorsAreUntouched() throws {
        try seed([.literal("甲"), .literal("No authorship indicated"), .literal("乙")])
        _ = try service.dropAuthors(["anon2002a:No authorship indicated=不是人"])
        XCTAssertEqual(try loaded().authors, [.literal("甲"), .literal("乙")])
    }

    /// 同一筆 work 移除多個位置：**由大到小**處理，呼叫端給的是原始位置的值，不必算位移。
    func testTwoRemovalsOnOneWorkDoNotShiftEachOther() throws {
        try seed([.literal("甲"), .literal("X"), .literal("乙"), .literal("Y")])
        let out = try json(try service.dropAuthors(["anon2002a:X=r1", "anon2002a:Y=r2"]))
        XCTAssertEqual(out["count"] as? Int, 2)
        XCTAssertEqual(try loaded().authors, [.literal("甲"), .literal("乙")])
        XCTAssertEqual(try loaded().authorRemovalRecords.count, 2)
    }

    /// **同一個 literal 在同一筆 work 出現兩次 → 拒絕不判定**（形狀取自 `enrich` 對 DOI
    /// 命中 ≥2 筆的既有處置）：移除哪一個，store 裡沒有東西說得出來。
    func testAmbiguousLiteralIsRefusedAndWritesNothing() throws {
        try seed([.literal("X"), .literal("X")])
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:X=r"])) { e in
            XCTAssertTrue("\(e)".contains("拒絕不判定"), "實際：\(e)")
        }
        XCTAssertEqual(try loaded().authors.count, 2, "零寫入")
        XCTAssertEqual(try loaded().authorRemovalRecords.count, 0)
    }

    /// 已歸戶的位置**不得**被移除——那是判定的逆轉，屬別的一族。訊息要指出去處。
    func testPromotedAuthorIsRefusedAndPointsElsewhere() throws {
        try seed([.key("chen-yi")])
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:chen-yi=r"])) { e in
            XCTAssertTrue("\(e)".contains("resolve-divergence"), "實際：\(e)")
        }
    }

    /// 理由必填（面層）。
    func testMissingReasonIsRefused() throws {
        try seed([.literal("X")])
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:X="])) { e in
            XCTAssertTrue("\(e)".contains("理由是空的"), "實際：\(e)")
        }
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:X"])) { e in
            XCTAssertTrue("\(e)".contains("缺少 `=`"), "實際：\(e)")
        }
    }

    /// **一筆壞掉 → 整批零寫入**（同 `judge`／`split_author` 的既有失敗語意）。
    func testABadSpecInTheBatchWritesNothing() throws {
        try seed([.literal("甲"), .literal("X")])
        XCTAssertThrowsError(try service.dropAuthors(
            ["anon2002a:X=r", "anon2002a:不存在的名字=r"]))
        XCTAssertEqual(try loaded().authors.count, 2, "第一筆合法也不得寫入")
    }

    /// 同一批裡同一個 (citekey, literal) 出現兩次 → 拒絕。
    func testDuplicateSpecInBatchIsRefused() throws {
        try seed([.literal("X")])
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:X=r", "anon2002a:X=r2"])) { e in
            XCTAssertTrue("\(e)".contains("出現兩次"), "實際：\(e)")
        }
    }

    // MARK: - store format 閘

    /// **format 16 的 store 拒寫移除記錄**（#457）。format-16 binary 的 `authors` case
    /// 存在，但它只認得拆分文法 → `SplitRecordValue.parse` 回 nil → 一樣**整檔 quarantine
    /// 且 rc=0**。所以 16 那道閘擋不住它，要各自一道。
    func testFormatSixteenRefusesARemovalRecord() throws {
        try StoreVersion.write(root: root, format: 16)
        try seed([.literal("X")])
        XCTAssertThrowsError(try service.dropAuthors(["anon2002a:X=r"])) { e in
            XCTAssertTrue("\(e)".contains("format ≥ 17"), "實際：\(e)")
        }
        XCTAssertEqual(try loaded().authors.count, 1, "閘在任何寫入之前對全部計畫求值")
    }

    /// 拆分記錄在 format 16 仍可寫——本輪的閘不得把既有能力一起關掉。
    func testFormatSixteenStillAcceptsSplitRecords() throws {
        try StoreVersion.write(root: root, format: 16)
        try seed([.literal("某人與雷庚玲")])
        XCTAssertNoThrow(try service.splitAuthors(["anon2002a:0:與=兩位作者被黏成一格"]))
    }

    // MARK: - 序列化

    /// 移除記錄要能 round-trip 過 YAML——decode 閘（`validateReferenceAttachment`）
    /// 認得它，而不是把整檔 quarantine。
    func testRemovalRecordSurvivesYAMLRoundTrip() throws {
        try seed([.literal("No authorship indicated")])
        _ = try service.dropAuthors(["anon2002a:No authorship indicated=不是人"])
        let reloaded = try LibraryStore(root: root).load()
        XCTAssertEqual(reloaded.quarantined.count, 0, "移除記錄不得讓記錄被 quarantine")
        let e = try XCTUnwrap(reloaded.entries.first { $0.citekey == "anon2002a" })
        XCTAssertEqual(e.authorRemovalRecords.count, 1)
    }

    // MARK: - 一致性掃描

    /// **移除記錄的一致性條件與拆分記錄相反**：拆分要求「至少一段仍在作者位」，
    /// 移除要求那個字串**不在**。乾淨的移除不得報 warning。
    func testACleanRemovalReportsNothing() throws {
        try seed([.literal("X"), .literal("甲")])
        _ = try service.dropAuthors(["anon2002a:X=不是人"])
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.contradictedRemovalRecords.count, 0)
    }

    /// **可達的矛盾要被抓到**：移除之後 `authors` 是空的，而
    /// `enrich --include-absent-authors` 只在完全為空時補作者——同一個字串補得回去，
    /// 那時 store 同時說「它已退役」與「它是作者」。這條路徑不是假想的。
    func testTheLiteralComingBackIsReported() throws {
        try seed([.literal("X")])
        _ = try service.dropAuthors(["anon2002a:X=不是人"])
        var e = try loaded()
        XCTAssertEqual(e.authors, [], "前提：移除後作者位是空的")
        e.authors = [.literal("X")]          // 模擬補值面把它加回來
        try store.writeEntry(e)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.contradictedRemovalRecords.count, 1)
        // **不用 `[0]`**：掃描失效時 count 是 0，而下標會讓測試**行程崩潰**而不是乾淨地紅
        // ——負控實測到這件事（runner 收不到 `Executed N tests`，於是「守衛失效」與
        // 「harness 失效」在輸出上不可分辨）。`XCTUnwrap` 讓它照常報一條失敗。
        let first = try XCTUnwrap(health.contradictedRemovalRecords.first)
        XCTAssertEqual(first.owner, "anon2002a")
        XCTAssertEqual(first.issue.severity, ValidationIssue.Severity.warning,
                       "記錄合法，失效的是證據錨——同 staleSplitRecords 的既有分級")
    }

    /// 別的字串回來不算矛盾——判準是**那一個**被移除的字串，不是「作者位非空」。
    func testADifferentLiteralIsNotAContradiction() throws {
        try seed([.literal("X")])
        _ = try service.dropAuthors(["anon2002a:X=不是人"])
        var e = try loaded()
        e.authors = [.literal("Y")]
        try store.writeEntry(e)
        XCTAssertEqual(store.health(from: try store.load()).contradictedRemovalRecords.count, 0)
    }

    // MARK: - APA7 下限

    /// **合法的無署名作品不得被報成下限違反**（#457）——APA7 §9.12 以標題起首是一個
    /// 獨立的參考文獻形。判準與 #406 的 `paginated` 同型：只在 store 明說過時抑制。
    func testRecordedUnattributedWorkIsNotAnAPA7Error() throws {
        try seed([.literal("No authorship indicated")])
        _ = try service.dropAuthors(["anon2002a:No authorship indicated=不是人"])
        let load = try store.load()
        let report = BibExport.apa7Report(entries: load.entries, people: load.people,
                                          organizations: load.organizations, venues: load.venues)
        XCTAssertFalse(report.issues.contains {
            $0.citekey == "anon2002a" && $0.message.contains("AUTHOR")
        }, "帶移除記錄的無署名作品不是缺陷")
    }

    /// **而「還沒記」仍然是錯的**——空的 `authors` 本身不足以抑制。這一格與上一格成對：
    /// 少了它，抑制條件會從「store 明說過」悄悄退化成「作者位是空的」，而後者正是本檢查
    /// 要抓的東西（同 `paginated` 的 `nil` 照報）。
    func testEmptyAuthorsWithoutARecordIsStillAnAPA7Error() throws {
        try seed([])
        let load = try store.load()
        let report = BibExport.apa7Report(entries: load.entries, people: load.people,
                                          organizations: load.organizations, venues: load.venues)
        XCTAssertTrue(report.issues.contains {
            $0.citekey == "anon2002a" && $0.severity == .error && $0.message.contains("AUTHOR")
        }, "沒有移除記錄的空作者位＝還沒記，仍是下限違反")
    }

    /// 移除之後 `.bib` 裡**不得**再出現那個被捏造的人。
    func testTheFabricatedBylineIsGoneFromTheBib() throws {
        try seed([.literal("No authorship indicated")])
        _ = try service.dropAuthors(["anon2002a:No authorship indicated=不是人"])
        let load = try store.load()
        let bib = BibExport.bibFile(entries: load.entries, people: load.people,
                                    organizations: load.organizations, venues: load.venues)
        XCTAssertFalse(bib.contains("No authorship"), "實際：\(bib)")
        XCTAssertFalse(bib.uppercased().contains("AUTHOR ="))
    }

    /// 不合法的 statement 仍要被 decode 閘擋下——本輪放寬的是**一種**新文法，不是任何字串。
    func testAnUnknownAuthorsStatementIsStillRefused() throws {
        var e = Entry(id: UUID(), citekey: "anon2002a", type: .periodicalArticle, title: "T")
        e.references = [ProvenanceReference(field: "authors", value: "X",
                                            kind: .judgement(statement: "隨便寫的", restsOn: []))]
        XCTAssertThrowsError(try e.validateReferenceAttachment()) { err in
            XCTAssertTrue("\(err)".contains("作者位記錄文法"), "實際：\(err)")
        }
    }
}
