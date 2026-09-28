import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicSQLite

/// #609：附加來源被標 orphan 之後，doctor 與 index 都看得到。
///
/// 兩個形狀：
/// - 主連結仍在、某個附加來源已刪除 → `orphanedAdditionalSourceCitekeys`（新）
/// - 沒有主來源、附加來源全部已刪除 → 整筆 orphan，進 `orphanedCitekeys`（先前哪裡都看不見，#609 R2 補充）
final class ZoteroLinkStateTests: XCTestCase {
    private var home: URL!
    private var root: URL!
    private var store: LibraryStore!
    private let gone = Date(timeIntervalSince1970: 1_753_000_000)

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-linkhome-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
        precondition(store.indexURL.path.hasPrefix(home.path + "/") || store.indexURL.path.hasPrefix(root.path + "/"),
                     "indexURL 指向沙箱外：\(store.indexURL.path)")
        try store.ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: home)
    }

    private func source(_ key: String, lib: Int, orphaned: Bool) -> Provenance {
        Provenance(zoteroKey: key, zoteroVersion: 1, libraryID: lib, orphanedAt: orphaned ? gone : nil)
    }

    private func entry(_ citekey: String, primary: Provenance?, additional: [Provenance]) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: citekey)
        e.provenance = primary
        e.additionalProvenance = additional
        return e
    }

    /// 封閉三值的每一格。
    func testLinkStateCoversEveryShape() {
        let live = source("K1", lib: 1, orphaned: false), dead = source("K1", lib: 1, orphaned: true)
        let liveB = source("K2", lib: 5, orphaned: false), deadB = source("K2", lib: 5, orphaned: true)
        let deadC = source("K3", lib: 7, orphaned: true)
        let cases: [(String, Provenance?, [Provenance], ZoteroLinkState)] = [
            ("沒有任何來源", nil, [], .intact),
            ("主來源活著", live, [], .intact),
            ("主來源活著、附加來源活著", live, [liveB], .intact),
            ("主來源已刪除", dead, [], .orphaned),
            ("主來源已刪除、附加來源活著", dead, [liveB], .orphaned),
            ("主來源活著、附加來源已刪除", live, [deadB], .additionalSourceOrphaned),
            ("只有附加來源、全部已刪除", nil, [deadB, deadC], .orphaned),
            ("只有附加來源、一個已刪除一個活著", nil, [deadB, liveB], .additionalSourceOrphaned),
            ("只有附加來源、全部活著", nil, [liveB], .intact),
        ]
        for (label, p, a, want) in cases {
            XCTAssertEqual(entry("x", primary: p, additional: a).zoteroLinkState, want, label)
        }
    }

    private func seedShapes() throws {
        try store.writeEntry(entry("alive2020", primary: source("A", lib: 1, orphaned: false), additional: []))
        try store.writeEntry(entry("partial2020", primary: source("B", lib: 1, orphaned: false),
                                   additional: [source("B2", lib: 5, orphaned: true)]))
        try store.writeEntry(entry("allgone2020", primary: nil,
                                   additional: [source("C", lib: 5, orphaned: true), source("C2", lib: 7, orphaned: true)]))
        try store.writeEntry(entry("primarygone2020", primary: source("D", lib: 1, orphaned: true),
                                   additional: [source("D2", lib: 5, orphaned: true)]))
    }

    /// doctor 讀的健康事實：兩張清單不相交，整筆 orphan 包含「只有附加來源、全部已刪除」。
    func testHealthListsBothShapesDisjointly() throws {
        try seedShapes()
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.orphanedCitekeys.sorted(), ["allgone2020", "primarygone2020"])
        XCTAssertEqual(health.orphanedAdditionalSourceCitekeys, ["partial2020"])
    }

    /// index 的 orphan 欄與健康事實同一個判準。
    func testIndexOrphanColumnFollowsTheSamePredicate() throws {
        try seedShapes()
        _ = try LibraryIndex(store: store).rebuild()
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: true)
        let rows = try db.query("SELECT citekey FROM entries WHERE orphaned = 1 ORDER BY citekey")
        XCTAssertEqual(rows.compactMap { $0["citekey"] as? String }, ["allgone2020", "primarygone2020"])
    }
}
