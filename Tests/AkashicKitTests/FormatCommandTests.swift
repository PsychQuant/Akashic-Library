import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #69：`akashic fmt` — 讓 encoder 以外的寫入者有一個對齊 canonical form 的入口。
///
/// **測試打在 `CanonicalFormat.scan` 而非 CLI 進入點**：命令本身是 thin wrapper，
/// 沿用 `AuthorizeNames` → `AuthorizedNameMigration.run` 的既有形狀（邏輯住 library、
/// 命令住 executable），因為 executable target 的符號測試 target 匯入不到。
/// 用臨時 store 而非注入假 home——意圖是「不碰真 store」，直接給 root 更短且更明確。
final class FormatCommandTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-fmt-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 寫一筆 canonical 記錄（經 encoder，依定義即 canonical）。
    @discardableResult
    private func writeCanonicalPerson(_ key: String) throws -> URL {
        var p = Person(key: key, names: ["N"], authorized: ["N"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "助研究員", range: DateRange(start: "2003", end: "2013")),
            TemporalValue(value: "研究員", range: DateRange(start: "2013")),
        ])
        return try store.writePerson(p)
    }

    /// 寫一筆**非** canonical 的記錄：手刻 YAML，affiliations 反時間序。
    /// 這是外部 pipeline 真實會產生的形狀——寫入者按自己的迴圈順序寫，不按時間。
    @discardableResult
    private func writeDeviatingPerson(_ key: String) throws -> URL {
        let id = UUID()
        let yaml = """
        person:
        id: \(id.uuidString)
        key: \(key)
        names:
        - N
        authorized:
        - N
        profile:
          affiliations:
          - value:
              literal: ISS
            start: 2013-07
          - value:
              literal: ISS
            start: 2003-01
            end: 2006-08
        """ + "\n"
        let url = store.entityURL(id: id)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func snapshot(_ dir: URL) throws -> [String: (Data, Date)] {
        var out: [String: (Data, Date)] = [:]
        for u in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where u.pathExtension == "yaml" {
            let attrs = try FileManager.default.attributesOfItem(atPath: u.path)
            out[u.lastPathComponent] = (try Data(contentsOf: u),
                                        attrs[.modificationDate] as? Date ?? .distantPast)
        }
        return out
    }

    // MARK: - --check

    func testCheckReportsDeviationAndExitsNonZero() throws {
        try writeCanonicalPerson("clean-one")
        let deviating = try writeDeviatingPerson("dirty-one")
        let r = try CanonicalFormat.scan(store: store, apply: false)
        XCTAssertEqual(r.deviating, [deviating.lastPathComponent],
                       "必須指名偏離的檔案；\(r)")
        XCTAssertTrue(r.rewritten.isEmpty, "--check 不得改寫任何檔案")
        XCTAssertTrue(r.hasProblems, "有偏離時必須非零退出")
    }

    /// design **失敗模式** 的「`--check` 不得開啟任何檔案的寫入控制代碼」。
    /// 比對位元組**與 mtime**——只比位元組會漏掉「寫回同樣內容」那種假無害的實作。
    func testCheckDoesNotModifyFiles() throws {
        try writeCanonicalPerson("clean-one")
        try writeDeviatingPerson("dirty-one")
        let before = try snapshot(store.entitiesDir)
        _ = try CanonicalFormat.scan(store: store, apply: false)
        let after = try snapshot(store.entitiesDir)
        XCTAssertEqual(before.keys.sorted(), after.keys.sorted())
        for (name, b) in before {
            XCTAssertEqual(b.0, after[name]?.0, "\(name) 的位元組被動過")
            XCTAssertEqual(b.1, after[name]?.1, "\(name) 的 mtime 被動過——有人開了寫入控制代碼")
        }
    }

    func testCheckOnCleanStoreExitsZero() throws {
        try writeCanonicalPerson("clean-one")
        try writeCanonicalPerson("clean-two")
        let r = try CanonicalFormat.scan(store: store, apply: false)
        XCTAssertTrue(r.deviating.isEmpty, "encoder 寫出來的記錄依定義即 canonical：\(r)")
        XCTAssertEqual(r.hasProblems, false)
    }

    // MARK: - 實際改寫

    func testApplyRewritesOnlyDeviatingRecords() throws {
        let clean = try writeCanonicalPerson("clean-one")
        let dirty = try writeDeviatingPerson("dirty-one")
        let cleanBefore = try Data(contentsOf: clean)

        let r = try CanonicalFormat.scan(store: store, apply: true)
        XCTAssertEqual(r.rewritten, [dirty.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: clean), cleanBefore,
                       "已經 canonical 的檔案不得被碰——那會產生假 diff")

        // 改寫後必須是不動點
        let second = try CanonicalFormat.scan(store: store, apply: true)
        XCTAssertTrue(second.rewritten.isEmpty, "第二次跑必須無事可做（冪等）")
    }

    // MARK: - 壞檔不中止整輪

    /// design **失敗模式** 的前兩條：單筆讀不進來時列出檔名與原因、繼續處理其餘、
    /// 退出碼非零，且**壞檔的位元組未變**。
    ///
    /// 中止整輪的代價不對稱：一個壞檔會讓其餘幾百筆的正規化全部做不成，而使用者
    /// 拿到的訊息只有第一個錯誤。
    func testUndecodableRecordDoesNotAbortRun() throws {
        try writeCanonicalPerson("clean-one")
        try writeDeviatingPerson("dirty-one")
        let broken = store.entitiesDir
            .appendingPathComponent("\(UUID().uuidString).yaml")
        let brokenBytes = Data("person:\nid: not-a-uuid\nkey: [unclosed\n".utf8)
        try brokenBytes.write(to: broken)

        let r = try CanonicalFormat.scan(store: store, apply: true)
        XCTAssertEqual(r.failures.map(\.file), [broken.lastPathComponent],
                       "必須指名壞掉的檔案：\(r)")
        XCTAssertFalse(try XCTUnwrap(r.failures.first).reason.isEmpty,
                       "必須說出為什麼壞——只說「有一個檔壞了」無法行動")
        XCTAssertEqual(r.rewritten.count, 1, "其餘記錄仍要被處理完")
        XCTAssertEqual(try Data(contentsOf: broken), brokenBytes,
                       "讀不進來的檔案不得被改寫")
        XCTAssertTrue(r.hasProblems, "有失敗時必須非零退出")
    }
}
