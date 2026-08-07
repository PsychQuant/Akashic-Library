import XCTest
import Foundation
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
}
