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
