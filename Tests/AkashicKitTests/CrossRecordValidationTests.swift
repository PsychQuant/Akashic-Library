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
    func testDuplicateUUIDIsError() throws {
        let shared = UUID()
        try store.writeEntry(entry("a2020a", id: shared))
        try store.writeEntry(entry("b2020b", id: shared))
        let issues = try store.load().crossRecordIssues()
        XCTAssertEqual(issues.filter { $0.severity == .error }.count, 1)
        XCTAssertTrue(issues[0].message.contains(shared.uuidString), issues[0].message)
        XCTAssertTrue(issues[0].message.contains("a2020a") && issues[0].message.contains("b2020b"),
                      "訊息要說出是哪兩筆，否則使用者無從下手：\(issues[0].message)")
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
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].severity, .warning)
        XCTAssertTrue(issues[0].message.contains("ghost-person"), issues[0].message)
    }

    func testResolvedAuthorKeyProducesNoIssue() throws {
        try store.writePerson(Person(key: "real-person", names: ["R"]))
        try store.writeEntry(entry("a2020a", authors: [.key("real-person")]))
        XCTAssertTrue(try store.load().crossRecordIssues().isEmpty)
    }

    func testDanglingLibraryKeyIsWarning() throws {
        try store.writeEntry(entry("a2020a", libraries: ["nolib"]))
        let issues = try store.load().crossRecordIssues()
        XCTAssertEqual(issues.filter { $0.severity == .warning }.count, 1)
        XCTAssertTrue(issues[0].message.contains("nolib"))
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
