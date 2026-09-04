import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// 歧異記錄的**建立入口**（#77）。
///
/// 缺陷重現：#71 讓「未決的同一性問題」成為可記錄的一級事物，`writeDivergence` 與
/// `resolveDivergence` 都在型別層備妥，`akashic resolve-divergence` 也有 CLI 入口——
/// 但**沒有任何方式建立一筆記錄**。於是「先記下來、之後再判斷」在使用層不成立，
/// 實務上只能手寫 YAML 繞過編碼器（位元組形式無保證），或當場做掉判斷而不留痕。
final class DivergenceRecordTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divrec-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func person(_ key: String, _ names: [String]) throws {
        _ = try store.writePerson(Person(key: key, names: PersonNames(
            authorized: [names[0]], variant: Array(names.dropFirst()))))
    }

    // MARK: - id 的推導

    func testDivergenceIDIsDerivedFromCandidatesAndIsOrderIndependent() {
        let a = DeterministicUUID.forDivergence(candidateKeys: ["shieh-grace-s", "shwu-rong-grace-shieh"])
        let b = DeterministicUUID.forDivergence(candidateKeys: ["shwu-rong-grace-shieh", "shieh-grace-s"])
        XCTAssertEqual(a, b, "「這些是不是同一個」不因候選的排列而改變——id 也不該")
        XCTAssertNotEqual(a, DeterministicUUID.forDivergence(candidateKeys: ["x", "y"]))
    }

    // MARK: - 建立

    func testRecordingADivergenceWritesALoadableRecord() throws {
        try person("shieh-grace-s", ["Shieh, Grace S."])
        try person("shwu-rong-grace-shieh", ["謝叔蓉", "Shwu-Rong Grace Shieh"])

        let d = try store.recordDivergence(
            question: "是否為同一人",
            candidates: [("shieh-grace-s", .person), ("shwu-rong-grace-shieh", .person)],
            judgement: "兩者是同一人",
            restsOn: ["sha256:a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"])

        let load = try store.load()
        XCTAssertEqual(load.divergences.count, 1)
        XCTAssertEqual(load.divergences.first?.id, d.id)
        XCTAssertEqual(load.divergences.first?.judgement?.statement, "兩者是同一人")
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
    }

    /// 記錄一個判斷**不等於**做掉它——消歧是一個操作，不是一個欄位（#71）。
    func testRecordingAJudgementDoesNotResolveIt() throws {
        try person("a", ["A One"])
        try person("b", ["B Two"])
        _ = try store.recordDivergence(question: "同一人？",
                                       candidates: [("a", .person), ("b", .person)],
                                       judgement: "是",
                                       restsOn: ["sha256:b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"])
        let load = try store.load()
        XCTAssertEqual(load.people.count, 2, "兩筆都還在——判斷寫下了，合併還沒發生")
        XCTAssertEqual(load.divergences.count, 1)
    }

    func testRecordingIsIdempotent() throws {
        try person("a", ["A One"])
        try person("b", ["B Two"])
        let first = try store.recordDivergence(question: "同一人？",
                                               candidates: [("a", .person), ("b", .person)],
                                               judgement: nil, restsOn: [])
        let again = try store.recordDivergence(question: "同一人？（改寫過的問法）",
                                               candidates: [("b", .person), ("a", .person)],
                                               judgement: "是",
                                               restsOn: ["sha256:b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"])
        XCTAssertEqual(first.id, again.id, "同一組候選＝同一個未決問題，不該累積成兩筆")
        XCTAssertEqual(try store.load().divergences.count, 1)
    }

    // MARK: - 拒絕

    func testCandidatesMustExist() throws {
        try person("a", ["A One"])
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一人？", candidates: [("a", .person), ("no-such", .person)],
            judgement: nil, restsOn: [])) { e in
            XCTAssertTrue("\(e)".contains("no-such"), "訊息要點名缺的那個：\(e)")
        }
    }

    /// 沒有依據的斷言不是判斷（#71 的不變式）。`recordDivergence` 要**早一步**擋，
    /// 而不是留給編碼器——工具的錯誤訊息比 YAML 層的訊息接近使用者的動作。
    func testJudgementRequiresEvidence() throws {
        try person("a", ["A One"])
        try person("b", ["B Two"])
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一人？", candidates: [("a", .person), ("b", .person)],
            judgement: "是", restsOn: [])) { e in
            XCTAssertTrue("\(e)".contains("依據"), "\(e)")
        }
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一人？", candidates: [("a", .person), ("b", .person)],
            judgement: nil, restsOn: ["sha256:c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"]))
    }

    func testAtLeastTwoCandidates() throws {
        try person("a", ["A One"])
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一人？", candidates: [("a", .person)], judgement: nil, restsOn: []))
    }

    /// CLI 入口必須存在——型別層備妥而使用層沒有入口，正是 #77 的內容。
    func testCLIExposesTheEntryPoint() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cli = try String(contentsOf: repoRoot.appendingPathComponent("Sources/akashic/CLI.swift"),
                             encoding: .utf8)
        XCTAssertTrue(cli.contains("RecordDivergence.self"),
                      "resolve-divergence 有入口而 record 沒有，記錄就只能手寫 YAML 繞過編碼器")
    }
}
