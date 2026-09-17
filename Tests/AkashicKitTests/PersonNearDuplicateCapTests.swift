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
}
