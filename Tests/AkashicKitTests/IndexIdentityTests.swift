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
        XCTAssertTrue(try LibraryIndex.isCurrent(indexPath: store.indexURL,
                                                 expectedRoot: root))
        // 路徑別名（未 resolve 的 temp 前綴 /var vs /private/var）也要命中
        let alias = URL(fileURLWithPath: "/private" + root.path)
        if FileManager.default.fileExists(atPath: alias.path) {
            XCTAssertTrue(try LibraryIndex.isCurrent(indexPath: store.indexURL,
                                                     expectedRoot: alias),
                          "canonical 比對——別名不是別的 store")
        }
    }

    /// #121 verify (c) 的靶心：同一 indexURL、不同 store root → stale。
    func testIsCurrentRejectsForeignStoreIndex() throws {
        let store = makeStore(root: root, key: "main")
        _ = try LibraryIndex(store: store).rebuild()

        let otherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idother-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        XCTAssertFalse(try LibraryIndex.isCurrent(indexPath: store.indexURL,
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
        XCTAssertFalse(try LibraryIndex.isCurrent(indexPath: store.indexURL,
                                                  expectedRoot: root),
                       "舊 schema（無身分表）＝stale，升級後第一次使用自動重建")
    }

    func testMissingIndexIsStale() throws {
        XCTAssertFalse(try LibraryIndex.isCurrent(
            indexPath: root.appendingPathComponent("nonexistent.sqlite"),
            expectedRoot: root))
    }
}
