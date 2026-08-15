import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #241／#227：person 身分重發 + names 巢狀化的一次性遷移。
///
/// 五條契約（spec `record-identity` 的 Identifier reassignment / recovery path）：
/// dry-run 零寫入、檔名與 id 遷移後一致（不一致會進 quarantine——首要風險）、
/// 髒工作樹拒寫、重跑安全、單筆失敗不中止整批且 report 點名。
final class PersonIdentityMigrationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        // 真 store 的處境：format 5（v10 之前）、entities 佈局、git 版控
        try StoreVersion.write(root: root, format: 5)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 舊形狀 person 檔（真 store 869 筆的形狀）：v5 id、平坦 names + 兄弟 authorized。
    @discardableResult
    private func writeOldShapePerson(key: String, names: [String],
                                     authorized: [String] = [],
                                     extra: String = "") throws -> URL {
        let id = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: key)
        var text = "person:\nid: \(id.uuidString)\nkey: \(key)\n"
        if !names.isEmpty {
            text += "names:\n" + names.map { "- \($0)\n" }.joined()
        }
        if !authorized.isEmpty {
            text += "authorized:\n" + authorized.map { "- \($0)\n" }.joined()
        }
        text += extra
        let url = root.appendingPathComponent("entities/\(id.uuidString).yaml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func commitAll() {
        GitFixture.initRepo(root)
        GitFixture.commitAll(root, message: "seed")
    }

    private func entityFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("entities").path))
    }

    // MARK: - (1) dry-run 零寫入

    func testDryRunWritesNothing() throws {
        let url = try writeOldShapePerson(key: "guan-yongtao",
                                          names: ["Guan, Yongtao"],
                                          authorized: ["Guan, Yongtao"])
        commitAll()
        let before = try Data(contentsOf: url)
        let filesBefore = try entityFiles()

        let report = try PersonIdentityMigration.run(store: store, apply: false)
        XCTAssertEqual(report.migrated, ["guan-yongtao"], "dry-run 要報告將要遷移的記錄")
        XCTAssertEqual(try Data(contentsOf: url), before, "沒給寫入指示就不能動任何檔")
        XCTAssertEqual(try entityFiles(), filesBefore, "不得新增或刪除任何檔案")
    }

    // MARK: - (2) 檔名與 id 遷移後一致（否則整批 quarantine）

    func testFilenameAndIDAgreeAfterMigration() throws {
        let oldURL = try writeOldShapePerson(
            key: "liang-yu-jen",
            names: ["梁佑任", "Liang, Yu-Jen", "Yu-Jen Liang"],
            authorized: ["梁佑任", "Yu-Jen Liang"],
            extra: "orcid: 0000-0001-2345-6789\n")
        commitAll()

        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["liang-yu-jen"])
        XCTAssertTrue(report.failed.isEmpty, "\(report.failed)")

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path), "舊檔必須刪除")
        let files = try entityFiles()
        XCTAssertEqual(files.count, 1)
        let newFile = files.first!
        let person = try PersonYAML.decode(String(
            contentsOf: root.appendingPathComponent("entities/\(newFile)"), encoding: .utf8))
        XCTAssertEqual("\(person.id.uuidString).yaml", newFile,
                       "檔名與檔內 id 必須同步改——不同步整批進 quarantine")
        let s = person.id.uuidString
        XCTAssertEqual(s[s.index(s.startIndex, offsetBy: 14)], "4", "新 id 必須是 v4：\(s)")
        // names 摺疊：authorized 分割保序、其餘進 variant
        XCTAssertEqual(person.names.authorized, ["梁佑任", "Yu-Jen Liang"])
        XCTAssertEqual(person.names.variant, ["Liang, Yu-Jen"])
        XCTAssertEqual(person.orcid, "0000-0001-2345-6789", "其餘欄位原樣保留")
        // load 全庫：零 quarantine
        let load = try store.load()
        XCTAssertEqual(load.people.map(\.key), ["liang-yu-jen"])
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
    }

    // MARK: - (3) 髒工作樹拒寫（回復路徑必須有效）

    func testDirtyWorktreeRefusesToWrite() throws {
        let url = try writeOldShapePerson(key: "wang-x", names: ["Wang, X."])
        commitAll()
        try "stray".write(to: root.appendingPathComponent("stray.txt"),
                          atomically: true, encoding: .utf8)   // 未提交變更
        let before = try Data(contentsOf: url)

        XCTAssertThrowsError(try PersonIdentityMigration.run(store: store, apply: true)) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(m.contains("commit") || m.contains("提交"),
                          "訊息要說明先 commit：\(m)")
        }
        XCTAssertEqual(try Data(contentsOf: url), before, "拒絕必須是完全 no-op")
        // dry-run 不受此前置（report-only 沒有要回復的東西）
        XCTAssertNoThrow(try PersonIdentityMigration.run(store: store, apply: false))
    }

    // MARK: - (4) 重跑安全（已是新形狀者計入「跳過」）

    func testRerunIsSafe() throws {
        try writeOldShapePerson(key: "chen-a", names: ["Chen A"])
        try writeOldShapePerson(key: "chen-b", names: ["Chen B"])
        commitAll()

        let first = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(Set(first.migrated), ["chen-a", "chen-b"])
        GitFixture.commitAll(root, message: "after first run")

        let filesAfterFirst = try entityFiles()
        let second = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(second.migrated.isEmpty, "已遷移的記錄不得再動：\(second.migrated)")
        XCTAssertEqual(Set(second.skipped), ["chen-a", "chen-b"],
                       "已是新形狀者計入「跳過」，與「已遷移」分開")
        XCTAssertEqual(try entityFiles(), filesAfterFirst, "第二輪必須是 no-op")
    }

    // MARK: - verify R1 補洞（#227/#241 cluster verify 抓到的遷移可達性族）

    /// F2：legacy 佈局（people/<key>.yaml，format 1）必須有遷移路徑——先前三個指令
    /// 互指成循環。就地摺疊＋補發 id（檔名即 key，不改名）；佈局搬移仍歸 akashic migrate。
    func testLegacyLayoutIsMigratedInPlace() throws {
        let legacyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idmig-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: legacyRoot) }
        try FileManager.default.createDirectory(
            at: legacyRoot.appendingPathComponent("people"), withIntermediateDirectories: true)
        try StoreVersion.write(root: legacyRoot, format: 1)
        // legacy 檔：無形狀標籤、無 id、平坦 names + 兄弟 authorized
        try "key: guan-yongtao\nnames:\n- Guan, Yongtao\nauthorized:\n- Guan, Yongtao\n"
            .write(to: legacyRoot.appendingPathComponent("people/guan-yongtao.yaml"),
                   atomically: true, encoding: .utf8)
        GitFixture.initRepo(legacyRoot)
        GitFixture.commitAll(legacyRoot, message: "seed legacy")
        let legacyStore = LibraryStore(root: legacyRoot)

        let report = try PersonIdentityMigration.run(store: legacyStore, apply: true)
        XCTAssertEqual(report.migrated, ["guan-yongtao"], "\(report.failed)")

        let text = try String(contentsOf:
            legacyRoot.appendingPathComponent("people/guan-yongtao.yaml"), encoding: .utf8)
        let person = try PersonYAML.decode(text)
        XCTAssertEqual(person.names.authorized, ["Guan, Yongtao"], "摺疊完成")
        let s = person.id.uuidString
        XCTAssertEqual(s[s.index(s.startIndex, offsetBy: 14)], "4", "補發的 id 是 v4")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: legacyRoot.appendingPathComponent("people").path), ["guan-yongtao.yaml"],
            "就地覆寫——檔名即 key，不改名、不留舊檔")
    }

    /// F2 自我指涉分支：entities 檔缺 id → 補發（one-time backfill），不再把記錄記成
    /// 「失敗，理由是請跑本工具」。
    func testMissingIDGetsBackfilledNotSelfReferentialFailure() throws {
        let id = UUID()
        try "person:\nkey: no-id-person\nnames:\n- No Id\n".write(
            to: root.appendingPathComponent("entities/\(id.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["no-id-person"], "\(report.failed)")
        XCTAssertTrue(report.failed.isEmpty)
        let load = try store.load()
        XCTAssertEqual(load.people.map(\.key), ["no-id-person"])
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    /// L7：format-2 的 `type: person` 檔（無裸標籤）不得被靜默跳過——先前不進任何
    /// 一欄、CLI 報「沒有 person 記錄」，操作者照指示 bump 後整批 quarantine。
    func testFormatTwoTypePersonFileIsMigratedNotSilentlySkipped() throws {
        let id = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace,
                                      name: "fmt2-person")
        try "type: person\nid: \(id.uuidString)\nkey: fmt2-person\nnames:\n- Fmt Two\n".write(
            to: root.appendingPathComponent("entities/\(id.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["fmt2-person"],
                       "type: person 是 format 2 的合法形狀，不得靜默跳過：\(report.failed)")
    }

    /// NEW-2：flow-style `names: [..]`——簡單純量要能摺；帶引號／巢狀的要**點名**
    /// 「無法辨識的寫法」，不得讓 decoder 的泛用訊息形成「請跑本工具」的循環建議。
    func testFlowStyleNamesFoldsOrFailsWithNamedReason() throws {
        try writeOldShapePersonText(key: "flow-simple",
                                    body: "names: [Flow Simple, Simple Flow]\n")
        try writeOldShapePersonText(key: "flow-quoted",
                                    body: "names: [\"Quoted, Name\"]\n")
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["flow-simple"], "\(report.failed)")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].reason.contains("無法辨識"),
                      "帶引號的 flow style 要點名寫法問題，不是循環建議：\(report.failed)")
        XCTAssertFalse(report.failed[0].reason.contains("migrate-person-identity"),
                       "失敗理由不得叫使用者跑剛失敗的這個工具")
    }

    /// L6：中斷殘留（同 key 新舊檔並存）重跑必須**收斂**——不得發第三個 id，
    /// 舊檔計入 failed 並點名重複。
    func testRerunAfterInterruptionConvergesInsteadOfIssuingThirdID() throws {
        // 模擬中斷：新形檔（v4）與舊形檔（v5）同 key 並存
        let newID = UUID()
        try """
        person:
        id: \(newID.uuidString)
        key: liang-yu-jen
        names:
          variant:
          - Liang, Yu-Jen
        """.write(to: root.appendingPathComponent("entities/\(newID.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        try writeOldShapePerson(key: "liang-yu-jen", names: ["Liang, Yu-Jen"])
        commitAll()

        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty, "不得替殘留舊檔發新 id：\(report.migrated)")
        XCTAssertEqual(report.skipped, ["liang-yu-jen"])
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].reason.contains("重複"),
                      "舊檔要以重複點名交給人：\(report.failed)")
        XCTAssertEqual(try entityFiles().count, 2, "兩檔保持原狀——不自動裁決刪誰")
    }

    /// L8：v4 id + 平坦 names 的半套檔——摺 names 但**保留**既有獨立 id
    /// （spec：already independent → left unchanged）。
    func testHalfMigratedFileKeepsItsV4ID() throws {
        let keepID = UUID()
        try "person:\nid: \(keepID.uuidString)\nkey: half-state\nnames:\n- Half State\n".write(
            to: root.appendingPathComponent("entities/\(keepID.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["half-state"], "\(report.failed)")
        let load = try store.load()
        XCTAssertEqual(load.people.first?.id, keepID, "已是 v4 的 id 不得重發")
    }

    /// L2/S3：遷移不得繞過 validate——同書寫系統兩個 authorized 的舊記錄計入 failed
    /// 並點名，不落盤（「每條寫入路徑都擋」對遷移同樣成立）。
    func testMigrationRoutesValidateErrorsToFailedInsteadOfWriting() throws {
        let url = try writeOldShapePerson(key: "dup-script",
                                          names: ["Alpha One", "Beta Two"],
                                          authorized: ["Alpha One", "Beta Two"])
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty, "\(report.migrated)")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].reason.contains("latn"),
                      "理由要含 validate 的訊息：\(report.failed)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "拒絕的記錄保持原狀（prior state）")
    }

    /// S2：工作樹「乾淨」對被 **ignore** 的內容是空話——`status --porcelain` 不列
    /// ignored 檔（可見的未追蹤檔會以 `??` 被髒樹閘抓，ignored 連 `??` 都沒有），
    /// 兩道舊閘都過而 git 根本救不回。有檔案卻零 git 追蹤時必須拒寫。
    func testIgnoredContentRefusesApply() throws {
        try writeOldShapePerson(key: "wang-x", names: ["Wang, X."])
        GitFixture.initRepo(root)
        try "entities/\nstore.yaml\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true, encoding: .utf8)
        GitFixture.commitAll(root, message: "gitignore only")   // entities 被 ignore → porcelain 乾淨
        XCTAssertThrowsError(try PersonIdentityMigration.run(store: store, apply: true)) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(m.contains("追蹤"), "訊息要說明未被追蹤：\(m)")
        }
    }

    /// helper：自訂 body 的舊形檔。
    @discardableResult
    private func writeOldShapePersonText(key: String, body: String) throws -> URL {
        let id = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace, name: key)
        let text = "person:\nid: \(id.uuidString)\nkey: \(key)\n" + body
        let url = root.appendingPathComponent("entities/\(id.uuidString).yaml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - (5) 單筆失敗不中止整批，report 點名

    func testSingleFailureDoesNotAbortBatch() throws {
        try writeOldShapePerson(key: "ok-one", names: ["Ok One"])
        // 壞檔：names 是 scalar——摺疊不了、現行 decoder 也拒收
        let brokenID = UUID()
        try "person:\nid: \(brokenID.uuidString)\nkey: broken-p\nnames: 不是清單\n".write(
            to: root.appendingPathComponent("entities/\(brokenID.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        try writeOldShapePerson(key: "ok-two", names: ["Ok Two"])
        commitAll()

        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(Set(report.migrated), ["ok-one", "ok-two"],
                       "其餘記錄必須照常處理，不因單筆失敗中止")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].file.contains(brokenID.uuidString),
                      "report 要點名失敗的檔：\(report.failed)")
        XCTAssertFalse(report.failed[0].reason.isEmpty, "以及原因")
    }
}
