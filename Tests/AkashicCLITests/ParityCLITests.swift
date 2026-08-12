import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import akashic

/// #219：MCP–CLI parity 家族的其餘五格（`people`／`get-entry`／`link`／`tag`／
/// `set-status`）。`person` 那一格在 #218（`PersonCLITests`）。
///
/// **走真 binary、經 `CLITestHarness`**——理由同 `PersonCLITests` 檔首（#110/#114
/// 教訓不再複製一份）。**fixture 用已註冊 store**（`registerStore()`）——未註冊組態
/// 下 `store.key` 兩邊都是 nil，是唯一看不見 key-drop bug 的組態（#220 教訓）；
/// 寫入格經過 `writeAndReindex`，key 沒帶就會在 store root 長出第二份 index。
final class ParityCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-parity-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()

        var e1 = Entry(id: UUID(), citekey: "cheng2025alpha", type: "article",
                       title: "Alpha", authors: [.key("che-cheng")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e1)
        try store.writeEntry(Entry(id: UUID(), citekey: "cheng2024beta", type: "article",
                                   title: "Beta", authors: [.key("che-cheng")], date: "2024"))
        // 不含 che 的第三筆——防 people 過濾假綠
        try store.writeEntry(Entry(id: UUID(), citekey: "olsson1979max", type: "article",
                                   title: "Max", authors: [.literal("Ulf Olsson")], date: "1979"))

        try store.writePerson(Person(key: "che-cheng", names: ["Cheng, Che", "鄭澈"],
                                     authorized: ["Cheng, Che"]))
        try store.writePerson(Person(key: "solo-person", names: ["Solo Author"]))
        try registerStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 同 `PersonCLITests.registerStore`：沒有它，key-drop 失效模式不可達。
    @discardableResult
    private func registerStore(as key: String = "probe") throws -> String {
        let cfg = fakeHome.appendingPathComponent("config.yaml")
        try "files:\n  \(key): \(root.path)\ncurrent: \(key)\n"
            .write(to: cfg, atomically: true, encoding: .utf8)
        return key
    }

    /// 比對用 service。keyless 對本檔足夠：`people`／`getEntry` 走 `store.load()`
    /// 不經 index；index 分岔另由 `testWriteCommandsDoNotGrowASecondIndexInStoreRoot`
    /// 從檔案系統面守（那才是 key-drop 可觀察的位置）。
    private func service() throws -> AkashicService {
        AkashicService(root: root, environment: env)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    // MARK: people（讀取聚合）

    func testPeopleJSONIsServiceResponseVerbatim() throws {
        let (status, out) = try cli(["people", "--json"])
        XCTAssertEqual(status, 0, out)
        let expected = try service().people(query: nil)
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines),
                       expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testPeopleQueryFilters() throws {
        let (status, out) = try cli(["people", "che", "--json"])
        XCTAssertEqual(status, 0, out)
        XCTAssertTrue(out.contains("che-cheng"))
        XCTAssertFalse(out.contains("solo-person"))
    }

    func testPeopleHumanReadableListsBothPersons() throws {
        let (status, out) = try cli(["people"])
        XCTAssertEqual(status, 0, out)
        XCTAssertTrue(out.contains("che-cheng"), out)
        XCTAssertTrue(out.contains("solo-person"), out)
    }

    // MARK: get-entry（讀取聚合）

    func testGetEntryJSONIsServiceResponseVerbatim() throws {
        let (status, out) = try cli(["get-entry", "cheng2025alpha", "--json"])
        XCTAssertEqual(status, 0, out)
        let expected = try service().getEntry(citekey: "cheng2025alpha")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines),
                       expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testGetEntryHumanReadableShowsTitleAndCitekey() throws {
        let (status, out) = try cli(["get-entry", "cheng2025alpha"])
        XCTAssertEqual(status, 0, out)
        XCTAssertTrue(out.contains("Alpha"), out)
        XCTAssertTrue(out.contains("cheng2025alpha"), out)
    }

    func testGetEntryNotFoundExitsNonzero() throws {
        let (status, _) = try cli(["get-entry", "no-such-citekey"])
        XCTAssertNotEqual(status, 0)
    }

    // MARK: link（關係寫入）

    func testLinkAddPersistsCites() throws {
        let (status, out) = try cli(["link", "cheng2025alpha",
                                     "--kind", "cites", "--add", "cheng2024beta"])
        XCTAssertEqual(status, 0, out)
        let entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        let akashic = try XCTUnwrap(entry["akashic"] as? [String: Any], "\(entry)")
        XCTAssertEqual(akashic["cites"] as? [String], ["cheng2024beta"])
    }

    func testLinkRemoveDeletesEdge() throws {
        _ = try cli(["link", "cheng2025alpha", "--kind", "related", "--add", "cheng2024beta"])
        let (status, out) = try cli(["link", "cheng2025alpha",
                                     "--kind", "related", "--remove", "cheng2024beta"])
        XCTAssertEqual(status, 0, out)
        let entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        let akashic = entry["akashic"] as? [String: Any]
        XCTAssertNil(akashic?["related"])
    }

    func testLinkRejectsUnknownKind() throws {
        let (status, _) = try cli(["link", "cheng2025alpha", "--kind", "bogus",
                                   "--add", "cheng2024beta"])
        XCTAssertNotEqual(status, 0)
    }

    // MARK: tag（狀態寫入）

    func testTagAddThenRemovePersists() throws {
        let (s1, o1) = try cli(["tag", "cheng2025alpha", "--add", "irt", "--add", "sem"])
        XCTAssertEqual(s1, 0, o1)
        var entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        var akashic = try XCTUnwrap(entry["akashic"] as? [String: Any])
        XCTAssertEqual(akashic["tags"] as? [String], ["irt", "sem"])

        let (s2, o2) = try cli(["tag", "cheng2025alpha", "--remove", "irt"])
        XCTAssertEqual(s2, 0, o2)
        entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        akashic = try XCTUnwrap(entry["akashic"] as? [String: Any])
        XCTAssertEqual(akashic["tags"] as? [String], ["sem"])
    }

    func testTagNotFoundExitsNonzero() throws {
        let (status, _) = try cli(["tag", "no-such-citekey", "--add", "x"])
        XCTAssertNotEqual(status, 0)
    }

    // MARK: set-status（狀態寫入）

    func testSetStatusPersists() throws {
        let (status, out) = try cli(["set-status", "cheng2025alpha", "read"])
        XCTAssertEqual(status, 0, out)
        let entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        let akashic = try XCTUnwrap(entry["akashic"] as? [String: Any])
        XCTAssertEqual(akashic["status"] as? String, "read")
    }

    func testSetStatusClearRemoves() throws {
        _ = try cli(["set-status", "cheng2025alpha", "read"])
        let (status, out) = try cli(["set-status", "cheng2025alpha", "--clear"])
        XCTAssertEqual(status, 0, out)
        let entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        let akashic = entry["akashic"] as? [String: Any]
        XCTAssertNil(akashic?["status"])
    }

    // MARK: 手寫 guard 的負向測試（#219 verify F3／Codex A：這些是 CLI adapter
    // 自己新增、service 委派涵蓋不到的邏輯——guard 被刪掉時全套件仍會綠，除非在此釘住）

    func testLinkWithoutAddOrRemoveIsRejected() throws {
        let (status, _) = try cli(["link", "cheng2025alpha", "--kind", "cites"])
        XCTAssertNotEqual(status, 0)
    }

    func testTagWithoutAddOrRemoveIsRejected() throws {
        let (status, _) = try cli(["tag", "cheng2025alpha"])
        XCTAssertNotEqual(status, 0)
    }

    func testSetStatusWithNeitherValueNorClearIsRejected() throws {
        _ = try cli(["set-status", "cheng2025alpha", "read"])
        let (status, _) = try cli(["set-status", "cheng2025alpha"])
        XCTAssertNotEqual(status, 0, "漏值必須拒絕——靜默當 clear 會清掉既有狀態")
        // 且既有狀態不能被動到
        let entry = try json(try service().getEntry(citekey: "cheng2025alpha"))
        let akashic = try XCTUnwrap(entry["akashic"] as? [String: Any])
        XCTAssertEqual(akashic["status"] as? String, "read")
    }

    func testSetStatusWithBothValueAndClearIsRejected() throws {
        let (status, _) = try cli(["set-status", "cheng2025alpha", "read", "--clear"])
        XCTAssertNotEqual(status, 0)
    }

    // MARK: 過濾與消毒（#219 verify Codex B／F、security F1/F2）

    /// query「鄭」只命中 names（che-cheng 的「鄭澈」），不含任何 key 子字串——
    /// 實作退化成「只查 key」時本測試轉紅（Codex B：'che' 同時命中 key，抓不到）。
    func testPeopleFilterMatchesNameNotJustKey() throws {
        let (status, out) = try cli(["people", "鄭", "--json"])
        XCTAssertEqual(status, 0, out)
        XCTAssertTrue(out.contains("che-cheng"), out)
        XCTAssertFalse(out.contains("solo-person"))
    }

    /// 零結果訊息不回顯 query（security F2 探針：argv 未消毒，回顯即 raw ESC 進終端機）。
    func testZeroResultPeopleDoesNotEchoQuery() throws {
        let (status, out) = try cli(["people", "zz\u{1B}[31mQ\u{202E}x"])
        XCTAssertEqual(status, 0, out)
        XCTAssertFalse(out.contains("\u{1B}"), "raw ESC 進了終端機")
        XCTAssertFalse(out.contains("\u{202E}"), "raw bidi 進了終端機")
    }

    /// fields 的**鍵**是 quarantine 唯一不驗的裸格（verify D3）——entryDict 消毒後，
    /// 人可讀與 --json 兩面都不得再有 raw ESC／bidi。
    func testInjectedFieldKeyIsSanitizedInBothFaces() throws {
        let store = LibraryStore(root: root)
        var e = Entry(id: UUID(), citekey: "evil2026key", type: "article",
                      title: "Evil", authors: [.literal("X")], date: "2026")
        e.fields["\u{1B}[31mKEY\u{202E}BIDI"] = "benign-value"
        try store.writeEntry(e)
        for args in [["get-entry", "evil2026key"], ["get-entry", "evil2026key", "--json"]] {
            let (status, out) = try cli(args)
            XCTAssertEqual(status, 0, out)
            XCTAssertFalse(out.contains("\u{1B}"), "\(args)：raw ESC 進了輸出")
            XCTAssertFalse(out.contains("\u{202E}"), "\(args)：raw bidi 進了輸出")
        }
    }

    /// orcid／openalex 消毒（本 change 對既有 MCP consumer 唯一的行為變更）：
    /// 正常 identifier 逐字不變、legacy 髒值被消毒、person() 與 people() 一致。
    func testPeopleIdentifierSanitization() throws {
        let store = LibraryStore(root: root)
        var clean = Person(key: "clean-person", names: ["Clean"])
        clean.orcid = "0000-0002-1825-0097"
        try store.writePerson(clean)
        var dirty = Person(key: "dirty-person", names: ["Dirty"])
        dirty.orcid = "\u{1B}[31mevil\u{202E}"
        try store.writePerson(dirty)

        let payload = try service().people(query: nil)
        XCTAssertTrue(payload.contains("0000-0002-1825-0097"), "正常 ORCID 不得被改寫")
        XCTAssertFalse(payload.contains("\u{1B}"), "legacy 髒 ORCID 的 raw ESC 進了 payload")
        XCTAssertFalse(payload.contains("\u{202E}"))

        // person() 與 people() 對同一人給同一個 identifier
        let one = try service().person(key: "clean-person", name: nil, library: nil)
        XCTAssertTrue(one.contains("0000-0002-1825-0097"))
    }

    // MARK: index 不分岔（#220 教訓的機械防線，寫入格版）

    /// 寫入格經 `writeAndReindex`——key 被丟掉時 index 會落到 store root 的
    /// `.akashic/`（而非 `$AKASHIC_HOME/index/`），對已註冊 store 長出第二份
    /// 會漂移的 index。
    ///
    /// **斷言的是 index 檔，不是目錄**（同 `PersonCLITests.
    /// testRegisteredStoreDoesNotGrowASecondIndex` 的教訓）：`ensureLayout()` 對
    /// keyless 開啟的 store 本來就會建空的 `.akashic/`，而 setUp 正是那樣建
    /// fixture 的。真正的傷害是裡面長出 `.sqlite`。
    func testWriteCommandsDoNotGrowASecondIndexInStoreRoot() throws {
        let inStore = root.appendingPathComponent(".akashic")
        func inStoreIndexes() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: inStore.path)) ?? [])
                .filter { $0.hasSuffix(".sqlite") }
        }
        XCTAssertEqual(inStoreIndexes(), [], "前置：in-store 還不該有 index")

        _ = try cli(["link", "cheng2025alpha", "--kind", "cites", "--add", "cheng2024beta"])
        _ = try cli(["tag", "cheng2025alpha", "--add", "irt"])
        _ = try cli(["set-status", "cheng2025alpha", "read"])

        XCTAssertEqual(inStoreIndexes(), [],
                       "已註冊 store 內冒出 in-store index——寫入命令把 registry key 丟掉了（#220 的病）")
        let homeIdx = fakeHome.appendingPathComponent("index")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: homeIdx.path)) ?? []
        XCTAssertTrue(names.contains { $0.hasPrefix("probe") },
                      "index 應在 $AKASHIC_HOME/index/probe-*.sqlite，實際：\(names)")
    }
}
