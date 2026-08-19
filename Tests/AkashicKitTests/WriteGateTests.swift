import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #108：寫入閘——root 打錯不再被靜默實體化成幽靈 store。
///
/// #101 讓 atomicWrite 自建父目錄後，「root 打錯會大聲失敗」只剩 CLI 的
/// openStore() 一道防線：`LibraryStore(root: 打錯的路徑).writeEntry(...)` 會把
/// 整棵樹安靜建出、且**無 store.yaml**——之後 ensureLayout 看到 entries/*.yaml
/// 把錯字路徑標成 format 1。MCP/App/外部呼叫端全裸。
final class WriteGateTests: XCTestCase {
    private var ghost: URL!

    override func setUpWithError() throws {
        ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ghost108-\(UUID().uuidString)")
        // 刻意**不**建立——這就是打錯字的 root
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ghost)
    }

    private func entry(_ citekey: String) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
              title: "T", authors: [.literal("X")], date: "2020")
    }

    func testWriteEntryToNonexistentRootIsRefused() throws {
        let store = LibraryStore(root: ghost, key: nil, environment: [:])
        XCTAssertThrowsError(try store.writeEntry(entry("aaa2020bbb"))) { error in
            let m = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(m.contains("doctor"), "訊息要指路（先跑 doctor 建佈局）：\(m)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ghost.path),
                       "拒絕時不得留下任何目錄——半棵樹就是下一個幽靈")
    }

    func testWritePersonAndOrganizationAndLibraryAlsoGated() throws {
        let store = LibraryStore(root: ghost, key: nil, environment: [:])
        XCTAssertThrowsError(try store.writePerson(Person(key: "p-x", names: ["X"])))
        XCTAssertThrowsError(try store.writeOrganization(
            Organization(key: "org-x", names: Timeline([TemporalValue(value: "X")]))))
        XCTAssertThrowsError(try store.writeLibrary(Library(key: "lib-x", name: "X")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ghost.path))
    }

    /// pre-#24 legacy：無 marker 但 entries/ 有內容——真 store，放行。
    func testLegacyStoreWithoutMarkerStillWritable() throws {
        try FileManager.default.createDirectory(
            at: ghost.appendingPathComponent("entries"), withIntermediateDirectories: true)
        let store = LibraryStore(root: ghost, key: nil, environment: [:])
        try store.ensureLayout()   // 會標 format 1（legacy 有內容判定在 writeIfAbsent）
        try FileManager.default.removeItem(at: StoreVersion.url(in: ghost))   // 模擬 pre-#24
        try "id: \(UUID().uuidString)\ncitekey: old2000x\ntype: periodical-article\ntitle: T\n".write(
            to: ghost.appendingPathComponent("entries/old2000x.yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try store.writeEntry(entry("new2021yyy")),
                         "無 marker 但有真內容＝pre-#24 legacy store，寫入照常")
    }

    /// 經過 ensureLayout 的正常路徑零影響（marker 在）。
    func testNormalPathUnaffected() throws {
        let store = LibraryStore(root: ghost, key: nil, environment: [:])
        try store.ensureLayout()
        XCTAssertNoThrow(try store.writeEntry(entry("ok2022zzz")))
    }

    /// 「新 store 的 format 取決於先呼叫哪個寫入 API」的不一致隨閘消失：
    /// 沒經過 ensureLayout 的裸寫一律被拒，不再有「先 writeOrganization 變
    /// entities、先 writeEntry 變 legacy」的分岔。
    func testBareWriteOrderNoLongerDeterminesFormat() throws {
        let store = LibraryStore(root: ghost, key: nil, environment: [:])
        XCTAssertThrowsError(try store.writeOrganization(
            Organization(key: "org-y", names: Timeline([TemporalValue(value: "Y")]))))
        XCTAssertThrowsError(try store.writeEntry(entry("bare2020www")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ghost.path))
    }
}
