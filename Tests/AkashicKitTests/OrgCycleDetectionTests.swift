import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #179：organization 階層的環，先前**沒有任何地方**偵測。
///
/// 載入不查、`crossRecordIssues` 不查、`validate`／`doctor` 不查、型別層當然也
/// 擋不住。環造出來會**安靜存在**，直到某個沿 parents 走的消費端無限迴圈。
///
/// #166 已在**歸戶端**擋下會閉環的候選（那是製造環最容易的路徑）。這裡補的是
/// 另一半：手寫 YAML、批次改寫、以及**從別台機器同步進來的檔案**——最後一條
/// 決定了「所有寫入點都擋」永遠不夠，需要一道**檢查時**的偵測。
///
/// **warning 而非 error**，與 `ISO8601Prefix` 的既有裁決一致：fail-closed 的內容
/// 驗證會讓一筆壞資料使整個 store 載入不了，而環是可回溯的（檔案都在版控裡）。
final class OrgCycleDetectionTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-179-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func org(_ key: String, parents: [String] = []) throws {
        var o = Organization(key: key, names: TimelineOf([
            TemporalValue(value: key.uppercased(), range: DateRange())]))
        o.parents = TimelineOf(parents.map {
            TemporalValue(value: OrgRef.key($0), range: DateRange()) })
        try store.writeOrganization(o)
    }
    private func cycleIssues() throws -> [ValidationIssue] {
        try store.load().crossRecordIssues().filter { $0.message.contains("有環") }
    }

    /// 兩節點環——手寫 YAML 造得出來，歸戶端擋不到。
    func testTwoNodeCycleIsReported() throws {
        try org("a", parents: ["b"])
        try org("b", parents: ["a"])
        let issues = try cycleIssues()
        XCTAssertEqual(issues.count, 1, "每個環只報一次，不是每個節點各報一次：\(issues)")
        XCTAssertEqual(issues.first?.severity, .warning,
                       "報告不是錯誤——環可回溯，fail-closed 會讓整個 store 開不了")
        XCTAssertTrue(issues.first!.message.contains("a"), "訊息要指名環上的節點")
        XCTAssertTrue(issues.first!.message.contains("b"))
    }

    /// **自環**：一個 organization 是自己的 parent。
    func testSelfCycleIsReported() throws {
        try org("solo", parents: ["solo"])
        XCTAssertEqual(try cycleIssues().count, 1)
    }

    /// 三節點環——`n` 個節點只報一次，不是 `n` 次。
    func testThreeNodeCycleIsReportedOnce() throws {
        try org("x", parents: ["y"])
        try org("y", parents: ["z"])
        try org("z", parents: ["x"])
        let issues = try cycleIssues()
        XCTAssertEqual(issues.count, 1, "n 個節點的環會產生 n 則說同一件事的警告：\(issues)")
    }

    /// **合法的深層階層不得誤報**——判準是環，不是「有祖先關係」。
    func testDeepHierarchyIsNotReported() throws {
        try org("top")
        try org("mid", parents: ["top"])
        try org("leaf", parents: ["mid"])
        XCTAssertEqual(try cycleIssues(), [], "leaf→mid→top 是三層階層，不是環")
    }

    /// **菱形不是環**：兩條路徑通到同一個祖先。DFS 若不追蹤「當前路徑」而是
    /// 追蹤「看過的節點」，這裡就會誤報。
    func testDiamondIsNotReported() throws {
        try org("top")
        try org("left", parents: ["top"])
        try org("right", parents: ["top"])
        try org("bottom", parents: ["left", "right"])
        XCTAssertEqual(try cycleIssues(), [], "菱形是合法的多重隸屬")
    }

    /// `.literal` 的 parents 不構成邊——它還沒歸戶，指不到任何記錄。
    func testLiteralParentsAreNotEdges() throws {
        var o = Organization(key: "a", names: TimelineOf([
            TemporalValue(value: "A", range: DateRange())]))
        o.parents = TimelineOf([TemporalValue(value: OrgRef.literal("a"), range: DateRange())])
        try store.writeOrganization(o)
        XCTAssertEqual(try cycleIssues(), [], "未歸戶的 literal 不是指涉，不成環")
    }

    /// **環不經過起點時仍不得無限遞迴。**
    ///
    /// `x → a`、`a → b`、`b → a`：從 `x` 出發永遠走不回 `x`，但 `a ⇄ b` 是環。
    /// 少了「不重訪」那道 guard 就會在 a、b 之間彈跳到堆疊溢位。mutation 實測
    /// **刪掉那行 → `signal 11`**（整個 test 程序死掉，不是某條斷言紅）。
    ///
    /// **注意 mutation 要刪對東西**：把 guard 換成「深度上限 100」時十條全綠——
    /// 那是一個**行為等價但較慢**的實作，不是退化。要證明 guard 是 load-bearing，
    /// 必須刪掉它而不是換掉它（本程式沒有其他終止界限）。
    ///
    /// 這條同時釘住兩件事：不當機，且 `a ⇄ b` 那個環**仍要被報出來**（從 a 或 b
    /// 出發時會找到），不能因為從 x 找不到就漏掉。
    func testCycleNotReachableFromStartStillTerminatesAndIsReported() throws {
        try org("x", parents: ["a"])
        try org("a", parents: ["b"])
        try org("b", parents: ["a"])
        let issues = try cycleIssues()
        XCTAssertEqual(issues.count, 1, "a ⇄ b 要被報出來（從 a 出發找得到）：\(issues)")
        XCTAssertTrue(issues.first!.message.contains("a") && issues.first!.message.contains("b"))
        XCTAssertFalse(issues.first!.message.hasPrefix("organization 階層有環：x"),
                       "x 不在環上")
    }

    /// 長鏈 + 尾端的環——不重訪 guard 的壓力測試（沒有它會指數爆炸或無限遞迴）。
    func testLongChainEndingInACycleTerminates() throws {
        for i in 0..<30 { try org("n\(i)", parents: ["n\(i + 1)"]) }
        try org("n30", parents: ["n31"])
        try org("n31", parents: ["n30"])
        XCTAssertEqual(try cycleIssues().count, 1, "只有尾端那一個環")
    }

    /// 指向不存在的 key 不成環、也不當機。
    func testDanglingParentDoesNotCrash() throws {
        try org("a", parents: ["nonexistent"])
        XCTAssertEqual(try cycleIssues(), [])
    }

    /// **環不擋載入**——這是 warning 的實際後果，要釘住。
    func testCycleDoesNotBlockLoading() throws {
        try org("a", parents: ["b"])
        try org("b", parents: ["a"])
        let load = try store.load()
        XCTAssertEqual(load.organizations.count, 2, "環不得讓記錄載入不了")
        XCTAssertEqual(load.crossRecordIssues().filter { $0.severity == .error }, [],
                       "不得升成 error——那會鎖住整個寫入面")
    }
}
