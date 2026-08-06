import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicSQLite

/// #122：衍生 index 的 store 身分戳記。
///
/// 兩個實測過的病（#101 R2 DA、#121 verify (c)）：`isCurrent` 只看 schema
/// version——(1) 被誤寫的空 index 版本對就永不重建；(2) registry 路徑被重新
/// 利用（舊 store 刪、新 store 同路徑同 key）時讀到**別的 store**的 index，
/// `isCurrent` 照樣點頭。身分戳記讓「這份 index 是誰的」成為可比對的事實。
final class IndexIdentityTests: XCTestCase {
    private var home: URL!
    private var root: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idhome-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "aaa2020first", type: "article",
                                   title: "T", authors: [.literal("X")], date: "2020"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: home)
    }

    /// 沙箱鐵律：構造與目的地斷言同一動作（同 GraphModelTests.sandboxStore）。
    private func makeStore(root: URL, key: String?) -> LibraryStore {
        let store = LibraryStore(root: root, key: key,
                                 environment: ["AKASHIC_HOME": home.path])
        precondition(store.indexURL.path.hasPrefix(home.path + "/")
                     || store.indexURL.path.hasPrefix(root.path + "/"),
                     "indexURL 指向沙箱外：\(store.indexURL.path)")
        return store
    }

    func testRebuildStampsIdentity() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: true)
        let rows = try db.query("SELECT store_root, built_at, entry_count FROM index_identity")
        XCTAssertEqual(rows.count, 1, "身分戳記恰好一列")
        XCTAssertEqual(rows.first?["store_root"] as? String,
                       root.resolvingSymlinksInPath().path,
                       "store_root 是 canonical path（tilde 展開 + symlink 解析）")
        XCTAssertEqual(rows.first?["entry_count"] as? Int, 1)
        XCTAssertNotNil(rows.first?["built_at"] as? String)
    }

    func testIsCurrentAcceptsOwnIndexIncludingPathAliases() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()
        XCTAssertTrue(LibraryIndex.isCurrent(indexPath: store.indexURL,
                                             expectedRoot: root))
        // 路徑別名（未 resolve 的 temp 前綴 /var vs /private/var）也要命中。
        // XCTSkipUnless 讓「別名不存在的環境」顯式 skip 而非靜默空轉（verify F4）
        let alias = URL(fileURLWithPath: "/private" + root.path)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: alias.path),
                          "/private 別名在此環境不存在")
        XCTAssertTrue(LibraryIndex.isCurrent(indexPath: store.indexURL,
                                             expectedRoot: alias),
                      "canonical 比對——別名不是別的 store")
    }

    /// #121 verify (c) 的靶心：同一 indexURL、不同 store root → stale。
    func testIsCurrentRejectsForeignStoreIndex() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()

        let otherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idother-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        XCTAssertFalse(LibraryIndex.isCurrent(indexPath: store.indexURL,
                                              expectedRoot: otherRoot),
                       "別的 store 的 index 不是你的 index——root 不符即 stale")
    }

    /// registry 路徑重新利用的端到端：舊 store 刪除、新 store 同 key 同 indexURL
    /// → ensureCurrent 必須重建而不是沿用舊 index。
    func testEnsureCurrentRebuildsWhenRootChanges() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()

        // 新 universe：不同 root、同 key（→ 同 indexURL）
        let newRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idnew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: newRoot) }
        let newStore = makeStore(root: newRoot, key: "main")
        try newStore.ensureLayout()
        try newStore.writeEntry(Entry(id: UUID(), citekey: "bbb2021second", type: "article",
                                      title: "U", authors: [.literal("Y")], date: "2021"))
        XCTAssertEqual(store.indexURL.path, newStore.indexURL.path, "前置：同 key 同 indexURL")

        let rebuilt = try LibraryIndex(store: newStore).ensureCurrent()
        XCTAssertTrue(rebuilt, "root 變了必須重建——沿用舊 index 就是讀別人的資料")
        let db = try SQLiteDB(path: newStore.indexURL.path, readOnly: true)
        let citekeys = try db.query("SELECT citekey FROM entries").compactMap { $0["citekey"] as? String }
        XCTAssertEqual(citekeys, ["bbb2021second"], "重建後是新 store 的內容")
    }

    /// schema bump（2→3）：舊版 index 無身分表——一律 stale、自動重建一次。
    func testOldSchemaIndexIsStale() throws {
        let store = makeStore(root: root, key: "main")
        try FileManager.default.createDirectory(
            at: store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)
        try db.execute("CREATE TABLE entries(citekey TEXT)")
        try db.execute("PRAGMA user_version = 2")
        XCTAssertFalse(LibraryIndex.isCurrent(indexPath: store.indexURL,
                                              expectedRoot: root),
                       "舊 schema（無身分表）＝stale，升級後第一次使用自動重建")
    }

    func testMissingIndexIsStale() throws {
        XCTAssertFalse(LibraryIndex.isCurrent(
            indexPath: root.appendingPathComponent("nonexistent.sqlite"),
            expectedRoot: root))
    }

    /// #129 verify F1/F2 的核心閘：root 不像 store（unmount／path flap／打錯）
    /// → rebuild 拒絕、舊 index 原封不動——寫出身分正確的空 index 比留舊的更糟。
    func testRebuildRefusesNonLibraryRootAndPreservesOldIndex() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()
        let before = try Data(contentsOf: store.indexURL)

        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idghost-\(UUID().uuidString)")   // 不存在
        let ghostStore = makeStore(root: ghost, key: "main")   // 同 key → 同 indexURL
        XCTAssertThrowsError(try LibraryIndex(store: ghostStore).rebuild()) { error in
            guard case IndexError.rootNotALibrary = error else {
                return XCTFail("預期 rootNotALibrary，實得 \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.indexURL), before,
                       "拒絕重建時舊 index 必須原封不動——unmount 是暫時的，資料不是")
    }

    /// isCurrent 整體 fail-safe（#129 verify F3/C7）：非 SQLite 檔（Dropbox conflict
    /// copy、截斷寫入）＝stale，不是把指令炸掉。
    func testGarbageIndexFileIsStaleNotFatal() throws {
        let store = makeStore(root: root, key: "main")
        try FileManager.default.createDirectory(
            at: store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "this is not a sqlite database".write(to: store.indexURL,
                                                  atomically: true, encoding: .utf8)
        XCTAssertFalse(LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: root),
                       "壞檔＝stale（會被 rebuild 換掉），不得 throw")
        XCTAssertTrue(try LibraryIndex(store: store).ensureCurrent(), "接著正常重建")
    }

    /// `..`＋symlink 的 canonical 求值（#129 verify Codex-5 的反例場景）：
    /// macOS Foundation 實測走 traversal 語意（/a/link/../store → /b/store），
    /// 兩種求值順序同果——本測試釘住這個行為，防未來 helper 改寫時倒退。
    func testCanonicalPathResolvesDotDotThroughSymlinks() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-canon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        for d in ["b/child", "b/store", "a", "a/store"] {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("a/link"),
            withDestinationURL: base.appendingPathComponent("b/child"))
        let canon = LibraryIndex.canonicalRootPath(base.appendingPathComponent("a/link/../store"))
        XCTAssertTrue(canon.hasSuffix("/b/store"),
                      "`..` 穿過 symlink 必須走 traversal 語意（得 b/store），不是 lexical（a/store）：\(canon)")
    }

    /// **已知限制的文件測試**（#129 verify Codex-1）：canonical path 是位置不是
    /// 化身——同路徑同 key 的「store 重生」通過身分比對。這個測試斷言**現況**，
    /// 讓限制可見；incarnation id（store.yaml 內的 UUID）落地時翻轉此斷言。
    func testKnownLimitationSamePathReincarnationPassesIdentity() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()
        // 「重生」：整個 root 刪掉重建（新化身、同路徑）
        try FileManager.default.removeItem(at: root)
        let reborn = makeStore(root: root, key: "main")
        try reborn.ensureLayout()
        XCTAssertTrue(LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: root),
                      "已知限制：path-based 身分分不出同路徑的重生——需要 store incarnation id")
    }
}
