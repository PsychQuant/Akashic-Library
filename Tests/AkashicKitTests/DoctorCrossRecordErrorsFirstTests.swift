import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #709 R2 verify（regression 席，真 binary）：同一筆記錄的 legacy 拷貝降為 warning 之後，每一對先造出兩則 warning（UUID 共用、
/// citekey 重複），`crossRecordIssues()` 按產生順序吐，而 MCP `akashic_doctor` 只送前 20 則——一個真的 error（兩筆**不同**的記錄共用
/// citekey）排在第 25 位時，`first` 裡全是 warning、而 `indexRebuilt:false` 的 note 指向一個看不到的 error。
/// 修法：`StoreHealth.crossRecordIssues` 是穩定的 error 先分割（單一來源，三個面讀同一份順序）。
final class DoctorCrossRecordErrorsFirstTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    /// 12 對 leftover（24 則 warning 先於任何 error）＋ 兩筆不同的記錄共用 citekey（1 則 error）。
    private func seed() throws {
        for i in 0..<12 {
            let e = Entry(id: UUID(), citekey: "pair\(i)work", type: .periodicalArticle, title: "Pair \(i)", date: "2020")
            try writeEntities(e)
            try writeLegacy(e)
        }
        try writeEntities(Entry(id: UUID(), citekey: "zzz2020dup", type: .periodicalArticle, title: "Dup A", date: "2020"))
        try writeEntities(Entry(id: UUID(), citekey: "zzz2020dup", type: .periodicalArticle, title: "Dup B", date: "2020"))
    }

    func testTheHealthListPutsErrorsBeforeWarningsAndKeepsTheOrderInsideEachGroup() throws {
        try seed()
        let load = try store.load()
        let generated = load.crossRecordIssues()
        XCTAssertGreaterThan(generated.count, 20, "前提：warning 多到把 error 擠出前 20 則")
        let firstErrorInGenerationOrder = try XCTUnwrap(generated.firstIndex { $0.severity == .error })
        XCTAssertGreaterThanOrEqual(firstErrorInGenerationOrder, 20, "前提：產生順序下 error 在 20 則之後——否則這個測試什麼都沒證")

        let health = store.health(from: load)
        let severities = health.crossRecordIssues.map(\.severity)
        let errorCount = severities.filter { $0 == .error }.count
        XCTAssertGreaterThan(errorCount, 0)
        XCTAssertEqual(Array(severities.prefix(errorCount)), Array(repeating: .error, count: errorCount), "error 全在最前面")
        XCTAssertEqual(health.crossRecordIssues.count, generated.count, "只重排、不增減")
        XCTAssertEqual(health.crossRecordIssues.filter { $0.severity != .error }.map(\.message),
                       generated.filter { $0.severity != .error }.map(\.message), "warning 之間保持原順序（穩定分割）")
        XCTAssertEqual(health.fatalCrossRecordIssues.map(\.message), health.crossRecordIssues.prefix(errorCount).map(\.message))
    }

    /// MCP 面：`first` 取前 20 則，`indexRebuilt:false` 指向的 error 必須在裡面。
    func testDoctorFirstTwentyContainsTheErrorThatBlocksTheRebuild() throws {
        try seed()
        let service = AkashicService(root: root, key: nil, environment: [:])
        let doctor = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try service.doctor().utf8)) as? [String: Any])
        XCTAssertEqual(doctor["indexRebuilt"] as? Bool, false, "\(doctor)")
        let cross = try XCTUnwrap(doctor["crossRecordIssues"] as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(cross["count"] as? Int), 20)
        let first = try XCTUnwrap(cross["first"] as? [[String: Any]])
        XCTAssertEqual(first.count, 20)
        XCTAssertEqual(first.first?["severity"] as? String, "error", "note 指向的 error 要看得見：\(first.prefix(3))")
        XCTAssertTrue((first.first?["message"] as? String ?? "").contains("zzz2020dup"), "\(String(describing: first.first))")
    }
}
