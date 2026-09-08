import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

final class AppStateTests: XCTestCase {
    var root: URL!
    var state: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: .periodicalArticle,
                       title: "Maximum likelihood estimation",
                       authors: [.literal("Ulf Olsson")], date: "1979")
        e2.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                   orphanedAt: Date(timeIntervalSince1970: 1))
        try store.writeEntry(e2)
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        state = AppState(root: root)
        try state.load()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMutatePatchesFreshDiskStateNotStaleSnapshot() throws {
        // 模擬外部工具（CLI/MCP/Zotero pull）在 App 尚未 reload 時改了 biblatex face
        let store = LibraryStore(root: root)
        var external = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        external.title = "Updated externally"
        try store.writeEntry(external)
        // App 記憶體仍是舊 title；此時做一次衍生層編輯
        try state.addTag(citekey: "cheng2025identifiability", tag: "keeper")
        // 外部的 title 更新不得被舊快照蓋回去，衍生層編輯也要到位
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.title, "Updated externally",
                       "衍生層編輯不可用記憶體舊快照覆寫外部剛寫入的書目層")
        XCTAssertTrue(after.akashic.tags.contains("keeper"))
    }

    func testLoadBumpsReloadCount() throws {
        let before = state.reloadCount
        try state.load()
        XCTAssertEqual(state.reloadCount, before + 1,
                       "reloadCount 供 App 層 model 對外部變更重建之用")
    }

    func testExternalReloadStampsSyncTime() throws {
        XCTAssertNil(state.lastExternalSyncAt)
        let before = state.reloadCount
        try state.externalReload()
        XCTAssertNotNil(state.lastExternalSyncAt, "FileWatcher reload 要留下可顯示的同步時戳")
        XCTAssertEqual(state.reloadCount, before + 1)
    }

    func testLoadCountsMatchDoctorSemantics() {
        XCTAssertEqual(state.entries.count, 2)
        XCTAssertEqual(state.people.count, 1)
        XCTAssertEqual(state.unresolvedLiteralCount, 1)
        XCTAssertEqual(state.orphanedEntries.map(\.citekey), ["olsson1979maximum"])
        XCTAssertTrue(state.quarantined.isEmpty)
    }

    func testSearchAndTypeFilter() {
        state.searchText = "polychoric"
        XCTAssertEqual(state.filteredEntries.map(\.citekey), ["cheng2025identifiability"])
        state.searchText = ""
        state.filterTag = "identifiability"
        XCTAssertEqual(state.filteredEntries.count, 1)
    }

    func testDerivedLayerEditPersists() throws {
        try state.setStatus(citekey: "olsson1979maximum", status: "reading")
        try state.addTag(citekey: "olsson1979maximum", tag: "classic")
        let reloaded = try LibraryStore(root: root).load()
            .entries.first { $0.citekey == "olsson1979maximum" }!
        XCTAssertEqual(reloaded.akashic.status, "reading")
        XCTAssertEqual(reloaded.akashic.tags, ["classic"])
    }

    func testRenameThroughState() throws {
        _ = try state.rename(from: "olsson1979maximum", to: "olsson1979bmaximum")   // 不要報告就寫出來（#465：沒有 @discardableResult）
        XCTAssertNotNil(state.entries.first { $0.citekey == "olsson1979bmaximum" })
        XCTAssertNil(state.entries.first { $0.citekey == "olsson1979maximum" })
    }

    /// #465：App 面的 rename 要把 `RenameReport` 帶回來——relations、歧異候選、verdict 三類
    /// 連帶改寫各自可見。這裡釘 relations 與 verdict 兩類非空、歧異候選為空。
    func testRenameThroughStateReturnsTheMigrationReport() throws {
        try state.addRelation(citekey: "cheng2025identifiability", kind: .cites, target: "olsson1979maximum")
        let store = LibraryStore(root: root)
        var p = Person(key: "ulf-olsson", names: ["Ulf Olsson"])
        p.references = [ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: "olsson1979maximum", literal: "Ulf Olsson").encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))]
        try store.writePerson(p)
        try state.load()

        let report = try state.rename(from: "olsson1979maximum", to: "olsson1979bmaximum")

        XCTAssertEqual(report.relationsRewritten, ["cheng2025identifiability"])
        XCTAssertEqual(report.divergenceCandidatesRewritten, [])
        XCTAssertEqual(report.verdictValuesRewritten, [HolderRecord(.person, "ulf-olsson")])
        let cites = state.entries.first { $0.citekey == "cheng2025identifiability" }?.akashic.relations.cites
        XCTAssertEqual(cites, ["olsson1979bmaximum"], "報告說改了，store 也要真的改了")
        // Codex R1 建議：不只信報告，也核對持久化結果——person 的 verdict holder 真的變成新 citekey
        let migrated = try store.load().people.first { $0.key == "ulf-olsson" }?.references
            .compactMap { $0.value }.compactMap(ProvenanceReference.VerdictPairingValue.parse) ?? []
        XCTAssertEqual(migrated.map(\.holder), ["olsson1979bmaximum"], "報告說遷了，檔案也要真的遷了")
    }

    /// #465：App 面的摘要——三類各一行、零筆說零（「沒有連帶改寫」與「沒有報告」是兩件事）、
    /// 超過五筆截斷但計數保留。
    func testRenameReportSummaryListsAllThreeFamiliesAndTruncates() {
        let many = (1...7).map { "w\($0)" }
        let text = RenameReportSummary.lines(RenameReport(relationsRewritten: many,
                                                         divergenceCandidatesRewritten: [],
                                                         verdictValuesRewritten: [HolderRecord(.person, "some-person")]))
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4, "#495 起多一行 verdict 收攏：\(text)")
        XCTAssertEqual(lines[0], "relations 已遷移：7 筆（w1、w2、w3、w4、w5…）")
        XCTAssertEqual(lines[1], "歧異候選已遷移：0 筆")
        XCTAssertEqual(lines[2], "消解判定已遷移：1 筆（person「some-person」）",
                       "#498：帶 kind——跨型別同名鍵時分得出是哪一筆")
        XCTAssertEqual(lines[3], "verdict 收攏丟棄：0 筆", "#495：丟棄必須可見，零也要說")
        // 帶 from/to 的版本第一行說出改成了什麼——與一次不編輯的點擊不同形（DA-2）
        let full = RenameReportSummary.receipt(RenameReport(), from: "a2020a", to: "a2020b")
        XCTAssertEqual(full.split(separator: "\n").first.map(String.init), "✓ a2020a → a2020b")
        XCTAssertEqual(full.split(separator: "\n").count, 5)
        XCTAssertEqual(full, "✓ a2020a → a2020b\nrelations 已遷移：0 筆\n歧異候選已遷移：0 筆"
                           + "\n消解判定已遷移：0 筆\nverdict 收攏丟棄：0 筆")
    }

    /// 消毒與 CLI 同立場：控制字元被逃脫、超長 key 被截（displaySafe(max: 200)）。
    func testRenameSummarySanitizesKeys() {
        let long = String(repeating: "k", count: 260)
        let text = RenameReportSummary.lines(RenameReport(relationsRewritten: ["a\tb", long]))
        XCTAssertFalse(text.contains("\t"), "控制字元不得原樣進 alert")
        XCTAssertTrue(text.contains("a\\u{0009}b"), "displaySafe 的逃脫形是 \\u{XXXX}（含反斜線）：\(text)")
        XCTAssertFalse(text.contains(long), "260 字的 key 要被截")
    }

    /// 部分成功的錯誤描述帶著報告，且說出「已寫入磁碟」；純文字、無 Markdown。
    func testRenamedButReloadFailedDescriptionCarriesTheReport() {
        let e = AppStateError.renamedButReloadFailed(
            report: RenameReport(relationsRewritten: ["w1"]), underlying: "index boom")
        let d = e.errorDescription ?? ""
        XCTAssertTrue(d.contains("已寫入磁碟"), d)
        XCTAssertTrue(d.contains("index boom"), d)
        XCTAssertTrue(d.contains("relations 已遷移：1 筆（w1）"), d)
        XCTAssertFalse(d.contains("**"), "Text(String) 不解析 Markdown，星號會原樣顯示")
    }

    // MARK: - 部分成功：改名落盤但索引沒跟上（#492）

    /// 核心：**兩條分支都不丟報告**。在 #492 之前，reindex 失敗時 `attempt` 把錯誤壓成
    /// 一句話，那份「全庫改寫了什麼」的報告到不了呈現層——而那正是使用者最需要看到的東西
    /// （磁碟已經被改了，只是 App 的視圖過期）。
    func testPartialRenameStillShowsTheWholeReceipt() {
        let report = RenameReport(relationsRewritten: ["a2020a", "b2020b"],
                                  divergenceCandidatesRewritten: [],
                                  verdictValuesRewritten: [HolderRecord(.person, "some-person")])
        let ok = EntryDetailView.RenameOutcome(from: "x2020a", to: "x2020b", report: report)
        let partial = EntryDetailView.RenameOutcome(from: "x2020a", to: "x2020b", report: report,
                                                   reloadFailure: "index rebuild exploded")

        let okText = EntryDetailView.renameMessage(ok)
        let partialText = EntryDetailView.renameMessage(partial)
        XCTAssertEqual(okText, RenameReportSummary.receipt(report, from: "x2020a", to: "x2020b"),
                       "成功路徑逐字就是回執，不多不少")
        XCTAssertTrue(partialText.hasSuffix(okText),
                      "部分成功要含**完整**的成功回執——少一個字就是報告被丟了一部分：\(partialText)")
        XCTAssertTrue(partialText.hasPrefix("⚠ 改名已寫入磁碟"),
                      "警語在最前面：放最後會被四行摘要推下去、在短 alert 裡看不到")
        XCTAssertTrue(partialText.contains("index rebuild exploded"), partialText)
    }

    /// 標題也要說——使用者可能只看標題就按「好」。
    func testPartialRenameChangesTheAlertTitle() {
        let r = RenameReport()
        XCTAssertEqual(EntryDetailView.renameAlertTitle(nil), "已改名")
        XCTAssertEqual(EntryDetailView.renameAlertTitle(
            .init(from: "a", to: "b", report: r)), "已改名")
        XCTAssertEqual(EntryDetailView.renameAlertTitle(
            .init(from: "a", to: "b", report: r, reloadFailure: "boom")), "已改名，但索引未重建")
    }

    /// underlying 來自任意錯誤——控制字元不得原樣進 alert（同 CLI 立場）。
    func testPartialRenameSanitisesTheUnderlyingMessage() {
        let text = EntryDetailView.renameMessage(
            .init(from: "a", to: "b", report: RenameReport(), reloadFailure: "boom\there"))
        XCTAssertFalse(text.contains("\t"), "控制字元不得原樣進 alert：\(text)")
        XCTAssertTrue(text.contains("boom\\u{0009}here"), text)
    }

}

/// #13 多 library：AppState 的 libraries 載入與 filterLibrary 篩選。
extension AppStateTests {
    func testFilterLibraryScopesEntries() throws {
        let store = LibraryStore(root: root)
        try store.writeLibrary(Library(key: "sinica", name: "中研院"))
        var e = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        e.akashic.libraries = ["sinica"]
        try store.writeEntry(e)
        try state.load()

        XCTAssertEqual(state.libraries.map(\.key), ["sinica"], "registry 要載入 AppState")
        XCTAssertEqual(state.filteredEntries.count, 2, "未選 library＝全集")
        state.filterLibrary = "sinica"
        XCTAssertEqual(state.filteredEntries.map(\.citekey), ["cheng2025identifiability"])
        state.filterLibrary = nil
        XCTAssertEqual(state.filteredEntries.count, 2)
    }
}

/// #18 多檔案：App 端 registry 讀取與 root 切換（session-scoped）。
extension AppStateTests {
    private func makeUniverse(citekey: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-file-\(UUID().uuidString)")
        let store = LibraryStore(root: url)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: citekey, authors: [.literal("X")], date: "2020"))
        return url
    }

    func testSwitchFileSwapsUniverseAndResetsFilters() throws {
        let rootA = try makeUniverse(citekey: "aaa2020first")
        let rootB = try makeUniverse(citekey: "bbb2020second")
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-cfg-\(UUID().uuidString).yaml")
        var config = AkashicConfig()
        config.files = ["a": rootA.path, "b": rootB.path]
        config.current = "a"
        try config.write(to: configURL)

        let state = AppState(root: rootA, configURL: configURL)
        try state.load()
        XCTAssertEqual(state.availableFiles.map(\.key), ["a", "b"])
        XCTAssertEqual(state.entries.map(\.citekey), ["aaa2020first"])

        state.searchText = "殘留"
        state.filterLibrary = "ghost"
        try state.switchFile(key: "b")
        XCTAssertEqual(state.root.path, rootB.path)
        XCTAssertEqual(state.entries.map(\.citekey), ["bbb2020second"], "互不相通：整個 universe 換掉")
        XCTAssertEqual(state.searchText, "", "切換重置搜尋")
        XCTAssertNil(state.filterLibrary, "切換重置 library view（跨檔案殘留無意義）")
    }

    func testSwitchFileUnknownKeyThrows() throws {
        let rootA = try makeUniverse(citekey: "aaa2020first")
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-cfg-\(UUID().uuidString).yaml")
        try AkashicConfig(files: ["a": rootA.path]).write(to: configURL)
        let state = AppState(root: rootA, configURL: configURL)
        XCTAssertThrowsError(try state.switchFile(key: "ghost"))
    }
}

/// #18 verify R1：switchFile 失敗 rollback（root 標籤與資料不可分離）。
extension AppStateTests {
    func testSwitchFileRollsBackWhenNewUniverseLoadFails() throws {
        let rootA = try makeUniverse(citekey: "aaa2020first")
        // rootB：entries 是「檔案」不是目錄——guard 過（fileExists true）但 load() 必炸
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-broken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        try "not a directory".write(to: rootB.appendingPathComponent("entries"),
                                    atomically: true, encoding: .utf8)
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-app-cfg-\(UUID().uuidString).yaml")
        try AkashicConfig(files: ["a": rootA.path, "broken": rootB.path]).write(to: configURL)

        let state = AppState(root: rootA, configURL: configURL)
        try state.load()
        XCTAssertThrowsError(try state.switchFile(key: "broken"))
        XCTAssertEqual(state.root.path, rootA.path, "load 失敗 → root 回復舊 universe")
        XCTAssertEqual(state.entries.map(\.citekey), ["aaa2020first"], "舊快照 best-effort 重載")
    }
}

/// App 面必須與 CLI / MCP 一樣保留 registry key（#101 verify）。
///
/// 曾經 `AppState.store` 是 `LibraryStore(root: root)`——key 永遠 nil。後果是 App 對
/// **已註冊**的 store 也走 keyless 路徑：`reindexAndReload()` 會在 store root 內建出
/// `.akashic/` 並寫一份沒有任何消費者的 index（CLI / MCP 讀的是 `index/<key>.sqlite`），
/// 而且使用者刪掉 `.akashic/` 之後只要開 App 編輯一次就長回來。
final class AppStateRegistryKeyTests: XCTestCase {
    private var home: URL!
    private var root: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-apphome-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-appkey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: "main",
                         environment: ["AKASHIC_HOME": home.path]).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: home)
    }

    func testRegisteredStoreReindexDoesNotCreateInStoreIndex() throws {
        let state = AppState(root: root, key: "main", environment: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(state.storeKey, "main", "前置條件：key 有被保留")

        // **正面斷言目的地，而且在任何重建之前**（#101 verify R2）。
        //
        // 第一版只斷言「沒長出 `.akashic/`」——那個負面斷言**抓不到它要抓的事故**：
        // 若有人只拿掉 `environment:` 而保留 `key:`，key 非 nil 所以不會建 `.akashic/`，
        // `storeKey == "main"` 也仍成立，測試照樣綠燈——而 index 會寫進**使用者真實的**
        // `~/.akashic/index/main.sqlite`。那正是本測試存在的原因（實際發生過一次）。
        // **判準是「落在沙箱內」，不是「等於某個確切路徑」**。原本寫成路徑相等，
        // 於是 #130 把檔名改成 `main-<化身>.sqlite` 之後，這條守衛在一個它不在乎的
        // 維度上紅了——而它要抓的事故（environment 沒帶 → 寫進真實 home）完全沒變。
        // 同檔的 `GraphModelTests` 同款守衛一直是 prefix 形式，這裡對齊它。
        let indexDir = home.appendingPathComponent("index")
        guard state.store.indexURL.path.hasPrefix(indexDir.path + "/"),
              state.store.indexURL.lastPathComponent.hasPrefix("main") else {
            XCTFail("""
                indexURL 指向沙箱外——中止以免覆寫真實資料。
                expected: \(indexDir.path)/main*.sqlite
                actual:   \(state.store.indexURL.path)
                """)
            return
        }

        try state.load()
        try state.reindexAndReload()

        XCTAssertTrue(FileManager.default.fileExists(atPath: state.store.indexURL.path),
                      "已註冊 store 的 index 必須落在 <home>/index/<key>-<化身>.sqlite")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".akashic").path),
            "已註冊的 store 被 App reindex 之後不該長出 in-store 的 .akashic/")
    }

    /// `switchFile` 的 storeKey 更新與回滾（#101 verify R2：原本完全沒有斷言，
    /// 刪掉那兩行 706 個測試照樣全綠）。
    func testSwitchFileUpdatesAndRollsBackStoreKey() throws {
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-appkey2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        try LibraryStore(root: other, key: "other",
                         environment: ["AKASHIC_HOME": home.path]).ensureLayout()

        let cfg = home.appendingPathComponent("config.yaml")
        try "files:\n  main: \(root.path)\n  other: \(other.path)\ncurrent: main\n"
            .write(to: cfg, atomically: true, encoding: .utf8)

        let state = AppState(root: root, key: "main", configURL: cfg,
                             environment: ["AKASHIC_HOME": home.path])
        try state.load()

        try state.switchFile(key: "other")
        XCTAssertEqual(state.storeKey, "other", "切換成功後 key 必須跟著 root 走")
        XCTAssertEqual(state.root.path, other.path)

        // 切到不存在的 key → 擲錯且 key/root 都不動
        XCTAssertThrowsError(try state.switchFile(key: "nope"))
        XCTAssertEqual(state.storeKey, "other", "失敗的切換不得留下錯位的 key")
        XCTAssertEqual(state.root.path, other.path)
    }

    func testUnregisteredStoreStillUsesInStoreIndex() throws {
        let bare = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-appbare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bare) }
        try LibraryStore(root: bare).ensureLayout()

        let state = AppState(root: bare)          // key == nil
        XCTAssertNil(state.storeKey)
        try state.load()
        try state.reindexAndReload()

        // #130：index 檔名帶化身前綴。斷言「in-store 目錄裡有一個 index」，
        // 不斷言確切檔名——檔名綁化身是刻意的（把 TOCTOU 變成不可表達）。
        let inStore = (try? FileManager.default.contentsOfDirectory(
            atPath: bare.appendingPathComponent(".akashic").path)) ?? []
        XCTAssertTrue(
            inStore.contains { $0.hasPrefix("index") && $0.hasSuffix(".sqlite") },
            "未註冊的 store 仍回落 in-store index")
    }
}
