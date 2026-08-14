import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import akashic

/// #218：CLI 的 person 讀取面。
///
/// **走真 binary**，且**經 `CLITestHarness`**——不自己複製 `runCLI`。那個 harness 的
/// 開頭就寫著它存在的理由（#110 verify：`runCLI` 曾被複製成三份，教訓註解沒跟過去）。
/// 本檔第一版又開了第四份，於是把兩條寫在 harness 註解裡的教訓一併丟掉：#114 的
/// pipe deadlock（單一 pipe、先讀 EOF 再 wait）與 `env` non-optional 的結構保證。
///
/// ## Fixture 分兩種，而且**已註冊**那一種是本檔的重點
///
/// 第一版全部用未註冊的臨時目錄（`--library <tmp>` 不在 registry）。那個組態下
/// `store.key` 兩邊都是 nil，**剛好是唯一看不見 key-drop bug 的組態**——於是
/// 「防分岔」的機械防線只在 bug 不會發生的地方綠燈。verify #220 的 4 個 lens 都
/// 指出這件事。所以 `registeredStore()` 是本檔的主力 fixture。
final class PersonCLITests: XCTestCase {
    var root: URL!
    /// #37：index 住 `$AKASHIC_HOME/index/<key>-<tag>.sqlite`。`person` 走 index，
    /// 不注入假 home 就會碰使用者真實的 home。
    ///
    /// **注意這句話對第一版是失效的**：key 被丟掉時 index 根本不去 home，而是進
    /// store root。假 home 注入當時是空轉的，而它遮住的正是那個 bug（#220 MEDIUM）。
    /// 現在 key 有帶了，這句話才真的成立——`testRegisteredStoreDoesNotGrowASecondIndex`
    /// 是它的機械證據。
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-person-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
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

        var p = Person(key: "che-cheng", names: ["Cheng, Che", "鄭澈"],
                       authorized: ["Cheng, Che"])
        // 一個已歸戶、一個未歸戶——隸屬的兩種狀態都要被呈現面覆蓋
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .key("national-taiwan-university"),
                          range: DateRange(start: "2015", end: "2021")),
            TemporalValue(value: .literal("Academia Sinica"), range: DateRange()),
        ])
        try store.writePerson(p)
        // 獨著者：合著者為空的呈現面要能被測
        try store.writePerson(Person(key: "solo-person", names: ["Solo Author"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "solo2020only", type: "article",
                                   title: "Only", authors: [.key("solo-person")], date: "2020"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 把本 fixture 的 store 註冊進假 home 的 registry，回傳 registry key。
    ///
    /// **這是本檔最重要的 helper。** 沒有它，`store.key` 永遠是 nil，而 key-drop
    /// 的整個失效模式不可達。
    @discardableResult
    private func registerStore(as key: String = "probe") throws -> String {
        let cfg = fakeHome.appendingPathComponent("config.yaml")
        try "files:\n  \(key): \(root.path)\ncurrent: \(key)\n"
            .write(to: cfg, atomically: true, encoding: .utf8)
        return key
    }

    private func service() -> AkashicService {
        AkashicService(root: root, environment: env)
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

    // MARK: - key-drop（verify #220 的 HIGH，4 個 lens 獨立命中）

    /// **已註冊的 store 不得長出第二份 index。**
    ///
    /// `PersonCmd` 若省略 `AkashicService(key:)`，service 內的 store 是 keyless →
    /// `indexURL` 從 `$AKASHIC_HOME/index/<key>-<tag>.sqlite` 回落到 in-store 的
    /// `<root>/.akashic/index-<tag>.sqlite`，於是 CLI 與 MCP／`query` 讀兩份不同的
    /// index。`doctor` 對那個目錄的判詞是「可刪」，而預設組態下 store root 就是
    /// 使用者的 `~/.akashic`（git + Dropbox 同步樹）。
    ///
    /// **第一版測試碰不到這個**：fixture 未註冊 → 兩側都 keyless → 剛好共用同一個
    /// in-store index。註冊起來才是 bug 可達的組態。
    func testRegisteredStoreDoesNotGrowASecondIndex() throws {
        try registerStore()
        // **斷言的是 index 檔，不是目錄**：`ensureLayout()` 對 keyless 開啟的 store
        // 本來就會建空的 `.akashic/`（`LibraryStore.swift` 的 `if key == nil`），而
        // setUp 正是那樣建 fixture 的。真正的傷害是**裡面長出 index**。
        let inStore = root.appendingPathComponent(".akashic")
        func inStoreIndexes() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: inStore.path)) ?? [])
                .filter { $0.hasSuffix(".sqlite") }
        }
        XCTAssertEqual(inStoreIndexes(), [], "前置：in-store 還不該有 index")

        let r = try cli(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.output)

        XCTAssertEqual(
            inStoreIndexes(), [],
            "已註冊的 store 內冒出 in-store index —— registry key 在 AkashicService 建構時被丟掉了")
        // 正面斷言：index 應該落在 home
        let homeIdx = fakeHome.appendingPathComponent("index")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: homeIdx.path)) ?? []
        XCTAssertTrue(names.contains { $0.hasPrefix("probe") },
                      "index 應在 $AKASHIC_HOME/index/probe-*.sqlite，實際：\(names)")
    }

    /// **`person` 的 index 重建必須讓 `query` 也看到。**
    ///
    /// 第一版是「兩支命令跑一次、比集合相等」——**那條在突變下照樣綠**（實測）：
    /// 兩份 index 都從同一份資料建出來，答案自然相同。分岔只在**其中一份過期**時
    /// 才顯現，所以測試必須製造那個時間差。
    ///
    /// 機制：`query` 走 `ensureCurrent()`（只驗 schema／root／incarnation，**不看
    /// mtime**），`person` 走 `ensureFreshIndex()`（看 mtime 會重建）。
    ///
    /// - 共用同一份 → person 的重建順便把 query 的答案修好 → query 看到新的那筆
    /// - 各自一份 → query 永遠停在舊答案
    func testPersonRefreshIsVisibleToQuery() throws {
        try registerStore()

        // ① query 先建 index（此時 2 筆）
        let before = try cli(["query", "--author", "che-cheng"])
        XCTAssertEqual(before.status, 0, before.output)
        XCTAssertFalse(before.output.contains("cheng2026gamma"))

        // ② 繞過 CLI 直接寫第三筆——index 因此過期
        try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "cheng2026gamma", type: "article",
                  title: "Gamma", authors: [.key("che-cheng")], date: "2026"))

        // ③ person 會依 mtime 重建它讀的那份 index
        let p = try cli(["person", "che-cheng"])
        XCTAssertEqual(p.status, 0, p.output)
        XCTAssertTrue(p.output.contains("cheng2026gamma"),
                      "person 沒看到新資料——它連自己那份 index 都沒重建：\n\(p.output)")

        // ④ 關鍵：query 現在該看得到了。看不到 = person 重建的是**另一份** index
        let after = try cli(["query", "--author", "che-cheng"])
        XCTAssertEqual(after.status, 0, after.output)
        XCTAssertTrue(after.output.contains("cheng2026gamma"),
                      "person 重建之後 query 仍看不到新資料——兩支命令讀的是兩份不同的 "
                      + "index（registry key 被丟掉）。query 輸出：\n\(after.output)")
    }

    /// **每一個從 CLI 建 `AkashicService` 的地方都必須帶 `key:`。**
    ///
    /// 行為測試（上面兩條）只覆蓋 `person`。key-drop 是**同源缺陷**——
    /// `update-person`／`create-entry` 抄的是同一個 keyless 寫法，本 PR 是第三次
    /// 複製它。行為面它們現在不炸（寫入路徑，答案不取自 index），所以只有源碼層的
    /// 斷言擋得住「第四次複製」。
    ///
    /// 這是**文字掃描**，不是型別保證——它的價值在於下一個人 grep 得到理由。
    func testEveryCLIServiceConstructionPassesRegistryKey() throws {
        let cliDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicCLITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/akashic")
        let swiftFiles = try FileManager.default
            .contentsOfDirectory(atPath: cliDir.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(swiftFiles.isEmpty, "找不到 Sources/akashic —— 斷言會空跑")

        var constructions = 0
        for f in swiftFiles {
            let text = try String(contentsOf: cliDir.appendingPathComponent(f), encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("AkashicService(root:") {
                constructions += 1
                XCTAssertTrue(line.contains("key: store.key"),
                              "\(f) 建 AkashicService 沒帶 registry key —— 已註冊的 store "
                              + "會被當成 keyless 而長出第二份 index（#220 HIGH）：\(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(constructions, 12,
                       "預期 person／update-person／create-entry + #219 五格"
                       + "（people／get-entry／link／tag／set-status）+ #232 的 "
                       + "resolve-people reject 與 apply + #250 兩格"
                       + "（add-person／divergences），共十二處；實際 \(constructions) 處——"
                       + "多出來的新呼叫點請一併確認有帶 key，然後更新這個數字")
    }

    // MARK: - 這個 change 的主張

    func testPersonCommandAnswersWhatSomeoneWrote() throws {
        let r = try cli(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("cheng2025alpha"), r.output)
        XCTAssertTrue(r.output.contains("cheng2024beta"), r.output)
        XCTAssertFalse(r.output.contains("olsson1979max"),
                       "不是本人的著作不該出現——回傳全庫也會讓上面兩條通過")
    }

    /// **CLI 與 service 不得分岔。**
    func testHumanReadableAgreesWithServiceOnPublications() throws {
        let human = try cli(["person", "che-cheng"])
        XCTAssertEqual(human.status, 0, human.output)

        let payload = try service().person(key: "che-cheng", name: nil, library: nil)
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let pubs = try XCTUnwrap(obj["publications"] as? [[String: Any]])
        let expected = Set(pubs.compactMap { $0["citekey"] as? String })

        XCTAssertFalse(expected.isEmpty, "fixture 壞了——service 自己就查不到著作")
        XCTAssertEqual(citekeysFromHumanOutput(human.output), expected,
                       "人可讀輸出與 service 的著作集合分岔了")
    }

    /// **`--json` 是逐字轉印**——名副其實的 verbatim。
    ///
    /// 第一版名為 verbatim，實際只比 `publications[].citekey` 的集合 + `co_authors`
    /// 非 nil。任何「長出第二種形狀」的改動（拿掉 `person` 區塊、欄位改名、多包一層
    /// envelope、截斷 title）都會通過（#220 MEDIUM）。`jsonString` 用
    /// `[.prettyPrinted, .sortedKeys]`，輸出是決定性的，所以可以直接比字串。
    func testJSONIsServiceResponseVerbatim() throws {
        let r = try cli(["person", "che-cheng", "--json"])
        XCTAssertEqual(r.status, 0, r.output)
        let expected = try service().person(key: "che-cheng", name: nil, library: nil)
        XCTAssertEqual(r.output.trimmingCharacters(in: .newlines),
                       expected.trimmingCharacters(in: .newlines),
                       "--json 不是逐字轉印——CLI 面長出了第二種形狀")
    }

    // MARK: - 衍生而非儲存（型別層，不是 fixture 層）

    /// **`Person` 型別本身不得有 works 成員。**
    ///
    /// 第一版對 fixture 落地的 YAML 做字串比對。但本 repo 的序列化慣例是**空集合
    /// 不輸出**，所以真正要防的那個動作——有人在 `Person` 加
    /// `public var works: [String] = []`——那條測試會照樣綠（#220 MEDIUM，3 個 lens）。
    /// 它只證明「這份 fixture 沒有 works」，證不到「這個型別不能有 works」。
    func testPersonTypeHasNoWorksMember() throws {
        let members = Mirror(reflecting: Person(key: "x")).children.compactMap(\.label)
        XCTAssertFalse(members.isEmpty, "反射拿不到成員——這條斷言會空跑")
        for forbidden in ["works", "publications", "authored", "entries", "entryKeys"] {
            XCTAssertFalse(members.contains(forbidden),
                           "`Person.\(forbidden)` 出現了——著作應由 work.authors 反向算出，"
                           + "存第二份就是第二份 canonical state。成員：\(members)")
        }
    }

    /// **手寫的 `works:` 必須落進 `unknownFields`，不得被提升成 typed 欄位。**
    ///
    /// 上一條從型別面守；這條從 tolerant-preserve 的反向守——即使有人繞過型別
    /// 直接讓 decoder 認得 `works:`，這條會紅。
    func testHandWrittenWorksFieldLandsInUnknownFields() throws {
        // **不手寫整份 YAML**——那樣測到的可能只是我把格式寫錯（第一版就是：
        // 記錄根本沒被載入，斷言 XCTUnwrap 失敗而非驗到 unknownFields）。改成
        // 用 store 寫一份合法的，再**只追加** `works:`：base 一定有效，變因只有一個。
        let store = LibraryStore(root: root)
        try store.writePerson(Person(key: "probe-person", names: ["Probe"]))

        let dir = root.appendingPathComponent("entities")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        var target: URL?
        for f in files where f.hasSuffix(".yaml") {
            let u = dir.appendingPathComponent(f)
            let t = try String(contentsOf: u, encoding: .utf8)
            if t.hasPrefix("person:"), t.contains("\nkey: probe-person\n") { target = u; break }
        }
        let f = try XCTUnwrap(target, "找不到剛寫的 probe-person 記錄")
        var text = try String(contentsOf: f, encoding: .utf8)
        if !text.hasSuffix("\n") { text += "\n" }
        try (text + "works:\n- cheng2025alpha\n").write(to: f, atomically: true, encoding: .utf8)

        let p = try XCTUnwrap(store.load().people.first { $0.key == "probe-person" },
                              "追加 works: 之後記錄整個載不進來——那是 decode 壞了，不是 tolerant-preserve")
        XCTAssertTrue(p.unknownFields.contains { $0.key == "works" },
                      "`works:` 沒落進 unknownFields——它被提升成 typed 欄位了。"
                      + "unknownFields=\(p.unknownFields.map(\.key))")
    }

    // MARK: - 呈現面不變式（規則檔新訂的，先前零覆蓋）

    /// **隸屬要看得到**——規則封閉列舉第 7 條，且是存在 person 自己身上的邊。
    ///
    /// 第一版只斷言三個子字串出現，**對整個時間區間全盲**：刪掉 `period` 計算照樣
    /// 全綠，而那正是 R2 四個 lens 報的 HIGH（`endedUnknown` 被折成現職）。
    /// DA 的原話是「等作者補上 endedUnknown／attested 之後，仍然沒有任何測試能防止
    /// 它再度退化」。所以本條現在斷言**期間本身**。
    func testAffiliationsAreShown() throws {
        let r = try cli(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("national-taiwan-university"),
                      "已歸戶的隸屬沒出現：\n\(r.output)")
        XCTAssertTrue(r.output.contains("Academia Sinica"),
                      "未歸戶的隸屬沒出現：\n\(r.output)")
        XCTAssertTrue(r.output.contains("（未歸戶）"),
                      "未歸戶者沒被標示——那會把 literal 冒充成 identity")
        // **期間必須出現**：fixture 是 2015–2021，輸出不含 2021 就代表 period 沒印
        XCTAssertTrue(r.output.contains("2021"),
                      "隸屬的結束年沒出現——period 計算被拿掉了也會讓上面三條全綠：\n\(r.output)")
    }

    /// **`DateRange` 的四個時間狀態必須互相可辨**（R2 verify HIGH，四個 lens 命中）。
    ///
    /// `endedUnknown`（#63）與 `attested`（#70）是一等的知識狀態，不是裝飾。把
    /// 「已結束、時點未知」印成跟「進行中」一樣，是對真人的**假陳述**——而且這個面
    /// 同時是 CLI 與 MCP（直達 LLM）。`RelationalExport` 有輸出 `ended_unknown`，
    /// 漏掉等於讓兩個衍生面對同一筆記錄互相矛盾。
    func testAffiliationTemporalStatesAreDistinguishable() throws {
        var p = Person(key: "four-states", names: ["Four States"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .key("org-ongoing"), range: DateRange(start: "2003")),
            TemporalValue(value: .key("org-ended-unknown"),
                          range: DateRange(start: "2003", endedUnknown: true)),
            TemporalValue(value: .key("org-closed"),
                          range: DateRange(start: "2003", end: "2008")),
            TemporalValue(value: .key("org-attested"),
                          range: DateRange(attested: ["2019", "2021"])),
        ])
        try LibraryStore(root: root).writePerson(p)

        let out = try cli(["person", "four-states"]).output
        func period(_ orgKey: String) -> String {
            let line = out.split(separator: "\n").first { $0.contains(orgKey) } ?? ""
            return String(line).replacingOccurrences(of: orgKey, with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        let ongoing = period("org-ongoing")
        let endedUnknown = period("org-ended-unknown")
        let closed = period("org-closed")
        let attested = period("org-attested")

        for (label, v) in [("ongoing", ongoing), ("ended-unknown", endedUnknown),
                           ("closed", closed), ("attested", attested)] {
            XCTAssertFalse(v.isEmpty, "\(label) 那一行沒有期間資訊：\n\(out)")
        }
        // **核心斷言**：四種狀態兩兩不同。任兩個相同 = 一個事實被冒充成另一個
        XCTAssertEqual(Set([ongoing, endedUnknown, closed, attested]).count, 4,
                       "四種時間狀態沒有互相區分——"
                       + "ongoing=\(ongoing) endedUnknown=\(endedUnknown) "
                       + "closed=\(closed) attested=\(attested)\n\(out)")
        // 具名斷言：最危險的那一對（#63 的整個存在理由）
        XCTAssertNotEqual(ongoing, endedUnknown,
                          "「已結束、時點未知」與「進行中」逐字相同——那 43 位退休 PI "
                          + "會被全部呈現成現職（DateRange.endedUnknown 的 doc 原話）")
        XCTAssertTrue(attested.contains("2019") && attested.contains("2021"),
                      "attested 的觀測點沒印出來：\(attested)")
    }

    /// 空的隸屬也要說出來（規則執行細節 4；同一輪剛把 co_authors 的省略判為 bug）。
    func testEmptyAffiliationsSectionIsStatedNotOmitted() throws {
        let r = try cli(["person", "solo-person"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("affiliations（0）"),
                      "整段消失 → 分辨不出「沒有隸屬記錄」與「這一段掉了」：\n\(r.output)")
    }

    /// **空集合要說出來**（規則執行細節 4）。獨著者也要看到「合著者（0）」。
    func testEmptyCoAuthorSectionIsStatedNotOmitted() throws {
        let r = try cli(["person", "solo-person"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("合著者（0）"),
                      "整段消失 → 分辨不出「沒有合著者」與「這一段掉了」：\n\(r.output)")
    }

    /// 未歸戶的合著者以 literal 呈現、**不**冒充 identity。
    func testUnresolvedCoAuthorIsShownWithoutKey() throws {
        let r = try cli(["person", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.output)
        let all = r.output.split(separator: "\n", omittingEmptySubsequences: false)
        let head = try XCTUnwrap(all.firstIndex { $0.hasPrefix("合著者（") },
                                 "沒有合著者區段：\n\(r.output)")
        let line = try XCTUnwrap(
            all[all.index(after: head)...].first { $0.contains("Hau-Hung Yang") },
            "未歸戶合著者應該出現在合著者區段：\n\(r.output)")
        XCTAssertEqual(line.split(separator: "\t").count, 2,
                       "未歸戶者不該有 person_key 欄——那會把未知偽裝成已解析")
    }

    // MARK: - 候選（--name）

    /// 模糊名回**候選**，絕不自動選。
    func testNameLookupReturnsCandidates() throws {
        let r = try cli(["person", "--name", "鄭"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("候選"), r.output)
        XCTAssertTrue(r.output.contains("che-cheng"), r.output)
    }

    /// **未歸戶的候選不得佔用 key 欄位。**
    ///
    /// 第一版印 `person_key ?? literal` 在同一欄，使用者照著複製回去會撞 notFound，
    /// 而 JSON 面明明保留了區分（#220 MEDIUM）。
    func testUnresolvedCandidateDoesNotOccupyKeyColumn() throws {
        let r = try cli(["person", "--name", "Olsson"])
        XCTAssertEqual(r.status, 0, r.output)
        let line = try XCTUnwrap(
            r.output.split(separator: "\n").first { $0.contains("Ulf Olsson") },
            "未歸戶候選沒出現：\n\(r.output)")
        XCTAssertEqual(line.split(separator: "\t").count, 2,
                       "未歸戶候選多了一欄——literal 佔了 identity 的位置：\(line)")

        // 對照：已歸戶的候選**有** key 欄
        let r2 = try cli(["person", "--name", "鄭"])
        let l2 = try XCTUnwrap(
            r2.output.split(separator: "\n").first { $0.contains("che-cheng") })
        XCTAssertEqual(l2.split(separator: "\t").count, 3,
                       "已歸戶候選應為 計數／名字／key 三欄：\(l2)")
    }

    // MARK: - 旗標語意

    /// `--in-library` 在 `--name` 模式下**明確拒絕**，不靜默忽略。
    ///
    /// service 的 name 分支沒讀 library 參數（候選計數掃全庫），靜默接受會給出
    /// 看起來被過濾過、實際沒有的數字（#220 MEDIUM）。
    func testInLibraryIsRefusedInNameMode() throws {
        let r = try cli(["person", "--name", "鄭", "--in-library", "no-such-lib"])
        XCTAssertNotEqual(r.status, 0, "應該被拒絕而不是靜默忽略：\n\(r.output)")
        XCTAssertTrue(r.output.contains("--in-library"), r.output)
    }

    /// `--in-library` 在 key 模式**確實過濾**（先前這個新旗標零覆蓋，#220 LOW）。
    ///
    /// 同時釘住一個容易誤讀的行為：指到不存在的 library key 會回「著作（0）（無）」
    /// 而不是錯誤。那是 service 的既有語意（成員資格是 per-entry 標記，沒有
    /// library registry 存在性檢查），本 change 不改它——但至少要有測試說出來，
    /// 否則「打錯 library 名」與「這個人在該 library 零篇」在輸出上完全相同。
    func testInLibraryFiltersInKeyMode() throws {
        let all = try cli(["person", "che-cheng"])
        XCTAssertTrue(citekeysFromHumanOutput(all.output).count >= 2, all.output)

        let none = try cli(["person", "che-cheng", "--in-library", "no-such-lib"])
        XCTAssertEqual(none.status, 0, none.output)
        XCTAssertTrue(none.output.contains("著作（0）"),
                      "不存在的 library key 應回零篇（既有語意，非本 change 引入）：\n\(none.output)")
        XCTAssertTrue(none.output.contains("che-cheng"),
                      "person 記錄本身仍要顯示——library 過濾只影響著作")
    }

    /// key 與 name 互斥的判準只有一份（在 service），CLI 不重寫。
    func testKeyAndNameAreMutuallyExclusive() throws {
        let r = try cli(["person", "che-cheng", "--name", "鄭"])
        XCTAssertNotEqual(r.status, 0, "同時給 key 與 name 應該被拒絕：\(r.output)")
    }

    /// 查不到的人是錯誤，不是空結果——與「有記錄但沒著作」是兩件事。
    func testUnknownPersonIsAnError() throws {
        let r = try cli(["person", "nobody-here"])
        XCTAssertNotEqual(r.status, 0, r.output)
    }
}
