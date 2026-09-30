import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）：`authorize-names --apply` 必附理由、每個寫入的名字各留一筆「指定：理由」，
/// 需要 store format ≥ 22，而且**不再替使用者寫 store marker**（先前結尾無條件把 marker 寫成 supported）。
/// 服務層（`AuthorizedNameMigration.run`）；CLI 的用法錯誤與真 binary 見 `AuthorizeNamesJudgementCLITests`。
final class AuthorizeNamesJudgementTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-anj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func people() throws -> [String: Person] {
        Dictionary(uniqueKeysWithValues: try store.load().people.map { ($0.key, $0) })
    }
    private func fileBytes() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        return Dictionary(uniqueKeysWithValues: try names.map { ($0, try Data(contentsOf: dir.appendingPathComponent($0))) })
    }
    private func seedTwoPeople() throws {
        _ = try store.writePerson(Person(key: "guan-yongtao", names: ["Guan, Yongtao"]))
        _ = try store.writePerson(Person(key: "liu-wei-chung", names: ["劉維中", "Wei-chung Liu"]))
    }

    // MARK: - 理由必填

    /// `--apply` 沒有理由：拒絕，而且早於讀 store（對一個根本不存在的 store 也是這句話）。
    func testApplyWithoutAReasonIsRefusedBeforeTheStoreIsRead() throws {
        try seedTwoPeople()
        let before = try fileBytes()
        for reason in [nil, "", "  \n\t"] as [String?] {
            XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: reason), "\(String(describing: reason))") { e in
                XCTAssertTrue("\(e)".contains("--judgement"), "\(e)")
            }
        }
        XCTAssertEqual(try fileBytes(), before, "零寫入")
        let nowhere = LibraryStore(root: root.appendingPathComponent("does-not-exist"))
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: nowhere, apply: true, judgement: nil)) { e in
            XCTAssertTrue("\(e)".contains("--judgement"), "用法錯誤早於開 store：\(e)")
        }
    }

    func testApplyReasonIsBoundedAndNotTruncated() throws {
        try seedTwoPeople()
        let before = try fileBytes()
        let tooLong = String(repeating: "字", count: 1_400)   // 4,200 位元組
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: tooLong)) { e in
            XCTAssertTrue("\(e)".contains("4096") || "\(e)".contains("4,096"), "\(e)")
        }
        XCTAssertEqual(try fileBytes(), before)
    }

    /// 乾跑不需要理由（它不寫）。
    func testDryRunNeedsNoReason() throws {
        try seedTwoPeople()
        let before = try fileBytes()
        let report = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(report.adopted, 3)
        XCTAssertEqual(try fileBytes(), before)
    }

    // MARK: - 記錄的形狀

    /// 每個寫入的 person、每個被採用的名字各一筆，statement 是「指定：整批那一句」、證據空。
    func testApplyWritesOneDesignationRecordPerNamePerPerson() throws {
        try seedTwoPeople()
        let report = try AuthorizedNameMigration.run(store: store, apply: true, judgement: "每人只有一個候選，逐筆看過")
        XCTAssertEqual(report.adopted, 3)
        let loaded = try people()
        XCTAssertEqual(loaded["guan-yongtao"]?.references,
                       [NameClassificationRecord.make(field: "authorized", name: "Guan, Yongtao", action: .designate,
                                                      reason: "每人只有一個候選，逐筆看過", restsOn: [])])
        let liu = try XCTUnwrap(loaded["liu-wei-chung"])
        XCTAssertEqual(Set(liu.names.authorized), ["劉維中", "Wei-chung Liu"])
        XCTAssertEqual(Set(liu.references.compactMap(\.value)), ["劉維中", "Wei-chung Liu"])
        XCTAssertEqual(liu.references.count, 2)
        for r in liu.references {
            XCTAssertEqual(r.field, "authorized")
            guard case .judgement(let statement, let restsOn) = r.kind else { return XCTFail("\(r)") }
            XCTAssertEqual(statement, "指定：每人只有一個候選，逐筆看過")
            XCTAssertEqual(restsOn, [], "整批一句、不帶證據")
        }
        XCTAssertTrue(try store.load().quarantined.isEmpty)
    }

    /// 已經有 authorized 的人不動、也不寫「確認」（本面只對 authorized 為空的人寫入）。
    func testPeopleWhoAlreadyHaveAnAuthorizedNameGetNoRecord() throws {
        _ = try store.writePerson(Person(key: "done-person", names: PersonNames(authorized: ["Done, Person"], variant: [])))
        let before = try fileBytes()
        let report = try AuthorizedNameMigration.run(store: store, apply: true, judgement: "r")
        XCTAssertEqual(report.alreadyDesignated, 1)
        XCTAssertEqual(try fileBytes(), before, "沒有要寫的人：零寫入")
    }

    // MARK: - store format 22 與 marker

    /// format 21：寫入閘擋，而且在任何一筆寫入之前（preflight）——零寫入、marker 不動。
    func testFormat21RefusesAndWritesNothing() throws {
        try seedTwoPeople()
        try StoreVersion.write(root: root, format: 21)
        let before = try fileBytes()
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: "r")) { e in
            let m = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(m.contains("22"), m)
        }
        XCTAssertEqual(try fileBytes(), before, "零寫入")
        XCTAssertEqual(try StoreVersion.read(root: root), 21)
    }

    /// 不再寫 marker：live store 的形狀（全部已有 authorized、marker 18）上 `--apply` 是 no-op，marker 停在 18。
    func testApplyNeverWritesTheMarker() throws {
        _ = try store.writePerson(Person(key: "done-person", names: PersonNames(authorized: ["Done, Person"], variant: [])))
        try StoreVersion.write(root: root, format: 18)
        _ = try AuthorizedNameMigration.run(store: store, apply: true, judgement: "r")
        XCTAssertEqual(try StoreVersion.read(root: root), 18, "升 marker 是使用者的動作（先前 --apply 結尾無條件寫 supported）")

        // 寫得進去的 store（format 22）上有人要寫：寫完 marker 仍是原值
        try StoreVersion.write(root: root, format: 22)
        _ = try store.writePerson(Person(key: "guan-yongtao", names: ["Guan, Yongtao"]))
        _ = try AuthorizedNameMigration.run(store: store, apply: true, judgement: "r")
        XCTAssertEqual(try StoreVersion.read(root: root), 22)
        XCTAssertEqual(try people()["guan-yongtao"]?.names.authorized, ["Guan, Yongtao"])
    }
}
