import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `RenameReport` 與 `PersonRenameReport` 的每個欄位都必須被渲染出來（#490）。
///
/// ## 這道守衛防的是什麼
///
/// 兩個 report 型別各自有渲染面（CLI 的 `rename`／`rename-person`、App 的
/// `RenameReportSummary`），而**加第四個欄位時沒有任何東西會出聲**：型別編譯得過、
/// 既有測試全綠，只是那個副作用從此不被印出來。而 report 存在的理由就寫在 CLI 的
/// 註解裡——「改名會動到**別的**記錄，那是使用者最不會預期的部分，不印等於沒發生過」
/// （#71 R3 DA）。一個沒被印出來的欄位，等於那個副作用回到了沒有 report 之前的狀態。
///
/// 先例是 `StoreHealthSurfaceTests`（#263／#484）與 `EntrySurfaceTests`（#394／#425）。
///
/// ## issue 自己的 Expected 已經過期——這是本檔的形狀來源
///
/// #490 的 Expected 逐字寫「`Sources/AkashicAppKit/EntryViews.swift` 的 `describe`」。
/// 那個位置**已經不存在**：#465 因為 `LocalizedError` 不能綁 MainActor 隔離的 `View`
/// 型別（Codex R2），把渲染抽成獨立的 `RenameReportSummary`。
///
/// 照 Expected 逐字實作會得到一個**指向不存在檔案**的守衛。所以本檔的兩個設計決定
/// 不是風格偏好：
///
/// 1. **欄位清單來自反射，不是人工清單**——型別是唯一來源，人工清單會與它分岔。
/// 2. **錨點找不到必須紅，不得跳過**。`repoFileAny` 具名列出全部候選路徑；
///    `declBody` 找不到宣告就 `XCTFail`。一個「找不到就 return」的守衛，在它**最
///    需要出聲的那一刻**（有人搬了檔案）恰好會安靜通過。
///
/// ## 誠實邊界
///
/// 它查的是**渲染面有沒有讀那個欄位**，不是渲染得對不對。一個讀了 `.foo` 卻印成空
/// 字串的實作仍會通過。必要條件，不是充分條件——同 `EntrySurfaceTests` 的既有立場。
final class RenameReportSurfaceTests: XCTestCase {

    /// 反射取欄位名——不寫死清單。
    private func fieldNames<T>(_ value: T) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    /// 從 `struct X: ParsableCommand {` 起、到下一個頂層 `struct` 為止。
    ///
    /// **整檔 `contains` 不行**：`Commands.swift` 有 40+ 個命令，別處偶然提到某個欄位名
    /// 就會讓斷言通過。而 `Rename` 與 `RenamePerson` 相鄰且欄位名有一個重疊
    /// （`verdictValuesRewritten`）——不切段的話，兩個型別會互相替對方作證。
    private func declBody(_ source: String, _ decl: String,
                          file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let start = source.range(of: "\n\(decl)") else {
            XCTFail("找不到宣告 `\(decl)`——它改名或搬家了。"
                    + "**不要刪掉引用它的斷言**：那會讓這個渲染面的守衛靜靜消失。"
                    + "把新的宣告字串換上來。", file: file, line: line)
            return ""
        }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\nstruct ") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    // MARK: - 非空前提（缺了它，下面每一條都會 vacuous pass）

    func testReflectionActuallySeesFields() {
        XCTAssertEqual(fieldNames(RenameReport()).count, 3,
                       "反射應看到 RenameReport 的全部欄位，實得 \(fieldNames(RenameReport()))")
        XCTAssertEqual(fieldNames(PersonRenameReport()).count, 3,
                       "反射應看到 PersonRenameReport 的全部欄位，實得 \(fieldNames(PersonRenameReport()))")
    }

    // MARK: - RenameReport 的兩個面

    func testEveryRenameReportFieldIsPrintedByTheCLI() throws {
        let src = EntrySurfaceTests.codeOnly(
            try EntrySurfaceTests.repoFileAny(["Sources/akashic/Commands.swift"],
                                              surface: "CLI rename"))
        let body = declBody(src, "struct Rename: ParsableCommand {")
        XCTAssertTrue(body.contains("func run()"), "取到的 Rename 段落不含 run()——切段錨點壞了")
        for field in fieldNames(RenameReport()) {
            XCTAssertTrue(body.contains(".\(field)"),
                          "CLI 的 rename 沒有印出 RenameReport.\(field) —— "
                          + "改名的連帶副作用不印等於沒發生過（#71 R3 DA）")
        }
    }

    func testEveryRenameReportFieldIsRenderedByTheApp() throws {
        let src = EntrySurfaceTests.codeOnly(
            try EntrySurfaceTests.repoFileAny(
                ["Sources/AkashicAppKit/RenameReportSummary.swift",
                 "Sources/AkashicAppKit/EntryViews.swift"],   // #490 Expected 寫的舊位置
                surface: "App rename 回執"))
        for field in fieldNames(RenameReport()) {
            XCTAssertTrue(src.contains(".\(field)"),
                          "App 的 rename 回執沒有渲染 RenameReport.\(field) —— "
                          + "只用 App 的人看不到這個副作用，而 CLI 面看得到"
                          + "（#263 記過的分岔換個形狀）")
        }
    }

    // MARK: - PersonRenameReport：CLI 一個面，App 零個

    /// **本條超出 #490 的 Expected**（它只點名 `RenameReport`），刻意加。
    ///
    /// 兩個型別相鄰、同一個 commit 加的、doc comment 明寫「刻意不共用型別」——只守其一
    /// 會讓檔名 `RenameReportSurfaceTests` 變成半真話。而 `PersonRenameReport` 的渲染面
    /// 只有一個，漏掉的話**連對照組都沒有**。
    func testEveryPersonRenameReportFieldIsPrintedByTheCLI() throws {
        let src = EntrySurfaceTests.codeOnly(
            try EntrySurfaceTests.repoFileAny(["Sources/akashic/Commands.swift"],
                                              surface: "CLI rename-person"))
        let body = declBody(src, "struct RenamePerson: ParsableCommand {")
        XCTAssertTrue(body.contains("func run()"), "取到的 RenamePerson 段落不含 run()——切段錨點壞了")
        for field in fieldNames(PersonRenameReport()) {
            XCTAssertTrue(body.contains(".\(field)"),
                          "CLI 的 rename-person 沒有印出 PersonRenameReport.\(field)")
        }
    }

    /// `PersonRenameReport` 今天**沒有** App 面——把「為什麼是零」釘住。
    ///
    /// 零的來源是 `renamePerson` 整個操作不在 App 裡（實測 `Sources/AkashicAppKit/`
    /// 對 `renamePerson` 與 `PersonRenameReport` 各 0 次命中）。所以上面那條「App 也要
    /// 渲染」對它不成立——**不是豁免，是前提不在**。
    ///
    /// 這條在 `renamePerson` 進 App 的那一刻變紅，訊息會說要回來加什麼。少了它，
    /// 那一刻不會有任何人被提醒，而 `RenameReport` 走過的路（CLI 有、App 漏）會原樣
    /// 重演一次。形狀取自 `zero-instance-guards` 第 8 列：零的來源在別處時，
    /// 要連「為什麼是零」一起釘住。
    func testPersonRenameHasNoAppSurfaceToday() throws {
        var dir = URL(fileURLWithPath: #filePath)
        var appKit: URL?
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Sources/AkashicAppKit")
            if FileManager.default.fileExists(atPath: candidate.path) { appKit = candidate; break }
        }
        guard let appKit else { return XCTFail("找不到 Sources/AkashicAppKit——本條的前提不成立") }
        let files = try FileManager.default.contentsOfDirectory(atPath: appKit.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "AkashicAppKit 沒有 .swift —— 斷言會空跑")
        var corpus = ""
        for f in files {
            corpus += EntrySurfaceTests.codeOnly(
                try String(contentsOf: appKit.appendingPathComponent(f), encoding: .utf8))
        }
        XCTAssertFalse(corpus.contains("PersonRenameReport") || corpus.contains("renamePerson"),
                       "App 面現在碰得到 person 改名了——這條的前提（零 App 面）已失效。"
                       + "請把 PersonRenameReport 加進 testEveryRenameReportFieldIsRenderedByTheApp "
                       + "的同型檢查，然後刪掉本條。")
    }
}
