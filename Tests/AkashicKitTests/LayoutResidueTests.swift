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

    // MARK: - #120 verify 兩席（adversarial + Codex）要求的守衛

    /// FP-2：判準必須有「這裡真的是 store」前提——不含任何 store 痕跡的目錄
    /// （只有個 notes/ 之類）不得得到任何刪除建議。
    ///
    /// **已知限制**：帶**空 `entries/`** 的目錄與 legacy store 的 fresh clone 本質上
    /// 不可區分（`isLibraryRoot` 對空 entries/ 刻意回 true，#35）——那種目錄仍會
    /// 得到建議。根治是「開啟任意目錄」本身要先被擋（#108 的守衛、#105 的 registry
    /// 反查），不是殘留判準能單獨解的。
    func testArbitraryDirectoryYieldsNoAdvice() throws {
        try mkdir("notes")
        // 沒有 store.yaml、也沒有 entries/entities → 不是 library root → 零建議
        XCTAssertEqual(try LibraryStore(root: root).layoutResidue(), [])
    }

    /// FP-1：symlink 目錄絕不報——`rm -rf notes/`（帶尾斜線）刪的是**目標**目錄。
    func testSymlinkedDirIsNeverResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-symtarget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("notes"),
            withDestinationURL: outside)
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix("notes/") })
    }

    /// FP-3 + Codex P1：**嚴格空**——只含 .DS_Store 的目錄不算空（它可以是目錄、
    /// 可以裝資料；「永不報含資料的目錄」是字面保證，Finder 殘渣造成的漏報可接受）。
    func testDSStoreOnlyDirIsNotResidue() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try touch("notes/.DS_Store")
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix("notes/") })
    }

    /// Codex P1：`.index.sqlite.` 寬前綴會把人工備份誤稱衍生物——只認 rebuild 的
    /// 精確文法（`.index.sqlite.rebuild-<UUID>`）。
    func testManualBackupInAkashicIsNotDerived() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reshome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try touch(".akashic/index.sqlite")
        try touch(".akashic/.index.sqlite.manual-backup")   // 使用者的救援資料
        XCTAssertFalse(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
        // rebuild 文法的 temp 檔則是衍生物
        try FileManager.default.removeItem(
            at: root.appendingPathComponent(".akashic/.index.sqlite.manual-backup"))
        try touch(".akashic/.index.sqlite.rebuild-\(UUID().uuidString)")
        XCTAssertTrue(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
    }

    /// FN-2：SQLite 側車（-wal/-shm/-journal）是衍生物——崩過的孤兒正好帶著它們。
    func testSidecarOnlyAkashicIsResidue() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reshome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = LibraryStore(root: root, key: "main",
                                 environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try touch(".akashic/index.sqlite")
        try touch(".akashic/index.sqlite-wal")
        try touch(".akashic/index.sqlite-shm")
        XCTAssertTrue(try store.layoutResidue().contains { $0.hasPrefix(".akashic/") })
    }

    /// (c)：ensureLayout 與 layoutResidue 的 format 分支**互補**是不變式——
    /// 四格（keyed/keyless × legacy/current）ensureLayout 後必須零殘留。
    /// 回歸一行（例如 ensureLayout 又變無條件）這裡就紅。
    func testEnsureLayoutNeverManufacturesItsOwnResidue() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-reshome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for (key, legacy) in [(String?.none, false), (String?.none, true),
                              (String?.some("main"), false), (String?.some("main"), true)] {
            let r = FileManager.default.temporaryDirectory
                .appendingPathComponent("akashic-cell-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: r) }
            if legacy {
                try FileManager.default.createDirectory(
                    at: r.appendingPathComponent("entries"), withIntermediateDirectories: true)
                try "citekey: x2000y\n".write(
                    to: r.appendingPathComponent("entries/x.yaml"),
                    atomically: true, encoding: .utf8)
            }
            let store = LibraryStore(root: r, key: key,
                                     environment: ["AKASHIC_HOME": home.path])
            try store.ensureLayout()
            XCTAssertEqual(try store.layoutResidue(), [],
                           "cell(key: \(key ?? "nil"), legacy: \(legacy)) 不得自產殘留")
        }
    }

    /// (d)：format 1 的空 people/ 與 libraries/ **不報**——釘住行為邊界。
    func testLegacyEmptyPeopleAndLibrariesAreNotResidue() throws {
        try mkdir("entries"); try touch("entries/a.yaml")
        let store = LibraryStore(root: root)
        try store.ensureLayout()   // format 1；ensureLayout 建了 people/ 與 libraries/
        let r = try store.layoutResidue()
        XCTAssertFalse(r.contains { $0.hasPrefix("people/") }, "\(r)")
        XCTAssertFalse(r.contains { $0.hasPrefix("libraries/") }, "\(r)")
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
