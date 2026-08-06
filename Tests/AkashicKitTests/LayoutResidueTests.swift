import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 佈局殘留偵測（#107）：#101/#102/#103/#106 讓 `ensureLayout` 只建該建的目錄，
/// 但只對**未來**的呼叫生效——既有 store 的殘留（migrate 留下的空 legacy 目錄、
/// keyless 時期的孤兒 index、#103 撤下後的空 notes/）無人聞問。
///
/// 形狀沿 #79：**報告、不自動刪**。判準自我描述且偏保守：「依當前 format 與 key
/// 不該存在，且是空目錄或純衍生物」——**永不報含資料的目錄**。
final class LayoutResidueTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-residue-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func mkdir(_ sub: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    private func touch(_ rel: String) throws {
        let u = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "x".write(to: u, atomically: true, encoding: .utf8)
    }

    /// 乾淨的現行 store：零殘留。
    func testCleanStoreHasNoResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        XCTAssertEqual(try store.layoutResidue(), [])
    }

    /// migrate 的遺留：format ≥ 2 + 空的 legacy 目錄。
    func testEmptyLegacyDirsOnCurrentFormatAreResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try mkdir("entries"); try mkdir("people")
        let r = try store.layoutResidue()
        XCTAssertTrue(r.contains { $0.hasPrefix("entries/") }, "\(r)")
        XCTAssertTrue(r.contains { $0.hasPrefix("people/") }, "\(r)")
    }

    /// **含資料的目錄永不報**——就地遷移到一半（legacy 檔還在）不是殘留，是資料。
    func testNonEmptyLegacyDirIsNeverResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try touch("entries/still-here.yaml")
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix("entries/") })
    }

    /// #102 的鏡像殘留：format 1 + 空的 entities/。
    func testEmptyEntitiesOnLegacyFormatIsResidue() throws {
        try mkdir("entries"); try touch("entries/a.yaml")
        let store = LibraryStore(root: root)
        try store.ensureLayout()   // writeIfAbsent 標 1
        try mkdir("entities")
        XCTAssertTrue(try store.layoutResidue().contains { $0.hasPrefix("entities/") })
    }

    /// #103 撤下的 notes/：存在且空 → 殘留（任何 format）。
    func testEmptyNotesIsResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try mkdir("notes")
        XCTAssertTrue(try store.layoutResidue().contains { $0.hasPrefix("notes/") })
    }

    /// keyless 時期的孤兒 index：帶 key 開啟 + in-store `.akashic/` 只含衍生物。
    func testInStoreIndexOnKeyedOpenIsResidue() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reshome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try touch(".akashic/index.sqlite")
        XCTAssertTrue(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
    }

    /// `.akashic/` 內有**非衍生物**的未知檔案 → 保守不報。
    func testAkashicDirWithUnknownContentIsNotResidue() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reshome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try touch(".akashic/somebody-put-this-here.txt")
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
    }

    /// keyless 開啟時 `.akashic/` 是正當的回落位置——不是殘留。
    func testInStoreIndexOnKeylessOpenIsNotResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try touch(".akashic/index.sqlite")
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
    }

    /// **`sources/` 絕不列入**（#101 的「險些誤判」教訓直接寫進判準）：
    /// 它是 #66 的被指涉內容、只留 local 的唯一一份——0 引用 ≠ 不要。
    func testSourcesIsNeverResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try mkdir("sources")                       // 空的也不報
        try touch("sources/ab/cdef0123")           // 有內容更不報
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix("sources/") })
    }
}
