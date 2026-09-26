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

    /// **標題預設隨 citekey 而異**（#79）。全部 fixture 共用 `title: "T"` 會讓
    /// 「同標題同年」的重複檢查在每個測試裡誤報——那是 fixture 的假重複，不是
    /// 被測邏輯的問題。需要真的測重複時，明確傳同一個 title。
    private func entry(_ key: String, id: UUID = UUID(), authors: [Author] = [.literal("X")],
                       libraries: [String] = [], title: String? = nil) -> Entry {
        var e = Entry(id: id, citekey: key, type: .periodicalArticle, title: title ?? "T-\(key)",
                      authors: authors, date: "2020")
        e.akashic.libraries = libraries
        return e
    }

    // MARK: - 懸空的團體作者與 venue 邊（#652、#579）

    /// 在此之前只有 person 那一半有懸空檢查：`.organization` 作者與 `venues[].key` 懸空時 validate／doctor／App 都不出聲。
    /// 2026-09-26 live store 實測有 2 筆（#340 批次手寫的 `organization: American Psychological Association`／`OECD`，
    /// payload 是名稱而不是 key）。
    func testDanglingCorporateAuthorAndVenueEdgeAreWarnings() throws {
        var org = Organization(key: "real-org")
        org.names = TimelineOf([TemporalValue(value: "Real Org", range: DateRange())])
        try store.writeOrganization(org)
        var e = entry("a2020a", authors: [.organization("real-org"), .organization("ghost-org")])
        e.venues = [.key("ghost-venue"), .literal("Some Journal")]
        try store.writeEntry(e)
        let issues = try store.load().crossRecordIssues()
        let orgW = try XCTUnwrap(issues.first { $0.message.contains("團體作者 key「ghost-org」") }, "\(issues)")
        XCTAssertEqual(orgW.severity, .warning)
        XCTAssertFalse(orgW.message.contains("不是合法的 StoreKey"), "合法 key 的懸空不附非法說明")
        XCTAssertFalse(issues.contains { $0.message.contains("「real-org」") }, "存在的 org 不報")
        let venueW = try XCTUnwrap(issues.first { $0.message.contains("venue key「ghost-venue」") }, "\(issues)")
        XCTAssertEqual(venueW.severity, .warning)
        XCTAssertFalse(issues.contains { $0.message.contains("Some Journal") }, "literal 邊是誠實狀態，不是懸空")
    }

    /// #579：key 本身不是合法 StoreKey 時，訊息要說它不可能對應任何記錄——「沒有對應的檔」會讓人去找一個不存在的檔。
    func testInvalidStoreKeyEdgeSaysItCanNeverResolve() throws {
        var e = entry("a2020a", authors: [.organization("OECD")])
        e.venues = [.key("Psych Bull")]
        try store.writeEntry(e)
        let issues = try store.load().crossRecordIssues()
        for needle in ["團體作者 key「OECD」", "venue key「Psych Bull」"] {
            let w = try XCTUnwrap(issues.first { $0.message.contains(needle) }, "\(needle)：\(issues)")
            XCTAssertTrue(w.message.contains("不是合法的 StoreKey"), w.message)
        }
    }

    // MARK: - 重複 DOI（#79）

    private func entryWithDOI(_ key: String, doi: String?, title: String = "Shared Title") -> Entry {
        var e = entry(key, title: title)
        if let doi { e.fields["doi"] = doi }
        return e
    }

    /// #79：17 組 work 共用同一個 DOI 而 validate 全綠——重複本身看不見。
    ///
    /// **warning 而非 error**：重複不毀資料，而且「同一篇在個人庫與群組庫各一份」
    /// 是真實且合理的狀態。用 error 會讓 `assertNoCrossRecordErrors` 鎖住整個寫入面。
    func testDuplicateDOIIsWarningNamingAllCitekeys() throws {
        try store.writeEntry(entryWithDOI("a2020a", doi: "10.1000/xyz"))
        try store.writeEntry(entryWithDOI("a2020ba", doi: "10.1000/xyz"))
        let issues = try store.load().crossRecordIssues()
        XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty,
                      "重複 DOI 不得是 error——會鎖住寫入面：\(issues)")
        let w = try XCTUnwrap(issues.first { $0.message.contains("10.1000/xyz") })
        XCTAssertEqual(w.severity, .warning)
        XCTAssertTrue(w.message.contains("a2020a") && w.message.contains("a2020ba"),
                      "訊息必須指名全部 citekey，否則無從下手：\(w.message)")
    }

    /// DOI 依規格大小寫不敏感——`10.1000/XYZ` 與 `10.1000/xyz` 是同一篇。
    /// 大小寫敏感的比較會讓真實的重複逃掉，而那正是這條檢查要抓的東西。
    func testDuplicateDOIComparisonIsCaseInsensitive() throws {
        try store.writeEntry(entryWithDOI("a2020a", doi: "10.1000/XYZ"))
        try store.writeEntry(entryWithDOI("a2020ba", doi: "10.1000/xyz"))
        XCTAssertTrue(try store.load().crossRecordIssues()
            .contains { $0.severity == .warning && $0.message.lowercased().contains("10.1000/xyz") },
            "大小寫不同的同一個 DOI 必須被視為重複")
    }

    /// **沒有 DOI 不是重複。** 缺席與空字串都不得把彼此湊成一組——
    /// 那會讓整個沒 DOI 的子集變成一則巨大的假警告。
    func testAbsentOrEmptyDOIIsNotDuplicate() throws {
        try store.writeEntry(entryWithDOI("a2020a", doi: nil, title: "A"))
        try store.writeEntry(entryWithDOI("b2020b", doi: nil, title: "B"))
        try store.writeEntry(entryWithDOI("c2020c", doi: "   ", title: "C"))
        try store.writeEntry(entryWithDOI("d2020d", doi: "", title: "D"))
        XCTAssertTrue(try store.load().crossRecordIssues().isEmpty,
                      "無 DOI 的記錄不得互相配成重複")
    }

    /// 三筆以上共用同一 DOI 只出一則 warning，且列出全部——
    /// 每對各出一則會讓 n 筆產生 n(n-1)/2 則雜訊。
    func testThreeWayDuplicateReportsOnceWithAllCitekeys() throws {
        for k in ["a2020a", "a2020ba", "a2020ca"] {
            try store.writeEntry(entryWithDOI(k, doi: "10.1000/same"))
        }
        let ws = try store.load().crossRecordIssues().filter { $0.message.contains("10.1000/same") }
        XCTAssertEqual(ws.count, 1, "同一個 DOI 只該出一則：\(ws)")
        let m = try XCTUnwrap(ws.first).message
        for k in ["a2020a", "a2020ba", "a2020ca"] {
            XCTAssertTrue(m.contains(k), "缺 \(k)：\(m)")
        }
    }

    /// DOI 有多種儲存形式——`https://doi.org/10.x/y`、`doi:10.x/y`、裸 `10.x/y`
    /// 都指同一篇。真實資料裡兩種形式並存（`cheng2021likert` 存 URL 形式、
    /// `cheng2021blikert` 存裸 DOI），只 trim+lowercase 會讓這組重複逃掉。
    func testDOINormalizationStripsResolverPrefix() throws {
        try store.writeEntry(entryWithDOI("a2020a", doi: "https://doi.org/10.1000/xyz"))
        try store.writeEntry(entryWithDOI("a2020ba", doi: "10.1000/xyz"))
        try store.writeEntry(entryWithDOI("a2020ca", doi: "doi:10.1000/XYZ"))
        let ws = try store.load().crossRecordIssues().filter { $0.message.contains("10.1000/xyz") }
        XCTAssertEqual(ws.count, 1, "三種寫法必須收斂成同一組：\(ws)")
        let m = try XCTUnwrap(ws.first).message
        for k in ["a2020a", "a2020ba", "a2020ca"] { XCTAssertTrue(m.contains(k), m) }
    }

    /// 同標題同年但 **DOI 不同**——DOI 檢查結構上看不到，而這是真實且大量的：
    /// JSTOR DOI vs 出版商 DOI、arXiv 預印本 vs 正式版、期刊自己換過 DOI 規則。
    func testSameTitleAndYearWithDifferentDOIsIsWarned() throws {
        try store.writeEntry(entryWithDOI("a1996a", doi: "10.1080/01621459.1996.10476987"))
        try store.writeEntry(entryWithDOI("a1996ba", doi: "10.2307/2291736"))
        let issues = try store.load().crossRecordIssues()
        XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty)
        let w = try XCTUnwrap(issues.first { $0.message.contains("標題") })
        XCTAssertEqual(w.severity, .warning)
        XCTAssertTrue(w.message.contains("a1996a") && w.message.contains("a1996ba"), w.message)
    }

    /// **DOI 已經抓到的組不得再用標題重報一次**——同一件事出兩則是雜訊不是訊號。
    func testTitleCheckDoesNotDuplicateDOIFinding() throws {
        try store.writeEntry(entryWithDOI("a2020a", doi: "10.1000/xyz"))
        try store.writeEntry(entryWithDOI("a2020ba", doi: "10.1000/xyz"))
        let issues = try store.load().crossRecordIssues()
        XCTAssertEqual(issues.count, 1, "同一組只該出一則：\(issues.map(\.message))")
    }

    /// 年份不同就不是同一篇——同名不同年的論文（年度報告、系列作）不得被湊成重複。
    func testSameTitleDifferentYearIsNotDuplicate() throws {
        var a = entryWithDOI("a2019a", doi: "10.1000/a", title: "Same"); a.date = "2019"
        var b = entryWithDOI("a2020a", doi: "10.1000/b", title: "Same"); b.date = "2020"
        try store.writeEntry(a); try store.writeEntry(b)
        XCTAssertTrue(try store.load().crossRecordIssues().isEmpty)
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
