import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `ensureLayout()` 建立的目錄集合必須**帶語意**（#101）。
///
/// 在 #101 之前它是一個無條件迴圈，同時做兩件事：宣告佈局（依 format 而定）與保證
/// 寫入路徑的父目錄存在（無條件）。後者之所以綁進來，是因為 `atomicWrite` 不建父目錄。
/// 結果是 format 5 的 store 長出 format 1 的 `entries/`／`people/`，已註冊的 store 長出
/// 「未註冊 store 專用」的 `.akashic/`——**「目錄存在」不再代表任何事**。
///
/// 這組測試把兩個職責分別釘住：
/// - 佈局宣告 → `ensureLayout` 依 format 與 registry key 決定建哪些
/// - 父目錄保證 → 寫入路徑自己負責（`atomicWrite` 的 choke point）
final class EnsureLayoutTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-layout-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func exists(_ sub: String) -> Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(
            atPath: root.appendingPathComponent(sub).path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }

    private func makeEntry(_ citekey: String = "cheng2025identifiability") -> Entry {
        Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
              title: "Identifiability of polychoric models",
              authors: [.literal("Che Cheng")], date: "2025")
    }

    // MARK: - 佈局宣告

    /// 全新的 store 是**現行格式**，不該拿到 legacy 佈局的目錄。
    func testFreshStoreHasNoLegacyDirectories() throws {
        try LibraryStore(root: root).ensureLayout()

        XCTAssertEqual(try StoreVersion.read(root: root), StoreVersion.supported,
                       "前置條件：全新的空 store 由 writeIfAbsent 標成當前 format")
        XCTAssertFalse(exists("entries"),
                       "format \(StoreVersion.supported) 的 store 不該有 legacy 的 entries/")
        XCTAssertFalse(exists("people"),
                       "format \(StoreVersion.supported) 的 store 不該有 legacy 的 people/")

        for sub in ["entities", "libraries"] {
            XCTAssertTrue(exists(sub), "\(sub)/ 是現行格式在用的目錄，必須建立")
        }
        XCTAssertFalse(exists("notes"),
                       "notes/ 已撤下（#103）——宣告以來沒有任何寫入端，不再屬於佈局")
    }

    /// 已註冊的 store 的 index 住 store **之外**（`~/.akashic/index/<key>.sqlite`，#37），
    /// 所以 in-store 的回落位置 `.akashic/` 對它毫無用處。
    func testRegisteredStoreHasNoInStoreIndexDirectory() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": fakeHome.path])
        try store.ensureLayout()

        XCTAssertFalse(store.indexURL.path.hasPrefix(root.path),
                       "前置條件：已註冊 store 的 index 本來就不在 store 內")
        XCTAssertFalse(exists(".akashic"),
                       ".akashic/ 是未註冊 store 的 index 回落位置；已註冊的 store 不該建它")
    }

    /// 既有的 legacy store（format 1）照樣拿到它在用的目錄——本 change 不動它們。
    func testLegacyStoreStillGetsLegacyDirectories() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try "citekey: legacy2000x\n".write(
            to: root.appendingPathComponent("entries").appendingPathComponent("legacy.yaml"),
            atomically: true, encoding: .utf8)

        try LibraryStore(root: root).ensureLayout()

        XCTAssertEqual(try StoreVersion.read(root: root), 1,
                       "前置條件：entries/ 有內容 → writeIfAbsent 標 format 1（#35 的安全點）")
        XCTAssertTrue(exists("entries"), "legacy 佈局在用 entries/")
        XCTAssertTrue(exists("people"), "legacy 佈局在用 people/")
        XCTAssertFalse(exists("entities"),
                       "#101 的鏡像（#102）：format 1 的 store 不該拿到永遠空著的 entities/——" +
                       "遷移時 StoreMigration 自己建，寫入時 atomicWrite 自建父目錄，都不靠這裡")
    }

    /// 未註冊的 store（`--library <path>` 直指）仍需要 in-store 的 index 回落位置。
    func testUnregisteredStoreStillGetsAkashicDir() throws {
        let store = LibraryStore(root: root)
        XCTAssertNil(store.key, "前置條件：未註冊")
        try store.ensureLayout()

        XCTAssertTrue(exists(".akashic"), "未註冊 store 的 index 回落 in-store，目錄必須在")
        // #130：檔名帶化身前綴，斷言目錄
        XCTAssertEqual(store.indexURL.deletingLastPathComponent().path,
                       root.appendingPathComponent(".akashic").path)
        XCTAssertTrue(store.indexURL.lastPathComponent.hasPrefix("index"))
    }

    // MARK: - marker 壞掉時建佈局要 fail-loud（#106）

    /// `usesEntitiesLayout` 的兜底是給**寫入路由**的（#35：猜的方向與資料一致）。
    /// 建佈局是結構性動作，猜錯的代價是雙佈局爛攤子——`ensureLayout` 必須走 strict：
    /// marker 讀不懂就拒絕（malformed 訊息目前只描述、不含修復指引——另案）。
    func testEnsureLayoutRefusesMalformedMarker() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "format: banana\n".write(to: StoreVersion.url(in: root),
                                     atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try LibraryStore(root: root).ensureLayout()) { error in
            guard case StoreVersionError.malformed = error else {
                return XCTFail("預期 malformed，實得 \(error)")
            }
        }
        XCTAssertFalse(exists("entries"),
                       "拒絕之後不得留下依錯誤猜測建出的目錄（現在：安靜判成 legacy 並建出它們）")
    }

    /// 比本 binary 新的 store：refuse-if-newer 的既有語意（#24）必須涵蓋建佈局的入口——
    /// 否則 `file add` 能成功註冊一個 too-new 的 store、doctor 對它安靜蓋目錄。
    func testEnsureLayoutRefusesNewerStore() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported + 5)

        XCTAssertThrowsError(try LibraryStore(root: root).ensureLayout()) { error in
            guard case StoreVersionError.tooNew = error else {
                return XCTFail("預期 tooNew，實得 \(error)")
            }
        }
        XCTAssertFalse(exists("entries"))
        XCTAssertFalse(exists("entities"))
    }

    // MARK: - 父目錄保證

    /// 寫入路徑**不得依賴** `ensureLayout` 事先建好目錄。
    ///
    /// 這條是把 legacy 目錄條件化之後的必要條件：測試樹裡有一批 fixture 先跑
    /// `ensureLayout()`（此時是當前 format）再把 format 標回 1，之後才寫入——若寫入端
    /// 不能自建目錄，那些 fixture 會撞上不存在的 `entries/`。
    ///
    /// 它同時是一個獨立的既存缺陷：`writeLibrary` / `StoreMigration` / `DivergenceResolve`
    /// 各自寫過一次 `createDirectory` 來繞過同一件事，而 entry / person 的寫入沒有。
    func testLegacyWriteCreatesItsOwnDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: 1)
        let store = LibraryStore(root: root)

        XCTAssertFalse(exists("entries"), "前置條件：entries/ 尚未建立")
        XCTAssertNoThrow(try store.writeEntry(makeEntry()),
                         "legacy 寫入路徑必須自己確保父目錄存在")
        XCTAssertTrue(exists("entries"))

        XCTAssertFalse(exists("people"), "前置條件：people/ 尚未建立")
        XCTAssertNoThrow(try store.writePerson(Person(key: "cheng-che")),
                         "person 的 legacy 寫入路徑同理（空 names——具名寫入受 #227 v10 閘）")
        XCTAssertTrue(exists("people"))
    }

    /// **`layoutResidue` 的檔名文法要跟著 #130 走**（verify B）。
    ///
    /// in-store index 現在是 `index-<8 碼>.sqlite`、rebuild temp 是
    /// `.index-<8 碼>.sqlite.rebuild-<UUID>`。先前白名單只認字面的 `index.sqlite`，
    /// 於是**凡是在新 binary 下先 keyless 用過、之後才註冊的 store，`.akashic/` 的
    /// 清理提示從此不出現**（origin/main 上會出現），崩掉的 rebuild 殘骸也沉默。
    func testLayoutResidueRecognisesIncarnationTaggedIndexNames() throws {
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": root.appendingPathComponent("h").path])
        try store.ensureLayout()
        let ak = root.appendingPathComponent(".akashic")
        try FileManager.default.createDirectory(at: ak, withIntermediateDirectories: true)
        for n in ["index-bd0b7f59.sqlite", "index-bd0b7f59.sqlite-wal",
                  ".index-bd0b7f59.sqlite.rebuild-\(UUID().uuidString)"] {
            FileManager.default.createFile(atPath: ak.appendingPathComponent(n).path, contents: Data())
        }
        XCTAssertTrue(try store.layoutResidue().contains { $0.contains(".akashic") },
                      "帶化身前綴的 in-store index 仍是可刪的衍生物——認不得它，"
                      + "清理提示就從此消失而沒有訊號")
    }

}
