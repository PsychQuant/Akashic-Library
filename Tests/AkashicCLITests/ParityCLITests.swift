import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import akashic

/// #250：`add-person`／`divergences` 兩個新 CLI 面。走真 binary（經
/// `CLITestHarness`，理由見 PersonCLITests 檔頭——不開第 N 份 runCLI）。
///
/// 與 MCP 面共用 `AkashicService` 同一函式，service 層語意（已存在拒絕、
/// quarantine 保護、列表欄位）由 `ServiceTests` 覆蓋；本檔只驗 CLI 面自己的
/// 責任：參數形狀、`--json`／人可讀同源、空集合要說出來。
final class ParityCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-parity-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writePerson(Person(key: "che-cheng", names: ["Cheng, Che"]))
        try store.writePerson(Person(key: "cheng-chen", names: ["Chen, Cheng"]))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    // MARK: - add-person

    func testAddPersonCreatesRecord() throws {
        let r = try cli(["add-person", "chen-chun-houh", "--name", "Chen, Chun-Houh",
                         "--name", "陳君厚"])
        XCTAssertEqual(r.status, 0, r.output)
        let people = try LibraryStore(root: root).load().people
        let p = people.first { $0.key == "chen-chun-houh" }
        XCTAssertNotNil(p, "add-person 之後記錄要在 store 裡")
        XCTAssertEqual(p?.names, ["Chen, Chun-Houh", "陳君厚"])
    }

    func testAddPersonRefusesExistingKey() throws {
        let r = try cli(["add-person", "che-cheng", "--name", "X"])
        XCTAssertNotEqual(r.status, 0, "key 已存在必須拒絕（create 語意，與 MCP 面同一個 service 判準）")
    }

    // MARK: - divergences

    func testDivergencesEmptySetIsStatedNotOmitted() throws {
        let r = try cli(["divergences"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("沒有未決"),
                      "「零筆未決」是結果不是缺席——空輸出分辨不出「沒歧異」與「這段掉了」：\n\(r.output)")
    }

    func testDivergencesListsRecordedQuestion() throws {
        let store = LibraryStore(root: root)
        _ = try store.recordDivergence(
            question: "Cheng, C. 是不是 che-cheng？",
            candidates: [(key: "che-cheng", shape: .person),
                         (key: "cheng-chen", shape: .person)],
            judgement: nil, restsOn: [], prefers: nil)
        let r = try cli(["divergences"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("che-cheng"), r.output)
        XCTAssertTrue(r.output.contains("Cheng, C. 是不是"), r.output)
    }

    func testDivergencesJSONAgreesWithHumanOnCount() throws {
        let store = LibraryStore(root: root)
        _ = try store.recordDivergence(
            question: "q1", candidates: [(key: "che-cheng", shape: .person),
                                         (key: "cheng-chen", shape: .person)],
            judgement: nil, restsOn: [], prefers: nil)
        let j = try cli(["divergences", "--json"])
        XCTAssertEqual(j.status, 0, j.output)
        let obj = try JSONSerialization.jsonObject(
            with: Data(j.output.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["count"] as? Int, 1, "--json 是 service 回應原樣轉印")
        let h = try cli(["divergences"])
        XCTAssertTrue(h.output.contains("divergence（1）"),
                      "人可讀與 --json 的計數要同源：\n\(h.output)")
    }
}
