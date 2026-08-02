import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex

/// #7b 跨記錄驗證 + #7a atomic index rebuild。
final class CrossRecordValidationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-xrec-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// legacy 佈局的 store（`entries/<citekey>.yaml` + `people/<key>.yaml`）。
    ///
    /// `setUpWithError` 的 `ensureLayout()` 會把新建的空 store 標成**當前** format，
    /// 因而走 entities 佈局。測 legacy 行為的案例必須明確把 format 標回 1——沿用
    /// `EntitiesLayoutTests.legacyStore()` 已建立的形式（#56）。
    private func legacyStore() throws -> LibraryStore {
        try StoreVersion.write(root: root, format: 1)
        return LibraryStore(root: root)
    }

    private func entry(_ key: String, id: UUID = UUID(), authors: [Author] = [.literal("X")],
                       libraries: [String] = []) -> Entry {
        var e = Entry(id: id, citekey: key, type: "article", title: "T",
                      authors: authors, date: "2020")
        e.akashic.libraries = libraries
        return e
    }

    // MARK: - 唯一性（單筆 validate 結構上看不到）

    /// 重複 UUID 的實際後果：index 的 `PRIMARY KEY` 靜默丟掉其中一筆——
    /// 查詢少一筆但**不報錯**。所以這必須是 error 而非 warning。
    ///
    /// **legacy 佈局限定**（#56）：entities 佈局下**檔名就是 UUID**，兩筆共用 UUID 會寫進
    /// 同一個檔、後者覆蓋前者，於是 load 只讀到一筆——「兩筆共用 UUID」在那個佈局裡
    /// 結構上不可能存在。這條檢查因此只對 legacy 佈局有意義。entities 佈局的等價
    /// 風險路徑（檔名與內容 id 不符）由 `testEntitiesLayoutRejectsIdFilenameMismatch` 覆蓋。
    func testDuplicateUUIDIsError() throws {
        let store = try legacyStore()
        let shared = UUID()
        try store.writeEntry(entry("a2020a", id: shared))
        try store.writeEntry(entry("b2020b", id: shared))
        let issues = try store.load().crossRecordIssues()
        let errors = issues.filter { $0.severity == .error }
        XCTAssertEqual(errors.count, 1, "\(issues)")
        // XCTUnwrap 而非 issues[0]：空陣列取值是 fatal error 而非測試失敗，
        // 會中止整個 xctest 程序並遮蔽其後所有 suite（#56 的實際後果）。
        let first = try XCTUnwrap(errors.first)
        XCTAssertTrue(first.message.contains(shared.uuidString), first.message)
        XCTAssertTrue(first.message.contains("a2020a") && first.message.contains("b2020b"),
                      "訊息要說出是哪兩筆，否則使用者無從下手：\(first.message)")
    }

    /// entities 佈局的等價風險：檔名 UUID 與記錄內的 id 不符。
    ///
    /// 這是 `testDuplicateUUIDIsError` 在新佈局下的對應面——重複 UUID 不可能發生，
    /// 但「有人手動改了檔名或 id」會讓引用錯位，必須被擋下而不是靜默載入。
    func testEntitiesLayoutRejectsIdFilenameMismatch() throws {
        let recorded = UUID(), filename = UUID()
        var e = entry("a2020a", id: recorded)
        e.akashic.libraries = []
        let yaml = try EntryYAML.encode(e)
        try yaml.write(to: store.entityURL(id: filename), atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 0, "檔名與 id 不符的記錄不得被載入")
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertTrue(q.reason.contains(recorded.uuidString), q.reason)
    }

    /// **重複 key 在 macOS 上結構性不可能**——檔名就是 key，而 APFS 預設 case-insensitive，
    /// 所以 `dup-one.YAML` 會直接覆蓋 `dup-one.yaml`。這條檢查是給 **case-sensitive 卷冊**
    /// 與 Linux 的縱深防禦（那裡兩個檔的 stem 都是 `dup-one`、都通過檔名↔key 檢查）。
    ///
    /// 因此在**邏輯層**測，不透過檔案系統——否則這個測試在 macOS 上只是驗證了
    /// 「檔案系統會覆蓋檔案」，跟要驗的東西無關。
    func testDuplicateKeysAreErrorsAtLogicLevel() {
        let load = LibraryLoad(
            entries: [],
            people: [Person(key: "dup-one", names: ["A"]),
                     Person(key: "dup-one", names: ["B"])],
            libraries: [Library(key: "dup-lib", name: "L1"),
                        Library(key: "dup-lib", name: "L2")])
        let issues = load.crossRecordIssues()
        XCTAssertEqual(issues.filter { $0.severity == .error }.count, 2, "\(issues)")
        XCTAssertTrue(issues.contains { $0.message.contains("dup-one") })
        XCTAssertTrue(issues.contains { $0.message.contains("dup-lib") })
    }

    func testDuplicateCitekeyIsErrorAtLogicLevel() {
        let load = LibraryLoad(entries: [entry("same2020a"), entry("same2020a")])
        XCTAssertTrue(load.crossRecordIssues().contains {
            $0.severity == .error && $0.message.contains("same2020a")
        })
    }

    // MARK: - 參照存在性（warning，不擋工作流）

    /// 懸空作者 key **不是 error**：resolve-people 尚未 apply 時本來就會有，
    /// 擋下反而卡住工作流。但必須可見，否則 person 頁面永遠空的而沒人知道為什麼。
    func testDanglingAuthorKeyIsWarningNotError() throws {
        try store.writeEntry(entry("a2020a", authors: [.key("ghost-person")]))
        let issues = try store.load().crossRecordIssues()
        XCTAssertEqual(issues.count, 1, "\(issues)")
        let first = try XCTUnwrap(issues.first)
        XCTAssertEqual(first.severity, .warning)
        XCTAssertTrue(first.message.contains("ghost-person"), first.message)
    }

    func testResolvedAuthorKeyProducesNoIssue() throws {
        try store.writePerson(Person(key: "real-person", names: ["R"]))
        try store.writeEntry(entry("a2020a", authors: [.key("real-person")]))
        XCTAssertTrue(try store.load().crossRecordIssues().isEmpty)
    }

    func testDanglingLibraryKeyIsWarning() throws {
        try store.writeEntry(entry("a2020a", libraries: ["nolib"]))
        let issues = try store.load().crossRecordIssues()
        let warnings = issues.filter { $0.severity == .warning }
        XCTAssertEqual(warnings.count, 1, "\(issues)")
        XCTAssertTrue(try XCTUnwrap(warnings.first).message.contains("nolib"))
    }

    func testCleanStoreHasNoCrossRecordIssues() throws {
        try store.writePerson(Person(key: "p-one", names: ["P"]))
        try store.writeLibrary(Library(key: "lib", name: "L"))
        try store.writeEntry(entry("a2020a", authors: [.key("p-one")], libraries: ["lib"]))
        try store.writeEntry(entry("b2021b"))
        XCTAssertTrue(try store.load().crossRecordIssues().isEmpty)
    }

    // MARK: - #7a：atomic index rebuild

    /// rebuild 之後不得留下 temp 檔——半套檔留在 index 目錄會累積，
    /// 而且看起來像真的 index。
    func testRebuildLeavesNoTempArtifacts() throws {
        try store.writeEntry(entry("a2020a"))
        _ = try LibraryIndex(store: store).rebuild()
        let dir = store.indexURL.deletingLastPathComponent()
        let leftovers = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
            .filter { $0.contains("rebuild-") }
        XCTAssertTrue(leftovers.isEmpty, "殘留 temp：\(leftovers)")
    }

    /// 重建到既有 index 之上必須成功（replaceItemAt 路徑），且內容是新的。
    func testRebuildOverExistingIndexReplacesAtomically() throws {
        try store.writeEntry(entry("a2020a"))
        let first = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(first.entries, 1)
        try store.writeEntry(entry("b2021b"))
        let second = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(second.entries, 2, "換位後必須是新 index")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
    }
}
