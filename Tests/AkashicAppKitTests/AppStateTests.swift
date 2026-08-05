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
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability of polychoric models",
                       authors: [.key("cheng-che")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        e1.akashic.tags = ["identifiability"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "olsson1979maximum", type: "article",
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
        try state.rename(from: "olsson1979maximum", to: "olsson1979bmaximum")
        XCTAssertNotNil(state.entries.first { $0.citekey == "olsson1979bmaximum" })
        XCTAssertNil(state.entries.first { $0.citekey == "olsson1979maximum" })
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
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: "article",
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
        let expected = home.appendingPathComponent("index").appendingPathComponent("main.sqlite")
        guard state.store.indexURL.path == expected.path else {
            XCTFail("""
                indexURL 指向沙箱外——中止以免覆寫真實資料。
                expected: \(expected.path)
                actual:   \(state.store.indexURL.path)
                """)
            return
        }

        try state.load()
        try state.reindexAndReload()

        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "已註冊 store 的 index 必須落在 <home>/index/<key>.sqlite")
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

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: bare.appendingPathComponent(".akashic/index.sqlite").path),
            "未註冊的 store 仍回落 in-store index")
    }
}
