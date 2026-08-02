import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// 形狀由**裸標籤**標示，不由某個後設欄位的值標示。
///
/// 缺陷重現：改動前，`type:` 的判別是 `t == "person" ? .person : .work`——一個全稱後備，
/// 讓任何字串都成為 work。實測一個 `type: view` / `title: 中研院的人` 的檔案通過
/// `akashic validate` 並被 doctor 計為一篇著作。封閉集合（work / person）在序列化到
/// YAML 的那一步被這個 `? :` 悄悄變回開放集合。
final class EntityShapeLabelTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-label-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeEntity(_ yaml: String, id: UUID = UUID()) throws -> String {
        let name = "\(id.uuidString).yaml"
        try yaml.write(to: root.appendingPathComponent("entities").appendingPathComponent(name),
                       atomically: true, encoding: .utf8)
        return "entities/\(name)"
    }

    // MARK: - E2 的五種情況

    /// 恰好一個已知標籤 → 用它決定 decoder。
    func testSingleKnownLabelSelectsShape() throws {
        let id = UUID()
        _ = try writeEntity("""
            work:
            id: \(id.uuidString)
            citekey: chen2020
            type: article
            title: T
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.entries.first?.type, "article", "書目類型不得被標籤取代")
    }

    /// person 標籤同樣有效，且**不需要** `type: person`。
    func testPersonLabelWithoutTypeField() throws {
        let id = UUID()
        _ = try writeEntity("""
            person:
            id: \(id.uuidString)
            key: chen-che
            names:
            - 鄭澈
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.people.count, 1)
        XCTAssertEqual(load.people.first?.key, "chen-che")
    }

    /// **本 change 的核心案例**：#54 的實測檔——沒有形狀標籤。
    /// 改動前它通過 validate 並被算成一篇著作；改動後必須 quarantine。
    func testIssue54ViewFileIsQuarantined() throws {
        let id = UUID()
        let file = try writeEntity("""
            id: \(id.uuidString)
            citekey: view-sinica-people
            type: view
            title: 中研院的人
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.count, 0, "形式概念不得被計為著作")
        XCTAssertEqual(load.quarantined.count, 1)
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertEqual(q.file, file)
        XCTAssertTrue(q.reason.contains("形狀標籤"), "理由須指名缺的是形狀標籤：\(q.reason)")
    }

    /// 不認得的標籤 → **具名**錯誤，且指出它該放哪。
    /// 只說「不認得」等於只證明它在這個位置沒有意義；讀者還需要知道哪裡有意義。
    func testUnknownLabelIsNamedAndRedirected() throws {
        let id = UUID()
        _ = try writeEntity("""
            view:
            id: \(id.uuidString)
            key: iss
            """, id: id)
        let load = try LibraryStore(root: root).load()
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertTrue(q.reason.contains("view"), "理由須指名該標籤：\(q.reason)")
        XCTAssertTrue(q.reason.contains("config.yaml"),
                      "理由須指出它該放哪：\(q.reason)")
    }

    /// 標籤帶值 → quarantine。允許帶值等於重新造出一個後設欄位，只是名字換成形狀名。
    func testLabelWithValueIsRejected() throws {
        let id = UUID()
        _ = try writeEntity("""
            person: true
            id: \(id.uuidString)
            key: chen-che
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.people.count, 0)
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertTrue(q.reason.contains("不得帶值"), "\(q.reason)")
    }

    /// 多個互不從屬的已知標籤 → quarantine，不猜。
    func testMultipleUnrelatedLabelsAreRejected() throws {
        let id = UUID()
        _ = try writeEntity("""
            work:
            person:
            id: \(id.uuidString)
            key: chen-che
            """, id: id)
        let load = try LibraryStore(root: root).load()
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertTrue(q.reason.contains("互不從屬") || q.reason.contains("多個"), "\(q.reason)")
    }

    // MARK: - `type:` 收窄為書目類型

    /// 標籤與 `type:` 指向不同形狀 → quarantine，不得挑一邊。
    func testLabelContradictsTypeField() throws {
        let id = UUID()
        _ = try writeEntity("""
            work:
            id: \(id.uuidString)
            citekey: x2020
            type: person
            title: T
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.count, 0)
        let q = try XCTUnwrap(load.quarantined.first)
        XCTAssertTrue(q.reason.contains("矛盾"), "\(q.reason)")
    }

    /// 未見過的書目類型仍正常載入——值域是開放的，不引入白名單。
    func testUnfamiliarBibliographicTypeStillLoads() throws {
        let id = UUID()
        _ = try writeEntity("""
            work:
            id: \(id.uuidString)
            citekey: d2026
            type: dataset
            title: T
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.entries.first?.type, "dataset")
    }

    /// legacy `type: person` 與 person 標籤並存 → 載入為 person，且重新編碼時該欄位消失。
    func testRedundantTypeFieldIsDroppedOnReencode() throws {
        let id = UUID()
        _ = try writeEntity("""
            person:
            id: \(id.uuidString)
            type: person
            key: chen-che
            names:
            - 鄭澈
            """, id: id)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        let p = try XCTUnwrap(load.people.first)
        let out = try PersonYAML.encode(p)
        XCTAssertFalse(out.contains("type:"), "冗餘的形狀名不得被寫回：\n\(out)")
        XCTAssertTrue(out.hasPrefix("person:\n"), "應以裸標籤開頭：\n\(out)")
    }

    // MARK: - 整批載入的韌性

    /// 單一無法判別的檔案不中斷整批載入。
    func testOneUnclassifiableFileDoesNotStopTheLoad() throws {
        let good = UUID(), bad = UUID()
        _ = try writeEntity("""
            work:
            id: \(good.uuidString)
            citekey: ok2020
            type: article
            title: T
            """, id: good)
        _ = try writeEntity("""
            id: \(bad.uuidString)
            citekey: bad
            type: view
            title: X
            """, id: bad)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.count, 1, "好檔仍須載入")
        XCTAssertEqual(load.quarantined.count, 1)
    }

    // MARK: - 往返穩定性（design E1 的前置）

    /// 裸標籤在專案自己的編碼路徑上往返逐字穩定。
    /// 標籤若在往返中變形（`person:` → `person: null`），逐位元穩定性就守不住。
    func testBareLabelRoundTripsVerbatim() throws {
        let p = Person(key: "chen-che", names: ["鄭澈"], id: UUID())
        let once = try PersonYAML.encode(p)
        let back = try PersonYAML.decode(once)
        let twice = try PersonYAML.encode(back)
        XCTAssertEqual(once, twice, "往返不穩定")
        XCTAssertTrue(once.hasPrefix("person:\n"), "標籤形式應為裸鍵：\n\(once)")

        let e = Entry(id: UUID(), citekey: "x2020", type: "article", title: "T",
                      authors: [.literal("A")], date: "2020")
        let eo = try EntryYAML.encode(e)
        XCTAssertEqual(eo, try EntryYAML.encode(try EntryYAML.decode(eo)))
        XCTAssertTrue(eo.hasPrefix("work:\n"), "標籤形式應為裸鍵：\n\(eo)")
    }
}

/// format 2 → 3 的補標籤遷移。
final class ShapeLabelMigrationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-labelmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: 2)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 寫一個「format 2 樣式」的檔：沒有形狀標籤，person 帶 legacy `type: person`。
    private func writeLegacyStyle(work: Bool, id: UUID = UUID()) throws -> URL {
        let u = root.appendingPathComponent("entities")
            .appendingPathComponent("\(id.uuidString).yaml")
        let body = work ? """
            id: \(id.uuidString)
            citekey: ck\(abs(id.hashValue % 100000))
            type: article
            title: T
            """ : """
            id: \(id.uuidString)
            type: person
            key: p\(abs(id.hashValue % 100000))
            """
        try body.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    /// format 2 的 store 仍可載入（回退模式）——否則 migrate 連讀都讀不到。
    func testFormat2StoreStillLoadsWithoutLabels() throws {
        _ = try writeLegacyStyle(work: true)
        _ = try writeLegacyStyle(work: false)
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.people.count, 1)
    }

    /// 遷移後每筆都有標籤，且 format 變 3。
    func testMigrationAddsLabelsAndBumpsFormat() throws {
        let w = try writeLegacyStyle(work: true)
        let p = try writeLegacyStyle(work: false)
        let r = try StoreMigration.toShapeLabels(store: store)
        XCTAssertEqual(r.labelled, 2)
        XCTAssertEqual(try StoreVersion.read(root: root), StoreVersion.supported)
        XCTAssertTrue(try String(contentsOf: w, encoding: .utf8).hasPrefix("work:\n"))
        let ptext = try String(contentsOf: p, encoding: .utf8)
        XCTAssertTrue(ptext.hasPrefix("person:\n"))
        XCTAssertFalse(ptext.contains("type:"), "冗餘的形狀名須在改寫時消失：\n\(ptext)")
        // 遷移後以嚴格模式載入仍然乾淨
        XCTAssertEqual(try store.load().quarantined.count, 0)
    }

    /// 中斷後重跑是冪等的，且不重複已完成的工作。
    func testMigrationIsIdempotentAfterInterruption() throws {
        _ = try writeLegacyStyle(work: true)
        _ = try writeLegacyStyle(work: true)
        // 模擬中斷：第一次跑完寫檔但 format 還沒 bump
        let first = try StoreMigration.toShapeLabels(store: store)
        XCTAssertEqual(first.labelled, 2)
        try StoreVersion.write(root: root, format: 2)   // 倒回「檔已寫、format 未 bump」
        let second = try StoreMigration.toShapeLabels(store: store)
        XCTAssertEqual(second.labelled, 0, "已完成的不得重做")
        XCTAssertEqual(second.alreadyLabelled, 2)
        XCTAssertEqual(try StoreVersion.read(root: root), StoreVersion.supported)
        XCTAssertEqual(try store.load().entries.count, 2, "無記錄遺失")
    }

    /// 已是 format 3 → 拒絕重跑，明說而不是靜默成功。
    func testMigrationRefusesWhenAlreadyAtCurrentFormat() throws {
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertThrowsError(try StoreMigration.toShapeLabels(store: store))
    }

    /// refuse-if-newer：比本 binary 新的 store 回報升級要求，
    /// 而不是產生與真正原因無關的 per-file 錯誤。
    /// **刻意不寫死版本號**——每次 bump 都要改測試的話，測的就變成數字而不是行為。
    func testOlderBinaryRefusesNewerStore() throws {
        let newer = StoreVersion.supported + 1
        try StoreVersion.write(root: root, format: newer)
        XCTAssertThrowsError(try store.load()) { err in
            guard case StoreVersionError.tooNew(let found, let supported) = err else {
                return XCTFail("應為 tooNew，實得 \(err)")
            }
            XCTAssertEqual(found, newer)
            XCTAssertEqual(supported, StoreVersion.supported)
            let msg = (err as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("升級"), "訊息須指向升級而非個別檔案：\(msg)")
        }
    }
}
