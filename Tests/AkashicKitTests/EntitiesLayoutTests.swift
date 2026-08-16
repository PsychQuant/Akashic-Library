import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #35：`entities/<uuid>.yaml` —— 分類不進路徑，檔名是不變的身分。
final class EntitiesLayoutTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ ck: String, id: UUID = UUID()) -> Entry {
        Entry(id: id, citekey: ck, type: "article", title: "T",
              authors: [.literal("X")], date: "2020")
    }
    private func legacyStore() throws -> LibraryStore {
        let fm = FileManager.default
        for d in ["entries", "people", "libraries"] {
            try fm.createDirectory(at: root.appendingPathComponent(d),
                                   withIntermediateDirectories: true)
        }
        try StoreVersion.write(root: root, format: 1)
        return LibraryStore(root: root)
    }

    // MARK: - 確定性身分（v5 機制——#241 起 person 無生產推導，機制仍服務 org／divergence）

    /// v5 的確定性：同 namespace + name 永遠推出同一個 UUID。person 的推導函式已
    /// 退場（#241），這裡以 personNamespace 釘住**機制本身**——測試 fabricate 舊
    /// fixture 與 org／divergence 的推導都靠它。
    func testPersonUUIDIsDeterministic() {
        let a = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "cheng-che")
        let b = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "cheng-che")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "cheng-chi"))
        // 必須是合法的 UUIDv5（version 5、RFC 4122 variant）——否則別的工具會當它壞掉
        let s = a.uuidString
        XCTAssertEqual(s[s.index(s.startIndex, offsetBy: 14)], "5", "version nibble 非 5：\(s)")
        XCTAssertTrue("89ab".contains(s[s.index(s.startIndex, offsetBy: 19)].lowercased()),
                      "variant 位元不符 RFC 4122：\(s)")
    }

    /// **對照獨立實作的 RFC 4122 §4.3 測試向量。** 只驗「version/variant 位元對」不夠
    /// ——那只證明它長得像 UUIDv5，不證明它**是**。若 namespace 的 byte order 弄反，
    /// 位元檢查照樣過，但推出的 id 與世界上任何其他 UUIDv5 實作都對不上。
    func testUUIDv5MatchesRFCTestVector() {
        // Python `uuid.uuid5(uuid.NAMESPACE_DNS, "python.org")`
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        XCTAssertEqual(DeterministicUUID.v5(namespace: dns, name: "python.org").uuidString
                        .lowercased(),
                       "886313e1-3b8a-5372-9b90-0c9aee199e5d")
        // 本專案的 namespace，對照同一個獨立實作
        XCTAssertEqual(DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: "cheng-che").uuidString.lowercased(),
                       "7a7f0a53-9d44-5f61-8b54-e3b8b791c7f8")
    }

    // MARK: - record-identity（#241）：身分只有一個產生事件

    /// spec `record-identity`「Two records with identical attributes receive different
    /// identifiers」：同 key 的兩筆新記錄不得共用身分——兩個不同 library 各自叫
    /// `chen-wei` 的**不同的人**，合併時必須仍可區分（v5(key) 會讓它們安靜熔成一筆）。
    func testNewPersonsWithSameKeyGetDistinctIDs() {
        let a = Person(key: "chen-wei")
        let b = Person(key: "chen-wei")
        XCTAssertNotEqual(a.id, b.id, "身分不得是名字（key）的函數")
    }

    /// 新建 person 的 id 不得等於舊推導函式對同一 key 的輸出——推導預設已退場。
    func testNewPersonIDIsNotDerivedFromKey() {
        let derived = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace,
                                           name: "chen-wei")
        XCTAssertNotEqual(Person(key: "chen-wei").id, derived)
    }

    /// 缺 `id:` 的 person 檔 fail-closed——decode 不得推導（那是 default 位置的
    /// compat fallback，#241 裁決退場）也不得隨機發（同檔每次載入不同身分，index
    /// 主鍵與引用全漂）。舊檔只能經遷移路徑進來，與平坦 names 的拒絕同紀律。
    func testPersonFileWithoutIDIsRefused() {
        let yaml = "key: p-one\nnames: {variant: [A]}\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("person.id"), "訊息要點名欄位：\(error)")
        }
    }

    /// `id` 在場但格式錯 → fail-closed。**不猜**：亂猜會讓引用安靜地對不上。
    func testMalformedPersonIDIsRejected() {
        XCTAssertThrowsError(try PersonYAML.decode("id: not-a-uuid\nkey: p\nnames: {variant: [A]}\n"))
    }

    // MARK: - 佈局選擇由 format 決定

    /// **判準是 store format，不是「entities/ 目錄存不存在」。** 目錄可能因為
    /// ensureLayout 或半途中斷而存在卻是空的，用它當判準會讓寫入端在遷移完成前
    /// 就往新位置寫。
    func testLayoutFollowsFormatNotDirectoryPresence() throws {
        let store = try legacyStore()
        try FileManager.default.createDirectory(at: store.entitiesDir,
                                                withIntermediateDirectories: true)
        XCTAssertFalse(store.usesEntitiesLayout, "空的 entities/ 不得使 store 改走新佈局")
        let e = entry("a2020a")
        let written = try store.writeEntry(e)
        XCTAssertEqual(written.deletingLastPathComponent().lastPathComponent, "entries")
    }

    func testFormat2WritesToEntitiesByUUID() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()                      // 空 store → format 2
        XCTAssertTrue(store.usesEntitiesLayout)
        let e = entry("a2020a")
        let url = try store.writeEntry(e)
        XCTAssertEqual(url.lastPathComponent, "\(e.id.uuidString).yaml")
        XCTAssertEqual(try store.load().entries.first?.citekey, "a2020a")
    }

    /// **既有 legacy store 沒有 marker 時不得被誤標成 format 2**——那會讓寫入端往
    /// `entities/` 去，而檔案全在 `entries/`，兩個佈局並存且沒有任何訊號。
    func testExistingLegacyStoreWithoutMarkerIsNotMislabelled() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("entries"),
                               withIntermediateDirectories: true)
        try "id: 11111111-1111-1111-1111-111111111111\ncitekey: a2020a\ntype: article\ntitle: T\nauthors:\n  - literal: X\n"
            .write(to: root.appendingPathComponent("entries/a2020a.yaml"),
                   atomically: true, encoding: .utf8)
        let store = LibraryStore(root: root)
        try store.ensureLayout()                      // 有 legacy 內容 → 必須標 1
        XCTAssertEqual(try StoreVersion.read(root: root), 1)
        XCTAssertFalse(store.usesEntitiesLayout)
    }

    // MARK: - entities 讀取的完整性

    /// 檔名即身分：stem 與記錄的 id 不符 → quarantine。不符代表有人改了檔名或 id，
    /// 兩者都會讓引用錯位。
    func testFilenameUUIDMustMatchRecordID() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let e = entry("a2020a")
        try EntryYAML.encode(e).write(
            to: store.entitiesDir.appendingPathComponent("\(UUID().uuidString).yaml"),
            atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 0)
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertTrue(load.quarantined[0].reason.contains("不符"), load.quarantined[0].reason)
    }

    func testNonUUIDFilenameInEntitiesIsQuarantined() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try EntryYAML.encode(entry("a2020a")).write(
            to: store.entitiesDir.appendingPathComponent("a2020a.yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().quarantined.count, 1)
    }

    /// work 與 person 住同一個目錄，靠 `type` 分辨。
    func testWorkAndPersonCoexistInEntities() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(entry("a2020a"))
        try store.writePerson(Person(key: "p-one", names: ["A"]))
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.people.count, 1)
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
    }

    /// **legacy 與 entities 並存讀取**——舊佈局的 store（別人的 clone、未遷移的備份）
    /// 必須照樣讀得到。
    func testLegacyAndEntitiesBothRead() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("legacy2020a"))          // → entries/
        try FileManager.default.createDirectory(at: store.entitiesDir,
                                                withIntermediateDirectories: true)
        let e2 = entry("new2021b")
        try EntryYAML.encode(e2).write(to: store.entityURL(id: e2.id),
                                       atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(Set(load.entries.map(\.citekey)), ["legacy2020a", "new2021b"])
    }

    // MARK: - rename 在 format 2 下不搬檔案

    /// entities 佈局最直接的好處：**改稱呼不再是一次多檔搬移**，也就沒有
    /// 「新舊並存」這個中斷態。
    func testRenameDoesNotMoveFileInFormat2() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let e = entry("old2020a")
        try store.writeEntry(e)
        let before = try FileManager.default.contentsOfDirectory(atPath: store.entitiesDir.path)
        _ = try store.renameEntry(from: "old2020a", to: "new2020b")
        let after = try FileManager.default.contentsOfDirectory(atPath: store.entitiesDir.path)
        XCTAssertEqual(before, after, "format 2 的 rename 不該產生新檔或刪舊檔")
        XCTAssertEqual(try store.load().entries.first?.citekey, "new2020b")
    }

    /// 檔名不再是 citekey，所以「新 citekey 未被佔用」不再由檔案系統天然保證——
    /// 沒有顯式檢查會安靜地產生兩筆同 citekey。
    func testRenameToOccupiedCitekeyIsRejectedInFormat2() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(entry("a2020a"))
        try store.writeEntry(entry("b2021b"))
        XCTAssertThrowsError(try store.renameEntry(from: "a2020a", to: "b2021b"))
        XCTAssertEqual(Set(try store.load().entries.map(\.citekey)), ["a2020a", "b2021b"])
    }

    /// **雙佈局並存時同一筆會被讀兩次**（半途遷移、還原的備份、git merge）。
    /// 這不是假想——遷移前後正是最可能出現的狀態。必須被跨記錄檢查接住，
    /// 而不是留給 index 的 UNIQUE constraint 去撞。
    func testSameRecordInBothLayoutsIsCaughtAsDuplicate() throws {
        let store = try legacyStore()
        let e = entry("a2020a")
        try store.writeEntry(e)                                   // → entries/
        try FileManager.default.createDirectory(at: store.entitiesDir,
                                                withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id),
                                      atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 2, "雙佈局下同一筆確實被讀兩次")
        let issues = load.crossRecordIssues().filter { $0.severity == .error }
        XCTAssertEqual(issues.count, 2, "重複 UUID 與重複 citekey 都要報：\(issues)")
    }

    // MARK: - 遷移

    func testMigrationMovesEverythingAndBumpsFormat() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        try store.writeEntry(entry("b2021b"))
        // #227：legacy 具名寫入被 v10 閘拒——fixture 手寫檔案（migration 只搬檔）
        try "id: 11111111-1111-4111-8111-111111111111\nkey: p-one\nnames: {variant: [A]}\n".write(
            to: store.peopleDir.appendingPathComponent("p-one.yaml"),
            atomically: true, encoding: .utf8)

        let report = try StoreMigration.toEntities(store: store)
        XCTAssertEqual(report.entriesMoved, 2)
        XCTAssertEqual(report.peopleMoved, 1)
        XCTAssertEqual(try StoreVersion.read(root: root), 2)

        let load = try store.load()
        XCTAssertEqual(Set(load.entries.map(\.citekey)), ["a2020a", "b2021b"])
        XCTAssertEqual(load.people.map(\.key), ["p-one"])
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        // legacy 檔已清掉——留著會讓 load 讀到兩份
        XCTAssertTrue(try FileManager.default
            .contentsOfDirectory(atPath: store.entriesDir.path).isEmpty)
    }

    /// **有 quarantine 就不遷移**：那些檔的內容讀不出來，搬過去只會把問題帶進新佈局，
    /// 並失去「它原本在哪、叫什麼」這個唯一線索。
    func testMigrationRefusesWhenQuarantinedFilesExist() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        try "這不是合法 YAML: [".write(
            to: store.entriesDir.appendingPathComponent("broken.yaml"),
            atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try StoreMigration.toEntities(store: store)) {
            guard case StoreMigration.MigrationError.quarantinedFilesPresent = $0 else {
                return XCTFail("應為 quarantinedFilesPresent，實得 \($0)")
            }
        }
        XCTAssertEqual(try StoreVersion.read(root: root), 1, "失敗後 format 不得被 bump")
    }

    func testDryRunTouchesNothing() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        let report = try StoreMigration.toEntities(store: store, dryRun: true)
        XCTAssertEqual(report.entriesMoved, 1)
        XCTAssertEqual(try StoreVersion.read(root: root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.entitiesDir.path))
    }

    // MARK: - verify 抓到的問題（PR #48）

    /// **CRITICAL：fresh clone 開不起來。** git 不追蹤空目錄，所以遷移後的 store
    /// clone 出來只有 `entities/`——只認 `entries/` 的話換一台機器就用不了。
    func testFreshCloneWithOnlyEntitiesIsRecognised() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("entities"),
                               withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: 2)
        XCTAssertTrue(LibraryStore.isLibraryRoot(root),
                      "只有 entities/ 的 store 必須被認得（新 clone 的實際樣子）")
    }

    func testLegacyRootStillRecognised() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entries"),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(LibraryStore.isLibraryRoot(root))
    }

    /// 普通檔案冒充目錄不算（R2 #3 的既有防護，不得因為本次改動而失效）。
    func testPlainFileNamedEntitiesIsNotALibrary() throws {
        try "x".write(to: root.appendingPathComponent("entities"),
                      atomically: true, encoding: .utf8)
        XCTAssertFalse(LibraryStore.isLibraryRoot(root))
    }

    /// **CRITICAL：兩筆映到同一目的 UUID。** 照做會讓後寫的覆蓋前寫的、兩份 legacy
    /// 都被刪 → 永久失去一筆。必須在動磁碟前擋下。
    func testMigrationRefusesDuplicateDestinationUUID() throws {
        let store = try legacyStore()
        let shared = UUID()
        try store.writeEntry(entry("a2020a", id: shared))
        try store.writeEntry(entry("b2021b", id: shared))
        XCTAssertThrowsError(try StoreMigration.toEntities(store: store)) { err in
            // 重複 UUID 先被 crossRecordIssues 擋（兩者都是正確的拒絕理由）
            switch err {
            case StoreMigration.MigrationError.duplicateDestination,
                 StoreMigration.MigrationError.crossRecordIssues: break
            default: XCTFail("必須擋下重複目的檔，實得 \(err)")
            }
        }
        XCTAssertEqual(try StoreVersion.read(root: root), 1, "失敗後不得 bump")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.entitiesDir.appendingPathComponent("\(shared.uuidString).yaml").path),
            "動磁碟前就該擋下")
    }

    /// **entry.id 撞到 person 的衍生 id**——不同型別、不同集合，`crossRecordIssues`
    /// 涵蓋不到，必須由遷移自己檢查。
    func testMigrationRefusesEntryPersonUUIDCollision() throws {
        let store = try legacyStore()
        // #227：同上，手寫 legacy person 檔；entry 撞同一個 UUID
        let pid = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        try "id: \(pid.uuidString)\nkey: p-one\nnames: {variant: [A]}\n".write(
            to: store.peopleDir.appendingPathComponent("p-one.yaml"),
            atomically: true, encoding: .utf8)
        try store.writeEntry(entry("a2020a", id: pid))
        XCTAssertThrowsError(try StoreMigration.toEntities(store: store)) { err in
            guard case StoreMigration.MigrationError.duplicateDestination = err else {
                return XCTFail("跨型別的 UUID 碰撞必須擋下，實得 \(err)")
            }
        }
    }

    /// **legacy 刪不掉時不得 bump format。** bump 了會讓 store 進入死角：雙佈局並存
    /// 使 index 撞 UNIQUE constraint 永遠 rebuild 不了，而 format 已是 2 使 migrate 拒絕再跑。
    func testMigrationDoesNotBumpWhenLegacyDeletionFails() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        // 讓 entries/ 唯讀 → removeItem 失敗
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.entriesDir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755],
                                      ofItemAtPath: store.entriesDir.path) }
        XCTAssertThrowsError(try StoreMigration.toEntities(store: store)) { err in
            guard case StoreMigration.MigrationError.legacyDeletionFailed = err else {
                return XCTFail("刪除失敗必須擲錯，實得 \(err)")
            }
        }
        XCTAssertEqual(try StoreVersion.read(root: root), 1,
                       "刪不掉時 format 必須留在 1——讀取端照舊佈局運作，資料一致")
    }

    /// marker 壞掉時**不得靜默當 format 1**——寫入端會把新記錄寫進 entries/，
    /// 而其餘資料在 entities/，兩個佈局並存且無訊號。
    func testCorruptMarkerFallsBackToDiskFactsNotFormat1() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(entry("a2020a"))            // → entities/
        try "garbage without format line\n".write(to: StoreVersion.url(in: root),
                                                  atomically: true, encoding: .utf8)
        XCTAssertTrue(store.usesEntitiesLayout,
                      "marker 壞掉時應以磁碟事實兜底（entities/ 有內容 → format 2）")
    }

    /// **雙佈局並存時改寫必須拒絕。** `renameEntry` 的刪除路徑只按 store format 推算
    /// 位置，所以它會刪掉其中一份而留下另一份——留下的還是舊 citekey。
    /// 讀取面（validate / doctor）刻意不擋：診斷工具在這種狀態下正是最該說話的時候。
    func testRenameRefusesWhenRecordExistsInBothLayouts() throws {
        let store = try legacyStore()
        let e = entry("a2020a")
        try store.writeEntry(e)                                     // → entries/
        try FileManager.default.createDirectory(at: store.entitiesDir,
                                                withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id),
                                      atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.renameEntry(from: "a2020a", to: "b2021b")) { err in
            guard case StoreIOError.inconsistentStore = err else {
                return XCTFail("應為 inconsistentStore，實得 \(err)")
            }
        }
        // 兩份都還在——拒絕不得留下部分狀態
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entryURL(citekey: "a2020a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entityURL(id: e.id).path))
    }

    /// 讀取面**不擋**——那是診斷工具該說話的時候。
    func testValidateStillReportsInsteadOfRefusing() throws {
        let store = try legacyStore()
        let e = entry("a2020a")
        try store.writeEntry(e)
        try FileManager.default.createDirectory(at: store.entitiesDir,
                                                withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id),
                                      atomically: true, encoding: .utf8)
        let load = try store.load()                                  // 不擲錯
        XCTAssertEqual(load.entries.count, 2)
        XCTAssertEqual(load.crossRecordIssues().filter { $0.severity == .error }.count, 2)
    }

    func testMigrationIsIdempotent() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        _ = try StoreMigration.toEntities(store: store)
        // 已是 format 2 → 拒絕重跑（而不是做出奇怪的半套動作）
        XCTAssertThrowsError(try StoreMigration.toEntities(store: store)) {
            guard case StoreMigration.MigrationError.alreadyAtFormat(2) = $0 else {
                return XCTFail("應為 alreadyAtFormat(2)，實得 \($0)")
            }
        }
    }

    /// 遷移後舊 binary 必須**整體拒絕**開啟——這正是 #24 的 refuse-if-newer 存在的理由。
    /// 沒有它，舊 binary 會看到空的 `entries/` 而回報「0 entries」：一個看起來成功的
    /// 錯誤答案。
    func testMigratedStoreIsRefusedByOlderBinary() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        _ = try StoreMigration.toEntities(store: store)
        // 模擬只支援 format 1 的 binary
        XCTAssertThrowsError(try {
            let found = try StoreVersion.read(root: root)
            guard found <= 1 else {
                throw StoreVersionError.tooNew(found: found, supported: 1)
            }
        }())
    }
}
