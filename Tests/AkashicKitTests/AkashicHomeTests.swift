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

    /// explicit / env / legacy 三條路徑都沒有 key——照實回 nil，不猜。
    func testExplicitAndEnvAndLegacyHaveNoKey() throws {
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
