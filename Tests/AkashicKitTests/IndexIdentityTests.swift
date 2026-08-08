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
        // #130 之前這裡斷言「同 key 同 indexURL」，因為 index 檔名只由 key 決定，
        // 於是兩個不同的 store 共用一個檔案、只能靠身分戳記分辨。**化身落地後
        // 檔名自己就分開了**——這是同一個保護往前挪一層，不是保護消失。
        XCTAssertNotEqual(store.indexURL.path, newStore.indexURL.path,
                          "不同化身的 index 是不同檔案（#130 裁決 3）")

        let rebuilt = try LibraryIndex(store: newStore).ensureCurrent()
        XCTAssertTrue(rebuilt, "root 變了必須重建——沿用舊 index 就是讀別人的資料")
        // **戳記那一層仍要成立**（縱深防禦）：就算有人把舊檔改成新名字，
        // `store_root` 不符照樣判 stale。
        XCTAssertFalse(LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: newRoot,
                                              expectedIncarnation: newStore.incarnation),
                       "舊 store 的 index 對新 root 必須是 stale")
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
    /// **同路徑重生**（#130）。這條原本是 `testKnownLimitation…PassesIdentity`，
    /// 斷言 `isCurrent == true` 並附註「已知限制」。化身 id 落地後翻轉。
    ///
    /// 兩層保護，**主要在檔名**：重生後的 store 有新的 incarnation，於是它的
    /// `indexURL` 是**另一個檔案**——舊 index 不是「被判 stale」，是根本不會被
    /// 拿去比對。這把 TOCTOU 從「偵測」變成「不可表達」。
    func testSamePathReincarnationGetsADifferentIndexFile() throws {
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        let before = store.indexURL
        // **刪除前先抓值**：`incarnation` 與 `indexURL` 都是 computed（每次讀磁碟），
        // 刪掉重建之後 `store.incarnation` 讀到的是**新**檔案——比對自己等於自己。
        // 第一版就是那樣寫的，測試因此紅在一個不存在的問題上。
        let originalID = store.incarnation
        _ = try LibraryIndex(store: store).rebuild()
        XCTAssertNotNil(originalID, "ensureLayout 要補寫化身 id")

        // 「重生」：整個 root 刪掉重建（新化身、同路徑）
        try FileManager.default.removeItem(at: root)
        let reborn = makeStore(root: root, key: "main")
        try reborn.ensureLayout()

        XCTAssertNotNil(reborn.incarnation)
        XCTAssertNotEqual(reborn.incarnation, originalID, "重生要拿到新化身")
        XCTAssertNotEqual(reborn.indexURL, before,
                          "index 檔名綁化身——重生後根本是另一個檔案，不存在「舊 index 被誤信」")
        XCTAssertFalse(FileManager.default.fileExists(atPath: reborn.indexURL.path),
                       "新化身的 index 還沒建，`ensureCurrent` 必須重建")
    }

    /// 縱深防禦那一層：**同一個檔案**被拿去比對時，`store_id` 不符要判 stale。
    ///
    /// 這一層擋的是人工改名（把舊 index 改成新化身的檔名）。主要保護在檔名，
    /// 所以這條要**刻意繞過檔名**才驗得到。
    func testStoreIdMismatchIsStaleEvenAtTheSamePath() throws {
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        _ = try LibraryIndex(store: store).rebuild()
        let built = store.indexURL
        XCTAssertTrue(LibraryIndex.isCurrent(indexPath: built, expectedRoot: root,
                                             expectedIncarnation: store.incarnation))
        XCTAssertFalse(LibraryIndex.isCurrent(indexPath: built, expectedRoot: root,
                                              expectedIncarnation: UUID().uuidString),
                       "store_id 不符＝別的化身建的，必須判 stale")
    }

    /// **化身檔存在但讀不到 → fail-loud，絕不覆寫**（#130 verify C）。
    ///
    /// `read()` 先前不區分「不存在」與「存在但讀失敗」，而 `writeIfAbsent` 只問它
    /// 是否回 nil——於是 store 的**身分**被靜默覆寫。席位實測三種情形（截斷、
    /// `chmod 000`、連續跑每次換新 id），其中 000 那條最嚴重：atomic replace 保留
    /// 000 權限，新 id 也讀不到 → `indexURL` 退回無 tag 的舊檔名 → 整個機制靜默
    /// 失效，而 `orphanedIndexFiles()` 在 tag 為 nil 時回 `[]`，連孤兒都不報。
    ///
    /// doc 自己寫著「既有的一律不覆寫——覆寫等於把一個 store 變成另一個化身，
    /// 而那正是這個機制要偵測的事件」。實作在讀失敗時做的正是那件事。
    /// **Dropbox 是文件點名要支援的情境**，半截同步會踩到。
    func testUnreadableIncarnationIsNotSilentlyOverwritten() throws {
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        let original = try XCTUnwrap(store.incarnation)
        let f = StoreIncarnation.url(in: root)

        // 內容壞掉（截斷／半截同步）
        try "not-a-uuid".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try StoreIncarnation.writeIfAbsent(root: root),
                             "內容不是 UUID 時不得覆寫——那會換掉 store 的身分")
        XCTAssertEqual(try String(contentsOf: f, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines), "not-a-uuid",
                       "拒絕就不得動檔案")

        // 讀不到（權限／online-only placeholder）
        try original.write(to: f, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: f.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: f.path) }
        if (try? String(contentsOf: f, encoding: .utf8)) == nil {
            XCTAssertThrowsError(try StoreIncarnation.writeIfAbsent(root: root),
                                 "讀不到不等於缺席——covering 掉一個暫時讀不到的身分"
                                 + "是不可逆的")
        }
    }

    /// **孤兒偵測不得跨 key**（#130 verify A）。
    ///
    /// `StoreKey.pattern` 允許連字號，所以 `main-backup` 是合法的 registry key。
    /// 先前只要 `hasPrefix("main-")`，於是 `main` 的 doctor 會把
    /// `main-backup-33f46bce.sqlite`——**另一個已註冊 store 正在用的 index**——
    /// 報成自己的孤兒，訊息還說「舊 index 不再使用」。照著做就刪掉別人的 live index。
    ///
    /// （`mainx-….sqlite` 不會誤報：連字號在 prefix 裡。誤報的是含連字號的 key
    /// ——那是席位糾正我的，我原本擔心錯了方向。）
    func testOrphanDetectionDoesNotCrossRegistryKeys() throws {
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        let tag = String(try XCTUnwrap(store.incarnation).prefix(8)).lowercased()
        let dir = store.indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["main-\(tag).sqlite",              // 本 store 當下的
                     "main-deadbeef.sqlite",             // 本 store 的舊化身 → 是孤兒
                     "main.sqlite",                      // 升級前的 → 是孤兒
                     "main-backup-33f46bce.sqlite",      // **另一個 registry key 的 live index**
                     "mainx-345632ab.sqlite",            // 另一個 key（無連字號）
                     "main-nothex1.sqlite"] {            // tag 不是 hex → 不是本 store 的
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path,
                                           contents: Data())
        }
        XCTAssertEqual(store.orphanedIndexFiles(), ["main-deadbeef.sqlite", "main.sqlite"],
                       "只有本 key 的舊化身算孤兒——把別的 store 的 live index 報成"
                       + "「可刪」是會造成資料遺失的誤報")
    }

    /// **缺席退回純路徑比對，不判 stale。**
    ///
    /// 既有 index 與既有 store 都沒有這個欄位／檔案。讓缺席等於「不符」會把全部
    /// 既有 index 判 stale——而且每次呼叫都重來（新 index 也只在 store 有 id 時
    /// 才寫 `store_id`）。`nil` 不會誤信：真正的保護在檔名。
    func testAbsentIncarnationFallsBackToPathComparison() throws {
        let store = makeStore(root: root, key: "main")
        try store.ensureLayout()
        _ = try LibraryIndex(store: store).rebuild()
        XCTAssertTrue(LibraryIndex.isCurrent(indexPath: store.indexURL, expectedRoot: root,
                                             expectedIncarnation: nil),
                      "呼叫端不知道化身時退回路徑比對——那是今天的行為，不是退步")
    }
}
