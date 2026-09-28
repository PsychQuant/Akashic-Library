import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #648 (b)：resolve-people 的 judge／refute 理由與未決腿的說明同一個上限（`maxStatementBytes`，4,096 位元組）——
/// 超過即整批拒絕、零寫入、不截斷。在此之前全樹的 `utf8.count <=` 上限只在未決腿、org 的兩條腿與 export，一句
/// 8–15 MB 的理由一次就能把一筆沒有任何預警的 person 推過讀取上限（#645 R2 verify DA 的構造）。
final class JudgeReasonCapTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-648b-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        let home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        let store = LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try store.writePerson(Person(key: "chun-houh-chen", names: ["Chen, Chun-houh"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T",
                                   authors: [.literal("Someone Else"), .literal("C-H Chen")], date: "2020"))
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": home.path])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private var cap: Int { AkashicService.maxStatementBytes }

    private func snapshot() throws -> (authors: [Author], verdicts: Int) {
        let load = try LibraryStore(root: root, key: nil, environment: [:]).load()
        let e = try XCTUnwrap(load.entries.first { $0.citekey == "w1" })
        let p = try XCTUnwrap(load.people.first { $0.key == "chun-houh-chen" })
        return (e.authors, p.references.count)
    }

    func testCapIsTheUndecidedLegsConstant() {
        XCTAssertEqual(cap, 4_096)
    }

    func testJudgeReasonAtTheCapIsAccepted() throws {
        let json = try service.resolvePeople(apply: nil, judge: ["w1:1:chun-houh-chen=\(String(repeating: "r", count: cap))"])
        XCTAssertTrue(json.contains("\"judged\""), json)
        XCTAssertEqual(try snapshot().authors[1], .key("chun-houh-chen"))
    }

    func testJudgeReasonOverTheCapIsRefusedWithZeroWrites() throws {
        let before = try snapshot()
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, judge: ["w1:1:chun-houh-chen=\(String(repeating: "r", count: cap + 1))"])) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("w1:1:chun-houh-chen"), "要指名是哪一筆：\(message)")
            XCTAssertTrue(message.contains("\(self.cap + 1)") && message.contains("\(self.cap)"), "兩個數都要說：\(message)")
        }
        let after = try snapshot()
        XCTAssertEqual(after.authors, before.authors)
        XCTAssertEqual(after.verdicts, before.verdicts)
    }

    /// 位元組不是字元：1,366 個「查」是 4,098 位元組。
    func testTheCapCountsBytesNotCharacters() throws {
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, judge: ["w1:1:chun-houh-chen=\(String(repeating: "查", count: 1_366))"]))
        XCTAssertNoThrow(try service.resolvePeople(apply: nil, judge: ["w1:1:chun-houh-chen=\(String(repeating: "查", count: 1_365))"]))
    }

    func testRefuteReasonOverTheCapIsRefusedWithZeroWrites() throws {
        let before = try snapshot()
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, refute: ["w1:1:chun-houh-chen=\(String(repeating: "r", count: cap + 1))"]))
        XCTAssertEqual(try snapshot().verdicts, before.verdicts)
    }

    /// 整批：合法的一筆排在前面也不得落地。
    func testOneOversizedReasonRejectsTheWholeBatch() throws {
        let before = try snapshot()
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, judge: [
            "w1:1:chun-houh-chen=合法的理由",
            "w1:0:chun-houh-chen=\(String(repeating: "r", count: cap + 1))",
        ]))
        XCTAssertEqual(try snapshot().authors, before.authors)
    }

    /// 在任何 store 狀態分支之前擋：指向不存在的 work（會被具名略過的那一種）也不得因此回報成功。
    func testOversizedReasonOnASkippableSpecIsStillAnInputError() throws {
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, judge: ["nope:0:chun-houh-chen=\(String(repeating: "r", count: cap + 1))"]))
    }

    /// 兩面的文件都要說出上限（CLI help 與 MCP 描述；源碼掃描，同 `HolderVerdictBudgetWarningTests` 的形）。
    /// 掃的是那一個旗標／參數的字串本體，不是整檔——整檔裡別處的「4,096」會讓拿掉它仍然綠。
    func testBothFacesDocumentTheCap() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (p: String) in try String(contentsOf: repo.appendingPathComponent(p), encoding: .utf8) }
        let server = try read("Sources/akashic-mcp/Server.swift")
        let cli = try read("Sources/akashic/Commands.swift")
        func literal(after marker: String, in text: String) -> String? {
            guard let r = text.range(of: marker) else { return nil }
            let rest = text[r.upperBound...]
            guard let end = rest.range(of: "\")") else { return nil }
            return String(rest[..<end.lowerBound])
        }
        for (marker, text) in [("\"judge\": strArray(\"逐篇判定（#386）", server),
                               ("\"refute\": strArray(\"逐篇**否決**", server),
                               ("help: \"逐篇判定（可重複）：citekey:authorIndex:personKey", cli),
                               ("help: \"判定式否決（可重複）", cli)] {
            let body = try XCTUnwrap(literal(after: marker, in: text), "找不到 \(marker)")
            XCTAssertTrue(body.contains("4,096 位元組") && body.contains("#648"), "\(marker) 沒有說出理由的上限")
        }
    }
}
