import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #31：tolerant-preserve 的可見性——「有本 binary 看不懂的欄位」必須在**讀取面**
/// 就看得到，而不是只有 doctor 才說。
final class UnknownFieldVisibilityTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ufv-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ name: String, _ body: String) throws {
        try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// 檔名清單用**實際檔名**而非以 key 重組（R6 修的迴歸點）——`.YAML` 這類大小寫
    /// 變體若用 key 合成，會報出一個不存在的路徑，使用者照著找找不到。
    func testUnknownFieldFilesUseActualFilenames() throws {
        try write("entries/oddcase.YAML", """
            id: 11111111-1111-1111-1111-111111111111
            citekey: oddcase
            type: article
            title: T
            authors:
              - literal: X
            futureField: v
            """)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.unknownFieldFiles, ["entries/oddcase.YAML"],
                       "必須是實際檔名；以 key 合成會產生不存在的 entries/oddcase.yaml")
    }

    /// 未知欄位**不使檔案 quarantine**——這是 #23 的核心契約，也是可見性面的前提：
    /// 若它被 quarantine，就不存在「正常載入但有保留欄位」這個狀態要顯示。
    func testUnknownFieldsDoNotQuarantine() throws {
        try write("entries/ok.yaml", """
            id: 11111111-1111-1111-1111-111111111111
            citekey: ok
            type: article
            title: T
            authors:
              - literal: X
            futureField: v
            akashic:
              tags: []
              futureNested: n
            """)
        let load = try LibraryStore(root: root).load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertFalse(load.entries[0].unknownFields.isEmpty,
                       "記錄自己要帶著 unknownFields，讀取面才有東西可露")
        XCTAssertEqual(load.unknownFieldFiles, ["entries/ok.yaml"])
    }

    /// quarantined 與 unknown-field 是**語意相反**的兩種狀態，不得合併計數：
    /// 前者「壞了、沒載入」，後者「正常載入且完整保留」。
    func testQuarantinedAndUnknownFieldAreDisjointSignals() throws {
        try write("entries/good.yaml", """
            id: 11111111-1111-1111-1111-111111111111
            citekey: good
            type: article
            title: T
            authors:
              - literal: X
            futureField: v
            """)
        try write("entries/bad.yaml", "這不是合法 YAML: [")
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertEqual(load.unknownFieldFiles, ["entries/good.yaml"])
        XCTAssertFalse(load.unknownFieldFiles.contains { $0.contains("bad") },
                       "壞檔不得混進 unknown-field 清單")
    }

    /// person 與 library 兩層同樣要帶（讀取面三型別一致）。
    func testPersonAndLibraryCarryUnknownFields() throws {
        try write("people/p-one.yaml", """
            key: p-one
            names: [Someone]
            futureAffiliation: ISS
            """)
        try write("libraries/lib.yaml", """
            key: lib
            name: L
            futureFacet: x
            """)
        let load = try LibraryStore(root: root).load()
        XCTAssertFalse(load.people.first?.unknownFields.isEmpty ?? true)
        XCTAssertFalse(load.libraries.first?.unknownFields.isEmpty ?? true)
        XCTAssertEqual(Set(load.unknownFieldFiles),
                       ["people/p-one.yaml", "libraries/lib.yaml"])
    }
}
