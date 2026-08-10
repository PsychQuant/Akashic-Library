import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import akashic

/// #218：CLI 的 person 讀取面。
///
/// **走真 binary**。這個 change 的價值全在**出口面**——「CLI 使用者能不能問出
/// 一個人寫了什麼」是關於 `akashic person` 這支命令存不存在。只測 service 層
/// 等於沒測到那句主張（同 `CreateEntryCLITests` 的理由，#206）。
final class PersonCLITests: XCTestCase {
    var root: URL!
    /// #37：index 住 `$AKASHIC_HOME/index/<key>.sqlite`。`person` 走 index，
    /// **不注入假 home 就會寫進使用者真實的 `~/.akashic/index/`**（實測發生過）。
    var fakeHome: URL!

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    private func runCLI(_ args: [String]) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = productsDirectory.appendingPathComponent("akashic")
        p.arguments = args + ["--library", root.path]
        // 先剝除所有 AKASHIC_*（沙箱紀律），再只放回假 home
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        env["AKASHIC_HOME"] = fakeHome.path
        p.environment = env
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        try p.run()
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: od, as: UTF8.self) + String(decoding: ed, as: UTF8.self))
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-person-cli-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()

        var e1 = Entry(id: UUID(), citekey: "cheng2025alpha", type: "article",
                       title: "Alpha", authors: [.key("che-cheng"), .literal("Hau-Hung Yang")],
                       date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e1)

        var e2 = Entry(id: UUID(), citekey: "cheng2024beta", type: "article",
                       title: "Beta", authors: [.key("che-cheng")], date: "2024")
        e2.fields["journaltitle"] = "BJMSP"
        try store.writeEntry(e2)

        // 第三筆**不含**本人——防「回傳全庫」這種假綠
        try store.writeEntry(Entry(id: UUID(), citekey: "olsson1979max", type: "article",
                                   title: "Max", authors: [.literal("Ulf Olsson")], date: "1979"))

        try store.writePerson(Person(key: "che-cheng", names: ["Cheng, Che", "鄭澈"],
                                     authorized: ["Cheng, Che"]))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func service() -> AkashicService {
        AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }

    /// 從人可讀輸出的「著作」區段抽 citekey（第一欄）。
    private func citekeysFromHumanOutput(_ out: String) -> Set<String> {
        var inPubs = false
        var keys: Set<String> = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("著作（") { inPubs = true; continue }
            if line.hasPrefix("合著者（") { inPubs = false; continue }
            guard inPubs, line.contains("\t") else { continue }
            keys.insert(String(line.split(separator: "\t")[0]))
        }
        return keys
    }

    // MARK: - 這個 change 的主張

    /// **命令存在，而且答得出「他寫了什麼」。**
    ///
    /// #218 的整句主張就是這件事——在此之前 CLI 有 24 個 subcommand，沒有一個能問。
    func testPersonCommandAnswersWhatSomeoneWrote() throws {
        let r = try runCLI(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("cheng2025alpha"), r.out)
        XCTAssertTrue(r.out.contains("cheng2024beta"), r.out)
        XCTAssertFalse(r.out.contains("olsson1979max"),
                       "不是本人的著作不該出現——回傳全庫也會讓上面兩條通過")
    }

    /// **CLI 與 service 不得分岔（本 change 的核心防線）。**
    ///
    /// 人可讀分支若哪天被「優化」成自己去問 `QueryEngine`，CLI 與 MCP 就成了
    /// 兩條各自重算的路徑——那正是 #218 在修的病（能力可用性取決於走哪個面）。
    /// 這條把「同一個回應的兩種排版」釘成規格。
    func testHumanReadableAgreesWithServiceOnPublications() throws {
        let human = try runCLI(["person", "che-cheng"])
        XCTAssertEqual(human.status, 0, human.out)

        let payload = try service().person(key: "che-cheng", name: nil, library: nil)
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let pubs = try XCTUnwrap(obj["publications"] as? [[String: Any]])
        let expected = Set(pubs.compactMap { $0["citekey"] as? String })

        XCTAssertFalse(expected.isEmpty, "fixture 壞了——service 自己就查不到著作")
        XCTAssertEqual(citekeysFromHumanOutput(human.out), expected,
                       "人可讀輸出與 service 的著作集合分岔了")
    }

    /// **`--json` 是 service 回應的原樣轉印**，不是 CLI 自己重組的第二種形狀。
    func testJSONIsServiceResponseVerbatim() throws {
        let r = try runCLI(["person", "che-cheng", "--json"])
        XCTAssertEqual(r.status, 0, r.out)
        let fromCLI = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any])
        let fromService = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(try service().person(key: "che-cheng", name: nil,
                                                library: nil).utf8)) as? [String: Any])
        XCTAssertEqual(
            Set((fromCLI["publications"] as? [[String: Any]] ?? []).compactMap { $0["citekey"] as? String }),
            Set((fromService["publications"] as? [[String: Any]] ?? []).compactMap { $0["citekey"] as? String }))
        XCTAssertNotNil(fromCLI["co_authors"], "co_authors 是 service 形狀的一部分，不得在 CLI 面消失")
    }

    /// **person 記錄不得儲存著作——衍生而非儲存（把設計裁決釘成規格）。**
    ///
    /// `work.authors` 已經是正典。在 person 再存一份就是第二份 canonical state，
    /// 歸戶／改名／刪除都要兩邊同步而它們會分岔。日後有人想加 `works:` 會在這裡紅。
    func testPersonRecordStoresNoWorks() throws {
        let people = try LibraryStore(root: root).load().people
        let p = try XCTUnwrap(people.first { $0.key == "che-cheng" })
        XCTAssertTrue(p.unknownFields.isEmpty, "fixture 不該有未知欄位")

        // 檔案層：落地的 YAML 不得出現任何指向 work 的欄位
        let dir = root.appendingPathComponent("entities")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var checked = 0
        for f in files where f.hasSuffix(".yaml") {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            // **必須是 person 記錄本身**。只比對 `key: che-cheng` 會連 work 一起收——
            // work 的 authors 槽裡就是那個字串（第一版這樣寫，命中 3 檔而非 1 檔）
            guard text.hasPrefix("person:"), text.contains("\nkey: che-cheng\n") else { continue }
            checked += 1
            for forbidden in ["works:", "publications:", "authored:", "entries:"] {
                XCTAssertFalse(text.contains(forbidden),
                               "person 記錄出現 `\(forbidden)`——著作應由 work.authors 反向算出，不得儲存")
            }
        }
        XCTAssertEqual(checked, 1, "沒找到（或找到多份）che-cheng 的記錄，斷言等於沒跑")
    }

    /// 未歸戶的合著者以 literal 呈現、**不**冒充 identity（同 `EntityRef` 的立場）。
    func testUnresolvedCoAuthorIsShownWithoutKey() throws {
        let r = try runCLI(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.out)
        // **必須限定在合著者區段**。同一個名字也出現在著作那行的 authors 欄，
        // 全文找第一個命中會抓到著作行（4 欄）而不是合著者行（第一版如此）
        let all = r.out.split(separator: "\n", omittingEmptySubsequences: false)
        let head = try XCTUnwrap(all.firstIndex { $0.hasPrefix("合著者（") },
                                 "沒有合著者區段：\n\(r.out)")
        let line = try XCTUnwrap(
            all[all.index(after: head)...].first { $0.contains("Hau-Hung Yang") },
            "未歸戶合著者應該出現在合著者區段：\n\(r.out)")
        XCTAssertEqual(line.split(separator: "\t").count, 2,
                       "未歸戶者不該有 person_key 欄——那會把未知偽裝成已解析")
    }

    /// 模糊名回**候選**，絕不自動選。
    func testNameLookupReturnsCandidates() throws {
        let r = try runCLI(["person", "--name", "鄭"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("候選"), r.out)
        XCTAssertTrue(r.out.contains("che-cheng"), r.out)
    }

    /// key 與 name 互斥的判準只有一份（在 service），CLI 不重寫。
    func testKeyAndNameAreMutuallyExclusive() throws {
        let r = try runCLI(["person", "che-cheng", "--name", "鄭"])
        XCTAssertNotEqual(r.status, 0, "同時給 key 與 name 應該被拒絕：\(r.out)")
    }

    /// 查不到的人是錯誤，不是空結果——與「有記錄但沒著作」是兩件事。
    func testUnknownPersonIsAnError() throws {
        let r = try runCLI(["person", "nobody-here"])
        XCTAssertNotEqual(r.status, 0, r.out)
    }
}
