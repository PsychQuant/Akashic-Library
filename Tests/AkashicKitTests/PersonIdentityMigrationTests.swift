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
        XCTAssertEqual(person.orcid?.normalized, "0000-0001-2345-6789", "其餘欄位原樣保留")
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

    /// S2／R2 C4：工作樹「乾淨」對被 **ignore** 的檔是空話——porcelain 不列 ignored、
    /// 目錄級「有 tracked 檔」也不構成**特定**檔案的回復保證。判準是 **per-file**：
    /// 只有自己被 git 追蹤的檔才可改寫，未追蹤的計入 failed 點名、已追蹤的照常遷移。
    func testPartiallyTrackedStoreMigratesTrackedAndFailsIgnoredPerFile() throws {
        let trackedURL = try writeOldShapePerson(key: "tracked-p", names: ["Tracked P"])
        GitFixture.initRepo(root)
        GitFixture.commitAll(root, message: "tracked seed")
        // 之後才建的檔、被 file-specific gitignore 排除——porcelain 全程乾淨
        let ignoredURL = try writeOldShapePerson(key: "ghost-p", names: ["Ghost P"])
        try "entities/\(ignoredURL.lastPathComponent)\n.gitignore\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true, encoding: .utf8)
        let ignoredBytes = try Data(contentsOf: ignoredURL)

        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["tracked-p"], "\(report.failed)")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].file.contains(ignoredURL.lastPathComponent))
        XCTAssertTrue(report.failed[0].reason.contains("追蹤"),
                      "未追蹤檔要點名原因：\(report.failed)")
        XCTAssertEqual(try Data(contentsOf: ignoredURL), ignoredBytes,
                       "git 看不見的檔一個位元組都不得動")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trackedURL.path),
                       "已追蹤的檔照常遷移（舊檔已刪）")
    }

    // MARK: - R2 blocking（C1/C2/C3——Codex 抓到的收斂與順序缺口）

    /// C1a：**巢狀+v5 id** 的中斷殘留（decodable 分支）同樣要收斂——不得發第三個 id。
    func testNestedV5ResidueWithExistingV4TwinConverges() throws {
        let v4ID = UUID()
        try """
        person:
        id: \(v4ID.uuidString)
        key: liang-yu-jen
        names:
          variant:
          - Liang, Yu-Jen
        """.write(to: root.appendingPathComponent("entities/\(v4ID.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        let v5ID = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace,
                                        name: "liang-yu-jen")
        try """
        person:
        id: \(v5ID.uuidString)
        key: liang-yu-jen
        names:
          variant:
          - Liang, Yu-Jen
        """.write(to: root.appendingPathComponent("entities/\(v5ID.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty, "巢狀 v5 殘留不得再發 id：\(report.migrated)")
        XCTAssertEqual(report.skipped, ["liang-yu-jen"])
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].file.contains(v5ID.uuidString), "\(report.failed)")
        XCTAssertTrue(report.failed[0].reason.contains("重複"), "\(report.failed)")
        XCTAssertEqual(try entityFiles().count, 2, "兩檔保持原狀")
    }

    /// C1b：兩個 v4 檔同 key——不得被 Set 吞成雙雙 skipped，必須報重複交給人。
    func testTwoV4FilesSameKeyReportedAsDuplicateNotDoubleSkipped() throws {
        for _ in 0..<2 {
            let id = UUID()
            try """
            person:
            id: \(id.uuidString)
            key: chen-wei
            names:
              variant:
              - Chen Wei
            """.write(to: root.appendingPathComponent("entities/\(id.uuidString).yaml"),
                      atomically: true, encoding: .utf8)
        }
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.skipped.isEmpty, "重複不得偽裝成 skipped：\(report.skipped)")
        XCTAssertEqual(report.failed.count, 2, "兩檔都要點名：\(report.failed)")
        XCTAssertTrue(report.failed.allSatisfy { $0.reason.contains("chen-wei") })
        XCTAssertEqual(try entityFiles().count, 2, "不自動刪任何一個")
    }

    /// C2：v4-skip 也要先過 validate——巢狀+v4 但驗證失敗的記錄不得謊稱「已是新形狀」。
    func testV4RecordWithValidationErrorIsFailedNotSkipped() throws {
        let id = UUID()
        try """
        person:
        id: \(id.uuidString)
        key: dup-script
        names:
          authorized:
          - Alpha One
          - Beta Two
          variant:
          - 甲乙
        """.write(to: root.appendingPathComponent("entities/\(id.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        commitAll()
        let before = try Data(contentsOf:
            root.appendingPathComponent("entities/\(id.uuidString).yaml"))
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.skipped.isEmpty, "\(report.skipped)")
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.failed[0].reason.contains("latn"), "\(report.failed)")
        XCTAssertEqual(try Data(contentsOf:
            root.appendingPathComponent("entities/\(id.uuidString).yaml")), before,
            "非本遷移的形狀問題——檔案不動，交給人修")
    }

    /// C3：**巢狀 names + 缺 id**——補 id 必須先於摺疊嘗試（先摺會對巢狀塊誤擲
    /// 「非 canonical」，補 id 程式碼不可達）。
    func testNestedNamesMissingIDGetsBackfilled() throws {
        let fname = UUID().uuidString
        try """
        person:
        key: half-migrated
        names:
          variant:
          - Half Migrated
        """.write(to: root.appendingPathComponent("entities/\(fname).yaml"),
                  atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertEqual(report.migrated, ["half-migrated"], "\(report.failed)")
        XCTAssertTrue(report.failed.isEmpty)
        let load = try store.load()
        XCTAssertEqual(load.people.map(\.key), ["half-migrated"])
        XCTAssertTrue(load.quarantined.isEmpty)
    }

    // MARK: - R3 verify（Codex NEW-1/4/5——盲區裁決、列舉誠實、keeper 交叉點名）

    /// R3 NEW-1a：解不開但**取得到 key** 的檔要參與裁決——同 key 的可讀檔不得
    /// 被當 singleton 重發 id。
    func testUnparsableFileWithExtractableKeyBlocksItsKeyGroup() throws {
        // 可讀的巢狀 v5 檔（本來會 reissue）
        let v5 = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace,
                                      name: "same-key")
        try """
        person:
        id: \(v5.uuidString)
        key: same-key
        names:
          variant:
          - Same Key
        """.write(to: root.appendingPathComponent("entities/\(v5.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        // 同 key、帶引號 flow style（fold 拒收 → 解不開，但 key 取得到）
        let bad = UUID()
        try "person:\nid: \(bad.uuidString)\nkey: same-key\nnames: [\"Quoted, Same\"]\n".write(
            to: root.appendingPathComponent("entities/\(bad.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty,
                      "隱藏重複無法排除——不得對 same-key 重發：\(report.migrated)")
        XCTAssertTrue(report.failed.contains { $0.file.contains(v5.uuidString)
                        && $0.reason.contains("無法解讀") },
                      "可讀檔要點名同 key 的盲區檔：\(report.failed)")
        XCTAssertEqual(try entityFiles().count, 2, "兩檔原狀")
    }

    /// R3 NEW-1b：連 key 都取不到的 person 形檔 → 保守抑制**全部**重發。
    func testKeylessUnparsableFileSuppressesAllReissues() throws {
        try writeOldShapePerson(key: "innocent-p", names: ["Innocent P"])
        let bad = UUID()
        try "person:\nid: \(bad.uuidString)\nnames: 不是清單\n".write(
            to: root.appendingPathComponent("entities/\(bad.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty,
                      "盲區在——任何重發都可能撞隱藏 key：\(report.migrated)")
        XCTAssertTrue(report.failed.contains { $0.reason.contains("取不到 key") },
                      "\(report.failed)")
    }

    /// R4 NEW-R4-1：key 擷取採**保守文法**——引號形／行內註解／重複 key: 行一律
    /// 視同取不到 key → 全域抑制。「引號包著的同 key」不得被誤判成不同 key 而繞過
    /// 同 key 裁決（Codex R4 的 HIGH 繞法）。
    func testNonCanonicalKeyInUnparsableFileTriggersGlobalSuppression() throws {
        // 可讀的巢狀 v5 檔（本來會 reissue）
        let v5 = DeterministicUUID.v5(namespace: DeterministicUUID.personNamespace,
                                      name: "same-key")
        try """
        person:
        id: \(v5.uuidString)
        key: same-key
        names:
          variant:
          - Same Key
        """.write(to: root.appendingPathComponent("entities/\(v5.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        // 同 key 但引號形 + 損壞 names——解不開，且 key 文法非 canonical → keyless
        let bad = UUID()
        try "person:\nid: \(bad.uuidString)\nkey: \"same-key\"\nnames: [故意損壞\n".write(
            to: root.appendingPathComponent("entities/\(bad.uuidString).yaml"),
            atomically: true, encoding: .utf8)
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.migrated.isEmpty,
                      "引號形 key 的盲區檔必須觸發全域抑制：\(report.migrated)")
        XCTAssertEqual(try entityFiles().count, 2, "兩檔原狀")

        // 文法單元：引號／註解／CRLF／重複行
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key: \"x\"\n"))
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key: x # c\n"))
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key: a\nkey: b\n"))
        XCTAssertEqual(PersonIdentityMigration.extractTopLevelKey("key: some-key\r\n"),
                       "some-key", "CRLF 行尾要剝")
        // R5 NEW-R5-1：空 RHS／tab 分隔的 `key:` 行也要入歧義偵測——decoy 不得存活
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key: decoy\nkey:\n"))
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key: decoy\nkey:\t\"same-key\"\n"))
        XCTAssertNil(PersonIdentityMigration.extractTopLevelKey("key:\n"), "單獨空 RHS 也是非 canonical")
    }

    /// R3 NEW-4：目錄不存在＝合法空 store；不得偽裝成功也不得炸。
    func testMissingPeopleDirIsLegitimatelyEmpty() throws {
        let r = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idmig-nodir-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: r) }
        try FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
        try StoreVersion.write(root: r, format: 1)   // legacy、無 people/
        let report = try PersonIdentityMigration.run(store: LibraryStore(root: r))
        XCTAssertTrue(report.migrated.isEmpty && report.skipped.isEmpty && report.failed.isEmpty)
        XCTAssertTrue(report.legacyLayout)
    }

    /// R3 NEW-5：唯一 v4 keeper 自己驗證失敗時，reason 也要交叉點名同 key 其他檔。
    func testInvalidKeeperCrossReferencesItsDuplicates() throws {
        let v4 = UUID()
        try """
        person:
        id: \(v4.uuidString)
        key: dup-k
        names:
          authorized:
          - Alpha One
          - Beta Two
        """.write(to: root.appendingPathComponent("entities/\(v4.uuidString).yaml"),
                  atomically: true, encoding: .utf8)
        try writeOldShapePerson(key: "dup-k", names: ["Dup K"])
        commitAll()
        let report = try PersonIdentityMigration.run(store: store, apply: true)
        XCTAssertTrue(report.skipped.isEmpty)
        let keeperEntry = report.failed.first { $0.file.contains(v4.uuidString) }
        XCTAssertNotNil(keeperEntry)
        XCTAssertTrue(keeperEntry!.reason.contains("驗證失敗")
                        && keeperEntry!.reason.contains("同 key"),
                      "keeper 要同時說驗證失敗與交叉點名：\(keeperEntry!.reason)")
    }

    /// R3 NEW-3：下一步指示的唯一成功判準是「apply 且零失敗」——全 skipped 的重跑
    /// 與空 store 同樣要有出口；有 failed 一律禁升；legacy 先指路 akashic migrate。
    func testNextStepCoversAllBranches() {
        var r = PersonIdentityMigration.Report()
        XCTAssertNil(PersonIdentityMigration.nextStep(report: r, apply: false), "dry-run 無指示")
        // 空 store／全 skipped：仍要有出口
        XCTAssertTrue(PersonIdentityMigration.nextStep(report: r, apply: true)!
            .contains("format: 改成 10"))
        r.skipped = ["a"]
        XCTAssertTrue(PersonIdentityMigration.nextStep(report: r, apply: true)!
            .contains("format: 改成 10"), "全 skipped 的重跑也要有下一步")
        // 有 failed：禁升
        r.failed = [(file: "x", reason: "y")]
        XCTAssertTrue(PersonIdentityMigration.nextStep(report: r, apply: true)!
            .contains("不得"), "有失敗必須明說禁升 marker")
        // legacy：先 migrate
        r.failed = []; r.legacyLayout = true
        let legacy = PersonIdentityMigration.nextStep(report: r, apply: true)!
        XCTAssertTrue(legacy.contains("akashic migrate"), "\(legacy)")
    }

    /// C5 的 report 面：legacy 佈局要在 Report 上可辨（CLI 據此分流下一步指示）。
    func testReportMarksLegacyLayout() throws {
        let legacyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idmig-ll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: legacyRoot) }
        try FileManager.default.createDirectory(
            at: legacyRoot.appendingPathComponent("people"), withIntermediateDirectories: true)
        try StoreVersion.write(root: legacyRoot, format: 1)
        let r1 = try PersonIdentityMigration.run(store: LibraryStore(root: legacyRoot))
        XCTAssertTrue(r1.legacyLayout)
        XCTAssertFalse(try PersonIdentityMigration.run(store: store).legacyLayout)
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
