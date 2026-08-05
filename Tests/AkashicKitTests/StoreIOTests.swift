import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

final class StoreIOTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-test-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try makeLegacyDirectories(in: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 把 store 切成 **legacy 佈局**（`entries/<citekey>.yaml`、`people/<key>.yaml`）。
    ///
    /// 只給結構性依賴 legacy 檔名語意的測試用——它們斷言檔名等於 citekey / person key。
    /// **不放 setUp**：其餘測試（目錄建立、path traversal 拒絕、config 解析…）與佈局無關，
    /// 整組釘死會拿掉它們在**實際出貨格式**（entities）下的覆蓋（#56 verify DA 發現）。
    ///
    /// 呼叫時機必須在任何寫入之前——此時 store 還是空的，改格式標記不會造成混合佈局。
    private func useLegacyLayout() throws {
        try StoreVersion.write(root: root, format: 1)
    }

    private func makeEntry(_ citekey: String = "cheng2025identifiability") -> Entry {
        Entry(id: UUID(), citekey: citekey, type: "article",
              title: "Identifiability of polychoric models",
              authors: [.literal("Che Cheng")], date: "2025")
    }

    func testWriteEntryExclusiveRefusesExistingDestination() throws {
        try useLegacyLayout()   // 斷言檔名 == key（#56）
        try store.writeEntry(makeEntry("taken2020key"))
        XCTAssertThrowsError(try store.writeEntryExclusive(makeEntry("taken2020key")),
                             "exclusive-create 對既存目的檔必須擲錯而非覆蓋")
        // 一般 writeEntry 仍是 upsert 語意
        XCTAssertNoThrow(try store.writeEntry(makeEntry("taken2020key")))
    }

    /// **只斷言這個 store 實際會用到的目錄**（#101）。`store` 是當前 format 且未註冊，
    /// 所以它用 `entities/`／`libraries/`／`notes/` 加上 in-store 的 index 回落位置；
    /// legacy 的 `entries/`／`people/` 不在其中。完整的條件對照由 `EnsureLayoutTests` 覆蓋。
    func testEnsureLayoutCreatesDirectories() {
        for sub in ["entities", "libraries", "notes", ".akashic"] {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(sub).path, isDirectory: &isDir)
            XCTAssertTrue(exists && isDir.boolValue, "\(sub)/ 應存在")
        }
    }

    func testWriteAndLoadEntryRoundTrip() throws {
        try useLegacyLayout()   // 斷言檔名 == key（#56）
        let entry = makeEntry()
        let url = try store.writeEntry(entry)
        XCTAssertEqual(url.lastPathComponent, "cheng2025identifiability.yaml")
        let load = try store.load()
        XCTAssertEqual(load.entries, [entry])
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    func testWriteEntryOverwritesAtomically() throws {
        try useLegacyLayout()   // 斷言檔名 == key（#56）
        var entry = makeEntry()
        _ = try store.writeEntry(entry)
        entry.title = "Updated title"
        _ = try store.writeEntry(entry)
        let load = try store.load()
        XCTAssertEqual(load.entries.first?.title, "Updated title")
        // atomic write 不留 temp 檔
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("entries"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), ["cheng2025identifiability.yaml"])
    }

    func testLoadQuarantinesBadYAMLWithoutDroppingGood() throws {
        _ = try store.writeEntry(makeEntry())
        let bad = root.appendingPathComponent("entries/broken.yaml")
        try "title: no citekey here\n".write(to: bad, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertEqual(load.quarantined.first?.file, "entries/broken.yaml")
    }

    func testWriteAndLoadPerson() throws {
        try useLegacyLayout()   // 斷言檔名 == key（#56）
        let person = Person(key: "chen-chun-houh", names: ["Chun-Houh Chen", "陳君厚"])
        let url = try store.writePerson(person)
        XCTAssertEqual(url.lastPathComponent, "chen-chun-houh.yaml")
        let load = try store.load()
        XCTAssertEqual(load.people, [person])
    }

    func testLoadEmptyLibraryIsEmpty() throws {
        let load = try store.load()
        XCTAssertTrue(load.entries.isEmpty)
        XCTAssertTrue(load.people.isEmpty)
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    // #23：新 schema person 檔（未知欄位）不再 quarantine——person 可用、欄位保留
    func testLoadToleratesFutureSchemaPersonFile() throws {
        let f = root.appendingPathComponent("people/future-one.yaml")
        try """
        key: future-one
        names:
          - Future One
        affiliations:
          - organization: ISS
        """.write(to: f, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "未知欄位不該進 quarantine（#23 tolerant-preserve）")
        XCTAssertEqual(load.people.map(\.key), ["future-one"])
        XCTAssertEqual(load.people.first?.unknownFields.map(\.key), ["affiliations"])
    }

    // #23：容忍的另一半——read-modify-write 不得剝掉未知欄位（資料毀損防線）
    func testWritePersonPreservesUnknownFieldsOnDisk() throws {
        try useLegacyLayout()   // 斷言檔名 == key（#56）
        let f = root.appendingPathComponent("people/future-two.yaml")
        try """
        key: future-two
        names:
          - Future Two
        facts:
          - kind: rank
            value: 研究員
        """.write(to: f, atomically: true, encoding: .utf8)
        var person = try store.load().people.first(where: { $0.key == "future-two" })!
        person.note = "edited by old binary"          // 舊 binary 的合法編輯
        _ = try store.writePerson(person)
        let text = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(text.contains("edited by old binary"))
        XCTAssertTrue(text.contains("facts"), "寫回時未知欄位必須保留")
        XCTAssertTrue(text.contains("研究員"))
    }
}

extension StoreIOTests {
    // path traversal 防護：write-time 強制 key 格式（security lens HIGH）
    func testWriteEntryRejectsTraversalCitekey() {
        let entry = Entry(id: UUID(), citekey: "../../evil", type: "article", title: "T")
        XCTAssertThrowsError(try store.writeEntry(entry))
    }

    func testWritePersonRejectsBadKey() {
        XCTAssertThrowsError(try store.writePerson(Person(key: "Bad/Key", names: ["X"])))
    }
}

extension StoreIOTests {
    // R3：大小寫變體副檔名（.YAML）也要被枚舉——否則 case-insensitive FS 上
    // 它是寫入目的檔的別名，卻連 quarantine 名單都進不了
    func testUppercaseExtensionIsEnumeratedAndQuarantined() throws {
        let f = root.appendingPathComponent("entries/Broken.YAML")
        try "not: [valid\n".write(to: f, atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertTrue(load.quarantined.first?.file.hasSuffix("Broken.YAML") ?? false)
    }
}

final class LibraryLocatorTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testExplicitPathWins() throws {
        let url = try LibraryLocator.resolve(explicit: "/some/lib",
                                             environment: ["AKASHIC_LIBRARY": "/env/lib"],
                                             configURL: tmp.appendingPathComponent("none.yaml"))
        XCTAssertEqual(url.path, "/some/lib")
    }

    func testEnvironmentFallback() throws {
        let url = try LibraryLocator.resolve(explicit: nil,
                                             environment: ["AKASHIC_LIBRARY": "/env/lib"],
                                             configURL: tmp.appendingPathComponent("none.yaml"))
        XCTAssertEqual(url.path, "/env/lib")
    }

    func testConfigFileFallback() throws {
        let config = tmp.appendingPathComponent("config.yaml")
        try "library: /cfg/lib\n".write(to: config, atomically: true, encoding: .utf8)
        let url = try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: config)
        XCTAssertEqual(url.path, "/cfg/lib")
    }

    func testUnconfiguredThrows() {
        XCTAssertThrowsError(try LibraryLocator.resolve(
            explicit: nil, environment: [:],
            configURL: tmp.appendingPathComponent("none.yaml")))
    }
}

final class RenameTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rename-\(UUID().uuidString)")
        // **必要**：seed(format:) 在 ensureLayout() 之前就寫 store.yaml，此時目錄還不存在。
        // 其餘三個 suite 的同款呼叫是多餘的（那裡 ensureLayout 先跑），已移除。
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try seed(format: 1)   // 預設 legacy——見下方 seed(format:) 說明
    }

    /// 以指定 store format 建好 fixture。
    ///
    /// **格式必須在寫入之前定好**，所以由各測試在開頭選，不是 setUp 寫死（#56 verify DA）。
    ///
    /// ## 為什麼預設仍是 legacy
    ///
    /// 實測「把預設改成 entities」時，7 個既有測試裡有 5 個照樣通過——但**通過不等於有覆蓋**。
    /// `testRenameMovesFileMigratesRelationsKeepsUUID` 斷言 `entries/old2020key.yaml` 不存在，
    /// 而在 entities 佈局下那個路徑**從來就沒存在過**，斷言因此空洞為真。把預設翻成 entities
    /// 只會讓這類斷言安靜地失去意義，比留在 legacy 更糟。
    ///
    /// rename 的核心語意（改 citekey 就搬檔）本來就是 legacy 專屬；entities 佈局的專屬分支
    /// 另由 `testRenameRejectsTakenCitekeyUnderEntitiesLayout` 與
    /// `testRenameUnderEntitiesLayoutKeepsFilenameAndMigratesRelations` 明確覆蓋
    /// （後者斷言 UUID 檔**仍然存在**，是上面那條空洞斷言的實質對應面）。
    ///
    /// **未涵蓋而誠實記錄**：`testRenameRejectsBadOrTakenTarget`、
    /// `testRenameMigratesSelfReferenceAndDuplicates`、`testRenamePreservesLibraries`
    /// 三者是佈局無關的，目前只跑 legacy。要不要讓它們兩種佈局各跑一次，是獨立的取捨，
    /// 不在 #56 範圍。
    private func seed(format: Int) throws {
        try StoreVersion.write(root: root, format: format)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "old2020key", type: "article", title: "T1",
                       authors: [.literal("A")], date: "2020")
        e1.akashic.relations.cites = ["other2019ref"]
        try store.writeEntry(e1)
        var e2 = Entry(id: UUID(), citekey: "citing2021paper", type: "article", title: "T2")
        e2.akashic.relations.cites = ["old2020key"]          // 引用即將被 rename 的 entry
        e2.akashic.relations.related = ["old2020key"]
        try store.writeEntry(e2)
    }

    /// 重建 fixture 為 **entities 佈局**（format 2+）。給要驗 entities 專屬分支的測試用。
    private func reseedAsEntities() throws {
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try seed(format: StoreVersion.supported)
    }

    /// entities 佈局下 `renameEntry` 的專屬守衛：檔名是不變的 UUID，所以「新 citekey
    /// 沒被別人佔用」不再由檔案系統天然保證。沒有這個檢查會安靜地產生兩筆同 citekey。
    ///
    /// 這條分支在 #56 之前完全沒有測試覆蓋（RenameTests 整組跑在 legacy）。
    ///
    /// **覆蓋邊界**：本測試只驗「目的 citekey 被另一筆**成功載入**的記錄佔用」。
    /// 被 **quarantined 檔案**佔用的情形由 `testRenameRejectsQuarantinedTargetUnderEntitiesLayout`
    /// 覆蓋（#61 補上——在那之前 entities 側確實沒有對應面，legacy 靠 `fileExists`
    /// 天然擋下的那一半保護在遷移時掉了）。
    func testRenameRejectsTakenCitekeyUnderEntitiesLayout() throws {
        try reseedAsEntities()
        XCTAssertTrue(store.usesEntitiesLayout, "測試前提：必須是 entities 佈局")
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "citing2021paper"),
                             "新 citekey 已被另一筆佔用，必須拒絕") { err in
            guard case StoreIOError.invalidKey(let field, _) = err else {
                return XCTFail("應為 invalidKey，實得 \(err)")
            }
            XCTAssertTrue(field.contains("citekey"), field)
        }
        // 拒絕後兩筆都必須完好——不得留下半套狀態
        let after = try store.load()
        XCTAssertEqual(Set(after.entries.map(\.citekey)), ["old2020key", "citing2021paper"])
    }

    /// #61：entities 佈局下「目的 citekey 被 **quarantined 檔**佔用」也必須擋。
    ///
    /// legacy 靠 `fileExists(entryURL(citekey:))` 天然擋下——檔名就是 citekey，
    /// 檔案存在就擋，不管內容能不能解析。entities 的檔名是 UUID，那條檢查失去意義，
    /// 替代守衛改掃 `load.entries`——而被 quarantine 的檔案在 `load.quarantined`，
    /// 守衛完全看不到。
    ///
    /// 後果不是「當下壞掉」而是**延遲爆炸**：store 裡同時存在一份宣稱 `qtarget` 的
    /// 隔離檔與一筆剛改名為 `qtarget` 的合法記錄；直到有人修好那份隔離檔，
    /// `crossRecordIssues()` 才突然冒出 citekey 重複。使用者體驗是「我只是修好一個
    /// 舊檔案，為什麼整個 store 就壞了」——錯誤出現的時間與成因相隔任意長。
    func testRenameRejectsQuarantinedTargetUnderEntitiesLayout() throws {
        try reseedAsEntities()
        XCTAssertTrue(store.usesEntitiesLayout, "測試前提：必須是 entities 佈局")
        // 可解析、明確宣稱 citekey: qtarget，但檔名 UUID 與 entry.id 不符 → quarantined
        let fileUUID = UUID(), contentUUID = UUID()
        let yaml = """
        work:
        id: \(contentUUID.uuidString)
        citekey: qtarget
        type: article
        title: Q
        date: '2020'
        """ + "\n"
        try yaml.write(to: store.entitiesDir.appendingPathComponent("\(fileUUID.uuidString).yaml"),
                       atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1, "測試前提：該檔必須被 quarantine")
        XCTAssertFalse(load.entries.contains { $0.citekey == "qtarget" },
                       "測試前提：quarantined 檔不得出現在 entries——否則測的不是這條路徑")

        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "qtarget"),
                             "目的 citekey 被 quarantined 檔佔用，必須拒絕") { err in
            guard case StoreIOError.invalidKey(let field, _) = err else {
                return XCTFail("應為 invalidKey，實得 \(err)")
            }
            XCTAssertTrue(field.contains("citekey"), field)
        }
        // 拒絕後不得留下半套狀態
        let after = try store.load()
        XCTAssertTrue(after.entries.contains { $0.citekey == "old2020key" }, "來源必須完好")
        XCTAssertFalse(after.entries.contains { $0.citekey == "qtarget" })
    }

    /// entities 佈局下改 citekey **不搬檔**（檔名是 UUID），但 citekey 與關係都要更新。
    func testRenameUnderEntitiesLayoutKeepsFilenameAndMigratesRelations() throws {
        try reseedAsEntities()
        let before = try XCTUnwrap(try store.load().entries.first { $0.citekey == "old2020key" })
        let urlBefore = store.entityURL(id: before.id)
        _ = try store.renameEntry(from: "old2020key", to: "new2020key")
        let after = try store.load()
        XCTAssertEqual(after.entries.first { $0.id == before.id }?.citekey, "new2020key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlBefore.path),
                      "entities 佈局下檔名是不變的 UUID，改 citekey 不得搬檔")
        let citing = try XCTUnwrap(after.entries.first { $0.citekey == "citing2021paper" })
        XCTAssertEqual(citing.akashic.relations.cites, ["new2020key"], "關係必須跟著遷移")
        XCTAssertEqual(citing.akashic.relations.related, ["new2020key"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRenameMovesFileMigratesRelationsKeepsUUID() throws {
        let before = try store.load().entries.first { $0.citekey == "old2020key" }!
        let report = try store.renameEntry(from: "old2020key", to: "new2020key")
        XCTAssertEqual(report.relationsRewritten, ["citing2021paper"])

        let load = try store.load()
        XCTAssertNil(load.entries.first { $0.citekey == "old2020key" })
        let renamed = load.entries.first { $0.citekey == "new2020key" }!
        XCTAssertEqual(renamed.id, before.id)                                   // UUID 不變
        XCTAssertEqual(renamed.akashic.relations.cites, ["other2019ref"])       // 自身 relations 不動
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.entryURL(citekey: "old2020key").path))                // 舊檔已刪
        let citing = load.entries.first { $0.citekey == "citing2021paper" }!
        XCTAssertEqual(citing.akashic.relations.cites, ["new2020key"])          // 引用端跟改
        XCTAssertEqual(citing.akashic.relations.related, ["new2020key"])
    }

    func testRenameRejectsBadOrTakenTarget() throws {
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "Bad/Key"))
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "citing2021paper"))
        XCTAssertThrowsError(try store.renameEntry(from: "nope", to: "x2020y"))
    }

    func testRenameRejectsQuarantinedTarget() throws {
        try "broken: [yaml\n".write(to: store.entriesDir.appendingPathComponent("qtarget.yaml"),
                                    atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "old2020key", to: "qtarget"))
    }

    /// relations 遷移的邏輯**不分佈局**（`renameEntry` 的該段不 branch on `usesEntitiesLayout`），
    /// 所以兩種佈局各跑一次——#56 verify round 2 指出只跑 legacy 是未經驗證的假設。
    func testRenameMigratesSelfReferenceAndDuplicates() throws {
        try assertSelfReferenceAndDuplicatesMigrate()
    }

    func testRenameMigratesSelfReferenceAndDuplicatesUnderEntitiesLayout() throws {
        try reseedAsEntities()
        XCTAssertTrue(store.usesEntitiesLayout, "測試前提：必須是 entities 佈局")
        try assertSelfReferenceAndDuplicatesMigrate()
    }

    private func assertSelfReferenceAndDuplicatesMigrate() throws {
        var selfRef = Entry(id: UUID(), citekey: "loop2020self", type: "article", title: "S")
        selfRef.akashic.relations.cites = ["loop2020self", "other2019ref"]
        selfRef.akashic.relations.related = ["loop2020self"]
        try store.writeEntry(selfRef)
        var dup = Entry(id: UUID(), citekey: "dup2021refs", type: "article", title: "D")
        dup.akashic.relations.cites = ["loop2020self", "x2000y", "loop2020self"]   // 重複引用
        try store.writeEntry(dup)

        _ = try store.renameEntry(from: "loop2020self", to: "ring2020self")

        let load = try store.load()
        let renamed = try XCTUnwrap(load.entries.first { $0.citekey == "ring2020self" })
        XCTAssertEqual(renamed.akashic.relations.cites, ["ring2020self", "other2019ref"],
                       "self-reference 必須跟著 rename")
        XCTAssertEqual(renamed.akashic.relations.related, ["ring2020self"])
        let dupAfter = try XCTUnwrap(load.entries.first { $0.citekey == "dup2021refs" })
        XCTAssertEqual(dupAfter.akashic.relations.cites, ["ring2020self", "x2000y", "ring2020self"],
                       "同一陣列的所有出現都必須遷移，不只第一個")
    }

    func testRenameRefusesMalformedOldKeyFromDisk() throws {
        // 磁碟上偽造 citekey=../outside 的 entry；rename 絕不可刪 entriesDir 之外的檔案
        let outside = root.appendingPathComponent("outside.yaml")
        try "sentinel".write(to: outside, atomically: true, encoding: .utf8)
        let seedURL = try store.writeEntry(
            Entry(id: UUID(), citekey: "victim2020x", type: "article", title: "V"))
        let evil = try String(contentsOf: seedURL, encoding: .utf8)
            .replacingOccurrences(of: "citekey: victim2020x", with: "citekey: ../outside")
        try evil.write(to: store.entriesDir.appendingPathComponent("evil.yaml"),
                       atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: seedURL)

        XCTAssertThrowsError(try store.renameEntry(from: "../outside", to: "fixed2020key"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path),
                      "庫外檔案不可被 rename 的刪除路徑觸及")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.entryURL(citekey: "fixed2020key").path))
    }
}

/// load() 的語意完整性：成功 decode 但 key 不合法／檔名不符的 entry 必須 quarantine，
/// 不得帶著畸形 citekey 進入 library（rename 刪除路徑、entryURL 組合的共同前提）。
final class LoadIntegrityTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-integrity-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try makeLegacyDirectories(in: root)   // fixture 手寫原始檔進 entries/、people/（#101）
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLoadQuarantinesMalformedCitekey() throws {
        let seedURL = try store.writeEntry(
            Entry(id: UUID(), citekey: "victim2020x", type: "article", title: "V"))
        let evil = try String(contentsOf: seedURL, encoding: .utf8)
            .replacingOccurrences(of: "citekey: victim2020x", with: "citekey: ../victim")
        try evil.write(to: store.entriesDir.appendingPathComponent("evil.yaml"),
                       atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: seedURL)

        let load = try store.load()
        XCTAssertTrue(load.entries.isEmpty, "畸形 citekey 不得進入 entries")
        XCTAssertEqual(load.quarantined.map(\.file), ["entries/evil.yaml"])
    }

    func testLoadQuarantinesFilenameStemMismatch() throws {
        let url = try store.writeEntry(
            Entry(id: UUID(), citekey: "other2020key", type: "article", title: "O"))
        try FileManager.default.copyItem(
            at: url, to: store.entriesDir.appendingPathComponent("alias2020copy.yaml"))

        let load = try store.load()
        XCTAssertEqual(load.entries.map(\.citekey), ["other2020key"],
                       "檔名與 citekey 不符的複本不得載入（避免重複 entry 與錯位刪除）")
        XCTAssertEqual(load.quarantined.map(\.file), ["entries/alias2020copy.yaml"])
    }

    func testLoadQuarantinesPersonStemMismatch() throws {
        let url = try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try FileManager.default.copyItem(
            at: url, to: store.peopleDir.appendingPathComponent("wrong-stem.yaml"))

        let load = try store.load()
        XCTAssertEqual(load.people.map(\.key), ["cheng-che"])
        XCTAssertEqual(load.quarantined.map(\.file), ["people/wrong-stem.yaml"])
    }
}

/// #13 多 library：libraries/ registry 的寫入驗證與 load 語意驗證。
final class LibraryRegistryStoreTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lib-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try makeLegacyDirectories(in: root)   // fixture 手寫原始檔進 entries/（#101）
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testWriteLibraryValidatesKeyAndRoundTrips() throws {
        XCTAssertThrowsError(try store.writeLibrary(Library(key: "Bad Key", name: "X")),
                             "不合 StoreKey 的 library key 拒寫")
        let url = try store.writeLibrary(Library(key: "sinica", name: "中研院"))
        XCTAssertEqual(url.lastPathComponent, "sinica.yaml")
        let load = try store.load()
        XCTAssertEqual(load.libraries.map(\.key), ["sinica"])
    }

    func testLoadQuarantinesBadLibraryFiles() throws {
        let good = try store.writeLibrary(Library(key: "psychology", name: "心理學"))
        // stem 不符的複本 → quarantine
        try FileManager.default.copyItem(
            at: good, to: store.librariesDir.appendingPathComponent("alias.yaml"))
        // 語法壞檔 → quarantine
        try "broken: [yaml\n".write(
            to: store.librariesDir.appendingPathComponent("broken.yaml"),
            atomically: true, encoding: .utf8)

        let load = try store.load()
        XCTAssertEqual(load.libraries.map(\.key), ["psychology"])
        XCTAssertEqual(load.quarantined.map(\.file).sorted(),
                       ["libraries/alias.yaml", "libraries/broken.yaml"])
    }

    func testEntryLibrariesMembershipPersists() throws {
        var e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article", title: "T")
        e.akashic.libraries = ["sinica"]
        try store.writeEntry(e)
        let load = try store.load()
        XCTAssertEqual(load.entries.first?.akashic.libraries, ["sinica"])
    }
}

/// #13 verify fix round：registry exclusive-create、membership 語意驗證。
extension LibraryRegistryStoreTests {
    func testWriteLibraryIsExclusiveCreate() throws {
        _ = try store.writeLibrary(Library(key: "sinica", name: "中研院"))
        XCTAssertThrowsError(try store.writeLibrary(Library(key: "sinica", name: "覆寫")),
                             "registry 寫入必須 exclusive-create（並發 create 不得靜默互吃）")
    }

    func testWriteEntryRejectsDuplicateMembership() {
        var e = Entry(id: UUID(), citekey: "dup2020test", type: "article", title: "T")
        e.akashic.libraries = ["sinica", "sinica"]
        XCTAssertThrowsError(try store.writeEntry(e), "重複 membership 拒寫")
    }

    func testLoadQuarantinesEntriesWithBadOrDuplicateMembership() throws {
        _ = try store.writeEntry(
            Entry(id: UUID(), citekey: "seed2020a", type: "article", title: "A"))
        let badYAML = """
        id: 7C1F6C2E-0000-0000-0000-00000000AAAA
        citekey: badmember2020x
        type: article
        title: Bad member
        akashic:
          libraries:
            - Bad Key
        """
        try badYAML.write(to: store.entriesDir.appendingPathComponent("badmember2020x.yaml"),
                          atomically: true, encoding: .utf8)
        let dupYAML = """
        id: 7C1F6C2E-0000-0000-0000-00000000BBBB
        citekey: dupmember2020x
        type: article
        title: Dup member
        akashic:
          libraries:
            - sinica
            - sinica
        """
        try dupYAML.write(to: store.entriesDir.appendingPathComponent("dupmember2020x.yaml"),
                          atomically: true, encoding: .utf8)

        let load = try store.load()
        // 畸形 key → quarantine；純重複 → auto-dedupe 保序載入（DA 裁決）
        XCTAssertEqual(load.entries.map(\.citekey), ["dupmember2020x", "seed2020a"])
        XCTAssertEqual(load.quarantined.map(\.file), ["entries/badmember2020x.yaml"])
        let dup = load.entries.first { $0.citekey == "dupmember2020x" }!
        XCTAssertEqual(dup.akashic.libraries, ["sinica"], "重複 key 去重保序（load 靜默正規化）")
        // validate() 的重複警告針對未正規化的原始構造（寫前 lint 用）
        var raw = dup
        raw.akashic.libraries = ["sinica", "sinica"]
        XCTAssertTrue(raw.validate().contains { $0.message.contains("重複") })
    }

    func testLoadSafeWhenLibrariesDirAbsent() throws {
        // v1.1 root（無 libraries/）——load 必須安全、libraries 為空
        let v11root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-v11-\(UUID().uuidString)")
        let s = LibraryStore(root: v11root)
        try FileManager.default.createDirectory(
            at: v11root.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: v11root.appendingPathComponent("people"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: v11root) }
        let load = try s.load()
        XCTAssertTrue(load.libraries.isEmpty)
        XCTAssertTrue(load.quarantined.isEmpty)
    }
}

/// #13：rename 保留 membership（per-entry 設計的結構保證，回歸測試釘住）。
extension RenameTests {
    /// library membership 的保存**不分佈局**——兩種各跑一次（#56 verify round 2）。
    func testRenamePreservesLibraries() throws {
        try assertLibrariesPreservedThroughRename()
    }

    func testRenamePreservesLibrariesUnderEntitiesLayout() throws {
        try reseedAsEntities()
        XCTAssertTrue(store.usesEntitiesLayout, "測試前提：必須是 entities 佈局")
        try assertLibrariesPreservedThroughRename()
    }

    private func assertLibrariesPreservedThroughRename() throws {
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "old2020key" })
        e.akashic.libraries = ["sinica"]
        try store.writeEntry(e)
        _ = try store.renameEntry(from: "old2020key", to: "kept2020key")
        let renamed = try XCTUnwrap(try store.load().entries.first { $0.citekey == "kept2020key" })
        XCTAssertEqual(renamed.akashic.libraries, ["sinica"])
    }
}

/// #18 多檔案：AkashicConfig parse/write + LibraryLocator registry resolution。
final class MultiFileConfigTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeConfig(_ text: String) throws -> URL {
        let url = dir.appendingPathComponent("config.yaml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testParseFullSchema() throws {
        let url = try writeConfig("""
        library: /legacy/root
        files:
          main: /path/a
          work: /path/b
        current: work
        """)
        let config = try AkashicConfig.read(from: url)
        XCTAssertEqual(config.library, "/legacy/root")
        XCTAssertEqual(config.files, ["main": "/path/a", "work": "/path/b"])
        XCTAssertEqual(config.current, "work")
    }

    func testParseLegacyOnlyUnchanged() throws {
        let url = try writeConfig("library: /legacy/root\n")
        let config = try AkashicConfig.read(from: url)
        XCTAssertEqual(config.library, "/legacy/root")
        XCTAssertTrue(config.files.isEmpty)
        XCTAssertNil(config.current)
    }

    func testMalformedFileKeyThrows() throws {
        let url = try writeConfig("files:\n  Bad_Key: /x\n")
        XCTAssertThrowsError(try AkashicConfig.read(from: url), "file key 走 StoreKey 規則")
    }

    func testWriteRoundTripPreservesUnknownLines() throws {
        let url = try writeConfig("""
        library: /legacy/root
        some_future_field: keep-me
        """)
        var config = try AkashicConfig.read(from: url)
        config.files["work"] = "/path/b"
        config.current = "work"
        try config.write(to: url)
        let reread = try AkashicConfig.read(from: url)
        XCTAssertEqual(reread.files, ["work": "/path/b"])
        XCTAssertEqual(reread.current, "work")
        XCTAssertEqual(reread.library, "/legacy/root")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("some_future_field: keep-me"), "未知頂層欄位保留")
    }

    func testResolveCurrentFileWins() throws {
        let url = try writeConfig("""
        library: /legacy/root
        files:
          work: /path/b
        current: work
        """)
        let root = try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: url)
        XCTAssertEqual(root.path, "/path/b")
    }

    func testResolveLegacyFallbackWhenNoCurrent() throws {
        let url = try writeConfig("""
        library: /legacy/root
        files:
          work: /path/b
        """)
        let root = try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: url)
        XCTAssertEqual(root.path, "/legacy/root")
    }

    func testResolveInvalidCurrentThrows() throws {
        let url = try writeConfig("""
        files:
          work: /path/b
        current: ghost
        """)
        XCTAssertThrowsError(try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: url),
                             "current 指向不存在 key 擲錯，不靜默 fallback")
    }

    func testExplicitAndEnvStillWin() throws {
        let url = try writeConfig("files:\n  work: /path/b\ncurrent: work\n")
        XCTAssertEqual(try LibraryLocator.resolve(explicit: "/exp", environment: [:], configURL: url).path, "/exp")
        XCTAssertEqual(try LibraryLocator.resolve(explicit: nil,
                                                  environment: ["AKASHIC_LIBRARY": "/env"],
                                                  configURL: url).path, "/env")
    }
}

/// #18 verify R1：config 存在但不可讀 → 擲錯（不得當空 config 覆寫 registry）。
extension MultiFileConfigTests {
    func testUnreadableExistingConfigThrowsNotEmpty() throws {
        let url = dir.appendingPathComponent("config.yaml")
        // 寫入非 UTF-8 bytes：檔案存在但 .utf8 解不開
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: url)
        XCTAssertThrowsError(try AkashicConfig.read(from: url),
                             "存在但讀不到 ≠ 空 config——防 RMW 靜默清空")
    }
}

/// #18 Codex R1：parser 向後相容與 round-trip 加固。
extension MultiFileConfigTests {
    func testIndentedLegacyLibraryStillResolves() throws {
        let url = try { let u = dir.appendingPathComponent("c6.yaml")
            try "  library: /legacy/indented\n".write(to: u, atomically: true, encoding: .utf8); return u }()
        let root = try LibraryLocator.resolve(explicit: nil, environment: [:], configURL: url)
        XCTAssertEqual(root.path, "/legacy/indented", "舊版 trim 掃描接受縮排 library:——零改變")
    }

    func testCommentsSurviveRoundTrip() throws {
        let url = dir.appendingPathComponent("c7.yaml")
        try "# 我的註解\nlibrary: /x\n".write(to: url, atomically: true, encoding: .utf8)
        var config = try AkashicConfig.read(from: url)
        config.current = nil
        try config.write(to: url)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("# 我的註解"), "使用者註解不得在 RMW 中被丟棄")
    }

    func testQuotedValuesUnquoted() throws {
        let url = dir.appendingPathComponent("c8.yaml")
        try "library: \"/with space/lib\"\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try AkashicConfig.read(from: url).library, "/with space/lib")
    }
}

/// #18 Codex R2：inline comment、ENOENT 嚴格性、entries 目錄檢查。
extension MultiFileConfigTests {
    func testInlineCommentStrippedUnlessQuoted() throws {
        let url = dir.appendingPathComponent("c9.yaml")
        try """
        library: /plain/path # 這是註解
        files:
          work: "/quoted/with #hash"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = try AkashicConfig.read(from: url)
        XCTAssertEqual(config.library, "/plain/path", "unquoted 的 inline comment 要剝")
        XCTAssertEqual(config.files["work"], "/quoted/with #hash", "quoted 內的 # 是字面值")
    }

    func testEntriesAsPlainFileIsNotLibraryRoot() throws {
        let root = dir.appendingPathComponent("fake-root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "file".write(to: root.appendingPathComponent("entries"), atomically: true, encoding: .utf8)
        XCTAssertFalse(LibraryStore.isLibraryRoot(root), "entries 是普通檔案不算 library")
        let real = dir.appendingPathComponent("real-root")
        try LibraryStore(root: real).ensureLayout()
        XCTAssertTrue(LibraryStore.isLibraryRoot(real))
    }
}

/// #18 Codex R3：含「 #」值的 round-trip 對稱（writer 按需加引號）。
extension MultiFileConfigTests {
    func testValueWithHashRoundTripsThroughWrite() throws {
        let url = dir.appendingPathComponent("c10.yaml")
        var config = AkashicConfig()
        config.files = ["work": "/tmp/a # b"]
        config.library = "/lib with #hash"
        try config.write(to: url)
        let reread = try AkashicConfig.read(from: url)
        XCTAssertEqual(reread.files["work"], "/tmp/a # b", "write→read 不得截斷")
        XCTAssertEqual(reread.library, "/lib with #hash")
        // 再寫再讀一輪（冪等）
        try reread.write(to: url)
        XCTAssertEqual(try AkashicConfig.read(from: url).files["work"], "/tmp/a # b")
    }

    func testQuotedValueFollowedByInlineComment() throws {
        let url = dir.appendingPathComponent("c11.yaml")
        try "library: \"/tmp/a # b\" # 真正的註解\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try AkashicConfig.read(from: url).library, "/tmp/a # b",
                       "引號內 # 字面值；引號後的 inline comment 忽略")
    }
}

// R7（#23 verify R6）：rename 預檢與 unknownFieldFiles 實際檔名的 regression
extension RenameTests {
    /// L32：preflight encode 失敗 → rename 完全不動磁碟（無半遷移）。
    func testRenamePreflightAbortsBeforeTouchingDisk() throws {
        var a = Entry(id: UUID(), citekey: "aaa1", type: "article", title: "A")
        a.akashic.relations.cites = []
        try store.writeEntry(a)
        // 手寫一個「decode 容忍、encode 拒寫」的凍結記錄，relations 引用 aaa1
        let frozen = """
        id: 7C1F6C2E-0000-0000-0000-00000000BB01
        citekey: frozen2
        type: article
        title: T
        akashic:
            relations:
              cites:
              - aaa1
            weird: [a,
          b]
        """
        try (frozen + "\n").write(
            to: store.entriesDir.appendingPathComponent("frozen2.yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "aaa1", to: "bbb2"))
        // 磁碟完全未動：舊檔在、新檔不在、凍結檔原文未變
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.entriesDir.appendingPathComponent("aaa1.yaml").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.entriesDir.appendingPathComponent("bbb2.yaml").path))
        let onDisk = try String(
            contentsOf: store.entriesDir.appendingPathComponent("frozen2.yaml"),
            encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- aaa1"))
    }
}

extension StoreIOTests {
    /// L34：unknownFieldFiles 回報實際檔名（含 `.YAML` 大小寫別名）。
    func testUnknownFieldFilesReportsActualFilename() throws {
        try FileManager.default.createDirectory(
            at: store.root.appendingPathComponent("people"), withIntermediateDirectories: true)
        try "key: fut1\nextra: 1\n".write(
            to: store.root.appendingPathComponent("people/fut1.YAML"),
            atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.unknownFieldFiles, ["people/fut1.YAML"], "\(load.quarantined)")
    }
}
