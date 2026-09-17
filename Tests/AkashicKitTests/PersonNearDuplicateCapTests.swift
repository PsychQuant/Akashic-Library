import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #554 R26（D72；R25 verify DA 第 2 列 HIGH、第 15 列、#576）：person 的近重複掃描是**組合式**的——200 個共用 matchingKey 而
/// `NameIdentity` 互不相同的名字，真 binary 吐 19,900 則、7.6 MB、`cappedRecords` 0。venue 側早為同一個威脅模型付了兩道上限
/// （每筆記錄列 20 組、每組 3 對、整筆 100,000 對求值總量），D70 卻寫下「其餘家族線性、撐不爆」。現在 person 側同一套：
/// 先以 matchingKey 分組（O(n)），一組一則、每筆記錄至多 `Entry.perRecordWarningCap` 組、其餘一句 `Entry.perRecordCapSummaryPrefix`
/// 概括，組內逐對評估有上限。
final class PersonNearDuplicateCapTests: XCTestCase {
    private var store: LibraryStore!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-pnd-\(UUID().uuidString)")
        store = LibraryStore(root: root); try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 200 個變體：7 種連字號家族字元 × 尾隨 0–28 個 ZWSP——`matchingKey` 全部相同（連字號折成 `-`、Cf 刪掉），
    /// `NameIdentity.canonical` 全部不同（它只丟 White_Space）。
    private func variants(_ n: Int) -> [String] {
        let hyphens = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"]
        var out: [String] = []
        outer: for z in 0..<40 { for h in hyphens { out.append("Fann" + h + "C" + String(repeating: "\u{200B}", count: z)); if out.count == n { break outer } } }
        return out
    }

    func testNearDuplicateScanIsCappedPerRecordAndCountsAsCapped() throws {
        let names = variants(200)
        let issues = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertLessThanOrEqual(issues.count, Entry.perRecordWarningCap + 1, "一組一則、每筆記錄至多 cap 組加一句概括：\(issues.count)")
        let bytes = issues.map(\.message).joined().utf8.count
        XCTAssertLessThan(bytes, 200_000, "200 個名字不得吐出 MB 級的訊息：\(bytes) bytes")
        XCTAssertTrue(issues.contains { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) } || issues.count <= Entry.perRecordWarningCap,
                      "超過名額時要有概括句：\(issues.map(\.message).prefix(3))")
        // 同一組 200 筆是一組——一則說出筆數與前幾對，不逐對列
        let first = try XCTUnwrap(issues.first)
        XCTAssertTrue(first.message.contains("200") && first.message.contains("近重複"), first.message)
        // 走 store：cappedRecords 要算到這筆記錄（R25 verify 第 23／31 列：被截而不算是 D57 的「≥」失效）
        try store.writePerson(Person(key: "fann", names: PersonNames(authorized: ["Fann-C"], variant: Array(names.dropFirst()))))
        let health = store.health(from: try store.load())
        let mine = health.perRecordIssues.filter { $0.owner == "fann" && $0.issue.message.contains("近重複") }
        XCTAssertLessThanOrEqual(mine.count, Entry.perRecordWarningCap + 1, "\(mine.count)")
    }

    /// 小案例仍逐對具名（兩個名字一組、一則、兩個名字都在訊息裡）；訊息以 `displaySafeInvisible` 迴送——ZWSP 印成 `\u{200B}`（D74）。
    func testSmallNearDuplicateGroupIsNamedAndEscaped() throws {
        let issues = AuthorizedNames.validateNearDuplicates(names: ["Fann-C", "Fann\u{2010}C\u{200B}"], ownerKey: "fann")
        XCTAssertEqual(issues.count, 1, issues.map(\.message).description)
        let m = issues[0].message
        XCTAssertTrue(m.contains("Fann-C") && m.contains("\\u{200B}") && m.contains("近重複"), m)
        XCTAssertFalse(m.unicodeScalars.contains { $0.value == 0x200B }, "原始 ZWSP 不得進訊息：\(m)")
    }

    /// R27 D76（R26 verify requirements 第 7 列、logic 第 13 列、security 第 21 列、regression 第 38 列、DA 第 27 列）：venue 的第五層——整筆記錄的求值
    /// 總量上限。400 組各 100 個名字（每組 4,950 對、剛好踩不到組內 5,000 對的上限）在 R26 是 1,980,000 次求值；現在整筆至多 100,000 對，
    /// 超過的組不評估、只計數並進概括句。
    func testWholeRecordEvaluationBudgetBoundsTheScan() throws {
        var names: [String] = []
        for g in 0..<400 { names += variants(100).map { $0.replacingOccurrences(of: "Fann", with: "Fann\(g)") } }
        let issues = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertLessThanOrEqual(issues.count, Entry.perRecordWarningCap + 1, "\(issues.count)")
        let summary = try XCTUnwrap(issues.first { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }, issues.map(\.message).suffix(2).description)
        XCTAssertTrue(summary.message.contains("380 組未評估（整筆記錄求值總量已達 100000 對的上限；未評估的是最大的幾組"), summary.message)
        XCTAssertEqual(issues.filter { $0.message.contains("是**近重複**") }.count, 20, "上限內評估到的 20 組照常列出")
    }

    /// R27（R26 verify logic 第 14 列、requirements 第 30 列）：只觸發組內求值上限、零對違反的組用自己的開頭詞——R26 印「其中 0 對是**近重複**（）」
    /// 加一句叫人裁決 0 對；venue 側對同一情形早有「同名段過多」（R11 verify regression 第 31 列：`grep -c '近重複'` 不該把它算成近重複）。
    func testCapHitWithoutViolationUsesItsOwnWordingAndCountsAsCapped() throws {
        // 101 個只差內部空白數的名字：matchingKey 相同、`NameIdentity.same` 兩兩為真（canonical 把空白串收成一個）——5,050 對全部豁免、求值觸頂
        let names = (1...101).map { "Fann" + String(repeating: " ", count: $0) + "C" }
        let issues = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertEqual(issues.count, 2, issues.map(\.message).description)
        let row = issues[0].message
        XCTAssertTrue(row.contains("共用配對鍵過多") && row.contains("沒有一對被判定違反"), row)
        XCTAssertFalse(row.contains("近重複"), "零對違反的組不得被 grep -c '近重複' 算進去：\(row)")
        XCTAssertFalse(row.contains("其中 0 對"), row)
        XCTAssertTrue(row.contains("共用配對鍵過多（組：「Fann C」）"), "觸頂訊息要點名組員（R27 verify DA 第 20 列：20 行逐位元組相同、無從定位）：\(row)")
        let summary = issues[1].message
        XCTAssertTrue(summary.hasPrefix(Entry.perRecordCapSummaryPrefix) && summary.contains("已列出的組裡 1 組只評估了前 5000 對"), summary)
        XCTAssertFalse(summary.contains(" 0 組") || summary.contains("有 0 組"), "概括句只列非零的類別：\(summary)")
    }

    /// R27（R26 verify regression 第 37 列）：R26 在名額檢查之前遞增 capHitGroups，一組同時進兩個計數、概括句把相交的集合當互斥報。
    /// 現在分四類各自計數：未列出的真違反、未列出的求值觸頂、已列出但被截、整筆上限擋掉的。
    /// R28 起小組先評估（DA 第 22 列）：101 筆的觸頂組排到最後、被概括——R27 的期望（它被列出、19 組真違反列出）建立在插入序上。
    func testUnlistedAndTruncatedGroupsAreAccountedSeparately() throws {
        var names = (1...101).map { "Fann" + String(repeating: " ", count: $0) + "C" }   // 觸頂、零違反——最大的組，最後評估、被概括
        for g in 0..<21 { names += ["Fann\(g)-C", "Fann\(g)\u{2010}C\u{200B}"] }        // 21 組真近重複：20 組列出、1 組超出名額
        let issues = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        let summary = try XCTUnwrap(issues.first { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }, issues.map(\.message).suffix(2).description)
        XCTAssertTrue(summary.message.contains("另有 1 組近重複（每一組都真的違反；部分組可能只評估到組內上限）未列出"), summary.message)
        XCTAssertTrue(summary.message.contains("另有 1 組共用配對鍵過多（求值到組內上限、沒有一對被判定違反）未列出"), summary.message)
        XCTAssertFalse(summary.message.contains("已列出的組裡"), "觸頂那一組沒被列出，不得同時算進已列出：\(summary.message)")
        XCTAssertEqual(issues.filter { $0.message.contains("是**近重複**") }.count, 20)
    }

    /// R28（R27 verify DA 第 22 列 HIGH-升級、regression 第 30 列、DA 第 31 列）：R27 的預算鎖存＋插入序讓 20 組 × 101 個同鍵名字把其後
    /// 25 組真近重複全部餓死、rc 0。現在小組先評估：25 組真違反全部評到（20 列出、5 概括），19 個巨型組觸頂、1 個放不進預算。
    /// **「預算不鎖存」在升冪之下與鎖存等價**（R29；R28 verify 第 21／39 列）：組依大小升冪，第一個放不進預算的組之後的每一組都不比它小，
    /// 所以「跳過、後面放得下的照評」永遠評不到任何一組——承重的是排序，不是不鎖存。名字與 doc 改成只宣稱排序。
    func testSmallGroupsAreEvaluatedBeforeGiants() throws {
        var names: [String] = []
        for g in 0..<20 { names += Array(repeating: "Giant \(g)", count: 101) }        // 同鍵、零違反、各吃 5,000 對
        for k in 0..<25 { names += ["Dup \(k)", "DUP \(k)"] }                          // matchingKey 相同、canonical 不同：真近重複
        let issues = AuthorizedNames.validateNearDuplicates(names: names, ownerKey: "fann")
        XCTAssertEqual(issues.filter { $0.message.contains("是**近重複**") }.count, Entry.perRecordWarningCap, issues.map(\.message).description)
        XCTAssertEqual(issues.filter { $0.message.contains("共用配對鍵過多") && !$0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) }.count, 0, "巨型組被概括、不佔名額")
        let summary = try XCTUnwrap(issues.first { $0.message.hasPrefix(Entry.perRecordCapSummaryPrefix) })
        XCTAssertTrue(summary.message.contains("另有 5 組近重複（每一組都真的違反；部分組可能只評估到組內上限）未列出"), summary.message)
        XCTAssertTrue(summary.message.contains("另有 19 組共用配對鍵過多"), summary.message)
        XCTAssertTrue(summary.message.contains("1 組未評估（整筆記錄求值總量已達 100000 對的上限；未評估的是最大的幾組"), summary.message)
    }
}
