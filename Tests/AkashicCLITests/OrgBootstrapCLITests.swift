import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #154 verify 154-4：`bootstrap-organizations` 的**CLI 輸出面**沒有任何測試。
///
/// 為什麼單元測試不夠：`OrgBootstrap.result` 的 `dropped` 有單元測試，但「CLI 有沒有
/// 把它印出來」是另一件事——席位實測兩個變異（拿掉 `reportDropped()` 呼叫、把空候選
/// 訊息改回誤導版本）在 960 個測試下**全綠**。dropped 這個機制存在的唯一理由就是
/// 「使用者要看得到」，而唯一看得到的地方是 CLI 輸出，所以判準必須落在 CLI 輸出上。
///
/// 用真 binary（非直接呼叫 `run()`）：#101/#112 的沙箱紀律——`--library` 之外一律
/// 剝除 `AKASHIC_*`，否則開發機的 registry 會把測試導到真實 store。
final class OrgBootstrapCLITests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-orgboot-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 寫一個帶 literal affiliations 的 person（實體依 UUID 落 `entityURL`，
    /// 不是 `people/<key>.yaml`——後者是舊佈局）。
    private func writePerson(key: String, affiliations: [String]) throws {
        let id = UUID()
        let segs = affiliations.map { "  - value:\n      literal: \"\($0)\"\n" }.joined()
        let yaml = """
        person:
        id: \(id.uuidString)
        key: \(key)
        names:
        - \(key)
        profile:
          affiliations:
        \(segs)
        """
        try yaml.write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
    }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }

    /// 純 CJK 機構名產不出 key——**必須明列**，不能只印出建得起來的那些。
    ///
    /// 這是 dropped 機制的核心情境：台灣機構的雙語寫法能用英文部分產 key，但
    /// 中文-only 的（「中央研究院」）不行。使用者看到「1 個候選」卻不知道另外
    /// 還有一個機構名被略過。
    func testDroppedNamesAreListed() throws {
        try writePerson(key: "p-one",
                        affiliations: ["中央研究院", "National Taiwan University"])
        let r = try runCLI(["bootstrap-organizations"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("national-taiwan-university"),
                      "雙語／英文名該產得出 key：\n\(r.output)")
        XCTAssertTrue(r.output.contains("中央研究院"),
                      "產不出 key 的機構名必須明列，不得靜默丟：\n\(r.output)")
        XCTAssertTrue(r.output.contains("無法自動產生 key"),
                      "要說明為什麼被列出來（需人工指定 key）：\n\(r.output)")
    }

    /// 全部候選都產不出 key 時，**不得**印「皆已有對應 organization，或全部低於門檻」
    /// ——那兩個原因都不是真的，使用者會以為機構都建好了。
    func testEmptyMessageIsNotMisleadingWhenEverythingWasDropped() throws {
        try writePerson(key: "p-two", affiliations: ["中央研究院", "國立臺灣師範大學"])
        let r = try runCLI(["bootstrap-organizations"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("皆已有對應 organization"),
                       "有機構名被丟棄時不得宣稱「都已建好或低於門檻」：\n\(r.output)")
        XCTAssertTrue(r.output.contains("中央研究院"), r.output)
        XCTAssertTrue(r.output.contains("國立臺灣師範大學"), r.output)
    }

    /// 真的沒東西可做時，空訊息照舊（不要為了修上一條而讓正常情境也變吵）。
    func testEmptyMessageStaysWhenThereIsGenuinelyNothing() throws {
        try writePerson(key: "p-three", affiliations: [])
        let r = try runCLI(["bootstrap-organizations"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("無候選"), r.output)
        XCTAssertFalse(r.output.contains("無法自動產生 key"),
                       "沒有 dropped 就不該出現 dropped 段：\n\(r.output)")
    }

    /// `--apply` 要說出建了什麼（席位附帶：先前一筆都不印，使用者無從確認）。
    func testApplyListsCreatedKeys() throws {
        try writePerson(key: "p-four", affiliations: ["National Taiwan University"])
        let r = try runCLI(["bootstrap-organizations", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("national-taiwan-university"),
                      "--apply 要列出建立的 key：\n\(r.output)")
        // 印出來 ≠ 真的寫進去：從 store 讀回確認（--apply 的輸出若與實際寫入
        // 脫節，這個測試就只是在驗證 print）
        let orgs = try store.load().organizations
        XCTAssertEqual(orgs.map(\.key), ["national-taiwan-university"],
                       "--apply 要真的寫進 store")
    }

    /// **`--apply` 路徑也要列 dropped**（#154 verify 154-9）：`reportDropped()` 有三個
    /// 呼叫點，先前只有「空候選」與「dry-run 列表」兩個被蓋住——刪掉 `--apply` 後面
    /// 那個呼叫，全套 965 測試綠。而 `--apply` 正是使用者最容易認定「做完了」的
    /// 時刻，也是唯一留下永久痕跡的路徑。
    func testApplyAlsoListsDropped() throws {
        try writePerson(key: "p-five",
                        affiliations: ["National Taiwan University", "中央研究院"])
        let r = try runCLI(["bootstrap-organizations", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("national-taiwan-university"), r.output)
        XCTAssertTrue(r.output.contains("中央研究院"),
                      "--apply 之後仍要說出哪些沒建起來：\n\(r.output)")
        XCTAssertTrue(r.output.contains("無法自動產生 key"), r.output)
        // 只建一個——dropped 的那個不得被建成垃圾 key
        XCTAssertEqual(try store.load().organizations.map(\.key), ["national-taiwan-university"])
    }

    /// **寫入失敗時不得留半套狀態**（#154 verify 154-11）。
    ///
    /// 補這條的理由不是「補測試比較好」，而是**本 PR 新增的防護本身沒有防護**：
    /// per-item 收容、`⚠ 部分完成`、exit 1 全是這次新加的行為，而驗證它們的只有
    /// 席位手動的 `chflags uchg`——那不會留在 repo 裡。下一個人動這段時沒有任何
    /// 東西擋住回歸。
    ///
    /// 用 `chflags uchg` 把其中一個目標檔設成不可寫，斷言：exit≠0、輸出列出失敗的
    /// key、**其餘 org 仍被寫入**（不是「連試都沒試」）、index 有重建。
    func testApplyReportsPartialFailureAndKeepsGoing() throws {
        try writePerson(key: "p-six",
                        affiliations: ["National Taiwan University", "Academia Sinica"])
        // 先 dry-run 拿到會建立的兩個 key
        let dry = try runCLI(["bootstrap-organizations"])
        XCTAssertTrue(dry.output.contains("academia-sinica"), dry.output)

        // **只鎖一個檔**（#154 verify R4 Q1）。第一版鎖整個 `entities/` 目錄，理由是
        // 「org 的檔名是 UUID，無法預測」——**那個前提是錯的**：
        // `Organization.init` 走 `DeterministicUUID.forOrganization(key:)`（UUIDv5，
        // 從 key 推出），同一個 key 在任何 store 都得到同一個 UUID。
        //
        // 而鎖整個目錄讓這條測試**驗不到自己名字裡的 `AndKeepsGoing`**：所有寫入都
        // 失敗 → `written` 恆為 0 → 席位把「首次失敗即 break」的回歸原封不動放回去，
        // 六條測試**全綠**。測試名字宣稱了它沒驗的性質，那比沒有測試更糟。
        //
        // 佔位檔刻意寫成會被 quarantine 的壞 YAML——那樣該 org 不算「已存在」、
        // 仍會被提名，寫入時才撞上 immutable。
        let target = store.entityURL(
            id: DeterministicUUID.forOrganization(key: "academia-sinica"))
        try "organization:\n  bad: [unclosed\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes(
            [.immutable: false], ofItemAtPath: target.path) }

        let r = try runCLI(["bootstrap-organizations", "--apply"])
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: target.path)

        XCTAssertNotEqual(r.status, 0, "部分失敗必須 exit≠0（否則會被 && chain 吞掉）：\n\(r.output)")
        XCTAssertTrue(r.output.contains("write failed"),
                      "要列出失敗項，不能只擲一句 Foundation 錯誤：\n\(r.output)")
        XCTAssertTrue(r.output.contains("部分完成"),
                      "不得印 ✓（那讀起來像全成功）：\n\(r.output)")
        // **這兩條才是 `AndKeepsGoing`**：失敗之後其餘候選仍被嘗試且真的寫進去。
        XCTAssertTrue(r.output.contains("national-taiwan-university"),
                      "失敗不得中斷後續候選：\n\(r.output)")
        XCTAssertEqual(try store.load().organizations.map(\.key),
                       ["national-taiwan-university"],
                       "印了還不夠——要真的落地（擋住「印了但沒寫進去」）")
    }
}
