import XCTest
import Foundation
@testable import AkashicStoreIO

/// #37：index 位置由 registry key 決定，store root 只留 canonical。
final class AkashicHomeTests: XCTestCase {

    private let fakeHome = ["AKASHIC_HOME": "/tmp/akashic-home-test"]

    // MARK: - home 路徑

    func testHomeDefaultsToDotAkashicUnderUserHome() {
        let home = AkashicHome.directory(environment: [:])
        XCTAssertEqual(home.lastPathComponent, ".akashic")
        XCTAssertEqual(home.deletingLastPathComponent().path,
                       FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// `$AKASHIC_HOME` 是測試與多帳號情境的 escape hatch。
    func testHomeHonoursEnvironmentOverride() {
        XCTAssertEqual(AkashicHome.directory(environment: fakeHome).path,
                       "/tmp/akashic-home-test")
        XCTAssertEqual(AkashicHome.configURL(environment: fakeHome).path,
                       "/tmp/akashic-home-test/config.yaml")
        XCTAssertEqual(AkashicHome.indexDirectory(environment: fakeHome).path,
                       "/tmp/akashic-home-test/index")
    }

    func testIndexURLIsNamedByRegistryKey() {
        XCTAssertEqual(AkashicHome.indexURL(forKey: "main", environment: fakeHome).path,
                       "/tmp/akashic-home-test/index/main.sqlite")
        XCTAssertEqual(AkashicHome.indexURL(forKey: "teaching", environment: fakeHome).path,
                       "/tmp/akashic-home-test/index/teaching.sqlite")
    }

    // MARK: - LibraryStore 的雙軌 index 解析

    /// **已註冊**（有 key）→ index 在 store root **之外**。這是本 issue 的核心：
    /// store root 正是會進 Dropbox / git 的東西，live SQLite 不該住在同步樹裡。
    func testRegisteredStoreKeepsIndexOutsideStoreRoot() {
        let root = URL(fileURLWithPath: "/tmp/akashic-home-test")
        let store = LibraryStore(root: root, key: "main", environment: fakeHome)
        XCTAssertEqual(store.indexURL.path, "/tmp/akashic-home-test/index/main.sqlite")
        XCTAssertFalse(store.indexURL.path.contains("/.akashic/index.sqlite"),
                       "已註冊 store 不得回落 in-store 路徑")
    }

    /// **未註冊**（`--library <path>` 直指，多見於測試與一次性檢查）→ 回落 in-store。
    /// 那種 store 不在 registry 治理範圍內，強行給它 home 內的位置反而要發明命名規則。
    func testUnregisteredStoreFallsBackToInStoreIndex() {
        let root = URL(fileURLWithPath: "/tmp/some/adhoc/store")
        let store = LibraryStore(root: root, environment: fakeHome)
        XCTAssertEqual(store.indexURL.path, "/tmp/some/adhoc/store/.akashic/index.sqlite")
    }

    /// 兩個已註冊 store 的 index 不得碰撞。
    func testDistinctKeysGetDistinctIndexes() {
        let a = LibraryStore(root: URL(fileURLWithPath: "/tmp/a"), key: "main", environment: fakeHome)
        let b = LibraryStore(root: URL(fileURLWithPath: "/tmp/b"), key: "teaching", environment: fakeHome)
        XCTAssertNotEqual(a.indexURL, b.indexURL)
    }

    /// canonical 目錄仍相對 store root——搬 index 不得動到 canonical 的解析。
    func testCanonicalDirsStillRelativeToRoot() {
        let root = URL(fileURLWithPath: "/tmp/akashic-home-test")
        let store = LibraryStore(root: root, key: "main", environment: fakeHome)
        XCTAssertEqual(store.entriesDir.path, "/tmp/akashic-home-test/entries")
        XCTAssertEqual(store.peopleDir.path, "/tmp/akashic-home-test/people")
    }

    // MARK: - Locator 的 key 傳遞

    func testResolvedCarriesKeyFromRegistry() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("akashic-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("config.yaml")
        try """
        files:
          main: /tmp/store-main
        current: main
        """.write(to: cfg, atomically: true, encoding: .utf8)

        let r = try LibraryLocator.resolveDetailed(explicit: nil, environment: [:], configURL: cfg)
        XCTAssertEqual(r.root.path, "/tmp/store-main")
        XCTAssertEqual(r.key, "main", "registry 解析必須帶回 key，否則 index 會回落 in-store")
    }

    /// **未註冊的** explicit / env 路徑與 legacy `library:` 都沒有 key——照實回 nil，
    /// 不猜（#105 之後 explicit / env 對**已註冊**路徑會反查帶 key，見
    /// `testExplicitPathToRegisteredStoreCarriesKey`；本測試釘的是未命中面）。
    func testUnregisteredExplicitEnvAndLegacyHaveNoKey() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("akashic-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("config.yaml")
        try "library: /tmp/legacy-store\n".write(to: cfg, atomically: true, encoding: .utf8)

        XCTAssertNil(try LibraryLocator.resolveDetailed(
            explicit: "/tmp/x", environment: [:], configURL: cfg).key)
        XCTAssertNil(try LibraryLocator.resolveDetailed(
            explicit: nil, environment: ["AKASHIC_LIBRARY": "/tmp/y"], configURL: cfg).key)
        let legacy = try LibraryLocator.resolveDetailed(explicit: nil, environment: [:], configURL: cfg)
        XCTAssertEqual(legacy.root.path, "/tmp/legacy-store")
        XCTAssertNil(legacy.key, "legacy library: 沒有 key")
    }

    /// 既有的 `resolve` 簽章必須保持行為不變（只回 root）。
    func testLegacyResolveSignatureUnchanged() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("akashic-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("config.yaml")
        try "library: /tmp/legacy-store\n".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertEqual(try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: cfg).path,
                       "/tmp/legacy-store")
    }
}

/// #110 verify 的兩個回歸守衛。
extension AkashicHomeTests {
    /// `resolveDetailed` 的 `configURL` 預設必須由**同一份** `environment:` 推導——
    /// 舊預設讀 process env，測試注入 fake env 時 registry 仍解析到真實 home
    /// （#110 的「兩個答案」同構殘留）。
    /// #309：registry 值（`~/.akashic`）的 tilde 展開必須跟著注入的 HOME——
    /// R2 verify 事故的根因：`HOME=fake` 下 configURL 隔離了、registry **值**
    /// 卻仍經 NSHomeDirectory() 展開到真 home，三個寫入命令落進真 store。
    func testRegistryTildeExpansionFollowsInjectedHome() throws {
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-309-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fake) }
        let home = fake.appendingPathComponent("home")
        let akashic = home.appendingPathComponent(".akashic")
        try FileManager.default.createDirectory(at: akashic, withIntermediateDirectories: true)
        try "files:\n  main: ~/.akashic\ncurrent: main\n".write(
            to: akashic.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8)
        let env = ["AKASHIC_HOME": akashic.path, "HOME": home.path]
        let r = try LibraryLocator.resolveDetailed(explicit: nil, environment: env)
        XCTAssertEqual(r.root.standardizedFileURL.path,
                       akashic.standardizedFileURL.path,
                       "registry 的 ~ 必須依注入的 HOME 展開，不得落到真 home：\(r.root.path)")
    }

    func testResolveDetailedDefaultConfigFollowsInjectedEnvironment() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-locenv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "files:\n  fake: \(home.path)/store\ncurrent: fake\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let r = try LibraryLocator.resolveDetailed(
            explicit: nil, environment: ["AKASHIC_HOME": home.path])   // configURL 省略
        XCTAssertEqual(r.key, "fake",
                       "configURL 預設該從注入的 environment 推導，而非 process env")
    }

    /// #110 的相容性宣稱入庫：未設 `AKASHIC_HOME` 時，env-aware 解析與舊的寫死路徑
    /// **逐字等價**（此前只在 verify 時用 swiftc 探針驗過，沒有測試釘住）。
    func testConfigURLWithoutOverrideMatchesLegacyHardcodedPath() {
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/config.yaml")
        XCTAssertEqual(AkashicHome.configURL(environment: [:]).path, legacy.path)
    }
}

/// registry 反查（#105，使用者拍板）：`--library <已註冊路徑>` 的語意是「指定一個
/// store」不是「繞過 registry」——同一個 store 不因開法不同而有兩份會漂移的 index。
extension AkashicHomeTests {
    private func makeRegistry() throws -> (home: URL, store: URL, cleanup: () -> Void) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lookup-\(UUID().uuidString)")
        let home = tmp.appendingPathComponent("home")
        let store = tmp.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try "files:\n  main: \(store.path)\ncurrent: main\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        return (home, store, { try? FileManager.default.removeItem(at: tmp) })
    }

    /// 已註冊路徑經 `--library`（explicit）開啟 → 帶 key 回來。
    func testExplicitPathToRegisteredStoreCarriesKey() throws {
        let (home, store, cleanup) = try makeRegistry()
        defer { cleanup() }
        let r = try LibraryLocator.resolveDetailed(
            explicit: store.path, environment: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.key, "main", "路徑已註冊就該把 key 帶回來（#105 拍板：反查）")
        XCTAssertEqual(r.root.standardizedFileURL.path, store.standardizedFileURL.path)
    }

    /// `$AKASHIC_LIBRARY` 同理。
    func testEnvLibraryToRegisteredStoreCarriesKey() throws {
        let (home, store, cleanup) = try makeRegistry()
        defer { cleanup() }
        let r = try LibraryLocator.resolveDetailed(
            explicit: nil,
            environment: ["AKASHIC_HOME": home.path, "AKASHIC_LIBRARY": store.path])
        XCTAssertEqual(r.key, "main")
    }

    /// 未註冊路徑 → 維持 keyless（fallback 不變）。
    func testExplicitUnregisteredPathStaysKeyless() throws {
        let (home, _, cleanup) = try makeRegistry()
        defer { cleanup() }
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-unreg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        let r = try LibraryLocator.resolveDetailed(
            explicit: other.path, environment: ["AKASHIC_HOME": home.path])
        XCTAssertNil(r.key)
    }

    /// config 不存在 → keyless、**不擲錯**（explicit path 不依賴 registry 存在）。
    func testExplicitPathWithoutConfigStaysKeylessWithoutThrowing() throws {
        let ghostHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-nohome-\(UUID().uuidString)")
        let r = try LibraryLocator.resolveDetailed(
            explicit: "/tmp/whatever-store", environment: ["AKASHIC_HOME": ghostHome.path])
        XCTAssertNil(r.key)
    }

    /// 路徑正規化：尾斜線要比得中。
    func testLookupNormalizesPathForms() throws {
        let (home, store, cleanup) = try makeRegistry()
        defer { cleanup() }
        let r = try LibraryLocator.resolveDetailed(
            explicit: store.path + "/", environment: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.key, "main", "尾斜線不該讓反查失敗")
    }

    /// **symlink 命中**（#121 verify H1）：registry 存實路徑、使用者給 symlink——
    /// `~/Dropbox` 型部署正是 index 外移的初衷場景，反查必須解析 symlink。
    func testLookupResolvesSymlinks() throws {
        let (home, store, cleanup) = try makeRegistry()
        defer { cleanup() }
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: store)
        let r = try LibraryLocator.resolveDetailed(
            explicit: link.path, environment: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.key, "main", "經 symlink 開已註冊 store 必須反查得到")
    }

    /// tilde 形（真實 registry 的形狀：`main: ~/.akashic`）——registry 值帶 tilde 也要命中。
    func testLookupExpandsTildeInRegistryValue() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-tilde-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // registry 值用 tilde 寫；查詢用展開後的絕對路徑
        let expanded = ("~/Desktop" as NSString).expandingTildeInPath
        try "files:\n  desk: ~/Desktop\ncurrent: desk\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let r = try LibraryLocator.resolveDetailed(
            explicit: expanded, environment: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.key, "desk")
    }

    /// **malformed registry 必須擲錯**（#121 verify Codex）：`try?` 會把「registry
    /// 壞掉」當成「未註冊」→ 在已註冊 store 裡靜默寫第二份 index，且使用者拿不到
    /// 任何損壞診斷。只有「檔案不存在」才降級成 keyless。
    func testMalformedRegistryThrowsInsteadOfKeyless() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-badcfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let home = tmp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "files:\n  Bad Key!!: /tmp/x\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LibraryLocator.resolveDetailed(
            explicit: "/tmp/whatever", environment: ["AKASHIC_HOME": home.path]))
    }

    /// **重複註冊擲錯**（#121 verify H2）：`Dictionary` 反查非決定性——同 store 的
    /// 反查結果會逐 process 交替、交替寫兩份 index。≥2 命中 = registry 損壞，修它不猜它。
    func testDuplicateRegistrationThrows() throws {
        let (home, store, cleanup) = try makeRegistry()
        defer { cleanup() }
        try "files:\n  aaa: \(store.path)\n  zzz: \(store.path)\ncurrent: aaa\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LibraryLocator.resolveDetailed(
            explicit: store.path, environment: ["AKASHIC_HOME": home.path])) { error in
            guard case ConfigError.duplicateRegistration(_, let keys) = error else {
                return XCTFail("預期 duplicateRegistration，實得 \(error)")
            }
            XCTAssertEqual(keys, ["aaa", "zzz"], "keys 排序後回報，錯誤訊息可重現")
        }
    }
}
