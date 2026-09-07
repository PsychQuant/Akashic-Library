import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #450：拆分後錨失效的兩種 warning——(1) 某 person／organization 持有的 resolution verdict，其
/// literal 已被某 work 的拆分記錄退役（**以 (citekey, literal) 為鍵**，不只比 literal）；(2) 一筆拆分
/// 記錄的各段全部不在作者位。兩種都是 warning、記錄仍載入（#464／#453 的 perRecordIssues 形）。
final class OrphanedSplitVerdictScanTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-osv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(_ field: String, _ value: String) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value,
                            kind: .judgement(statement: "resolve \(field)：unit test", restsOn: []))
    }
    private func person(_ key: String, _ refs: [ProvenanceReference]) throws {
        var p = Person(key: key, names: [key.uppercased()])
        p.references = refs
        try store.writePerson(p)
    }
    private func work(_ citekey: String, authors: [Author], split: (retired: String, parts: [String])? = nil) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T", authors: authors)
        if let s = split {
            let v = try XCTUnwrap(SplitRecordValue(parts: s.parts, reason: "兩位作者被匯出黏成一格"))
            e.references = [ProvenanceReference(field: "authors", value: s.retired,
                                                kind: .judgement(statement: v.encoded, restsOn: []))]
        }
        try store.writeEntry(e)
    }

    /// spec「Rejected literal later split」。
    func testRejectedLiteralLaterSplitIsAnOrphan() throws {
        try person("p-one", [verdict("resolution-rejected", "work:chen2020a :: 某人與雷庚玲")])
        try work("chen2020a", authors: [.literal("某人"), .literal("雷庚玲")],
                 split: ("某人與雷庚玲", ["某人", "雷庚玲"]))
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "\(load.quarantined)")
        let issues = store.orphanedSplitVerdictIssues(in: load)
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.issue.message))")
        XCTAssertEqual(issues.first?.owner, "p-one")
        XCTAssertEqual(issues.first?.kind, "person")
        XCTAssertEqual(issues.first?.issue.severity, .warning)
        let msg = issues.first?.issue.message ?? ""
        XCTAssertTrue(msg.hasPrefix(StoreHealth.orphanedSplitVerdictPrefix), msg)
        XCTAssertTrue(msg.contains("chen2020a") && msg.contains("某人與雷庚玲"), "要指名那筆 work 與 literal：\(msg)")
    }

    /// spec「Same literal on a different work is not an orphan」：以 (citekey, literal) 為鍵。
    func testSameLiteralOnDifferentWorkIsNotAnOrphan() throws {
        try person("p-one", [verdict("resolution-rejected", "work:other2021 :: 某人與雷庚玲")])
        try work("other2021", authors: [.literal("某人與雷庚玲")])
        try work("chen2020a", authors: [.literal("某人"), .literal("雷庚玲")],
                 split: ("某人與雷庚玲", ["某人", "雷庚玲"]))
        let load = try store.load()
        XCTAssertTrue(store.orphanedSplitVerdictIssues(in: load).isEmpty)
    }

    /// spec「Clean store reports nothing」。
    func testCleanStoreReportsNothing() throws {
        try person("p-one", [verdict("resolution-confirmed", "work:chen2020a :: 某人")])
        try work("chen2020a", authors: [.key("p-one"), .literal("雷庚玲")])
        let load = try store.load()
        XCTAssertTrue(store.orphanedSplitVerdictIssues(in: load).isEmpty)
        XCTAssertTrue(store.health(from: load).orphanedSplitVerdicts.isEmpty)
        XCTAssertTrue(store.health(from: load).staleSplitRecords.isEmpty)
    }

    /// spec「All parts gone is a warning, not a rejection」：記錄仍載入，health 報一筆 warning 指名 work 與 literal。
    func testAllPartsGoneIsAWarningNotARejection() throws {
        try work("chen2020a", authors: [.literal("王五")], split: ("某人與雷庚玲", ["某人", "雷庚玲"]))
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 0, "各段全不在不是 decode 期的拒收：\(load.quarantined)")
        let health = store.health(from: load)
        XCTAssertTrue(health.orphanedSplitVerdicts.isEmpty, "沒有 verdict 就沒有孤兒 verdict")
        XCTAssertEqual(health.staleSplitRecords.count, 1, "\(health.perRecordIssues.map(\.issue.message))")
        let w = try XCTUnwrap(health.staleSplitRecords.first)
        XCTAssertEqual(w.owner, "chen2020a"); XCTAssertEqual(w.kind, "entry")
        XCTAssertEqual(w.issue.severity, .warning)
        XCTAssertTrue(w.issue.message.hasPrefix(StoreHealth.staleSplitRecordPrefix), w.issue.message)
        XCTAssertTrue(w.issue.message.contains("某人與雷庚玲"), w.issue.message)
    }

    /// design：「至少一段仍在」含已升格的 `.key` 對應的 confirmed literal——升格不是消失。
    func testPartPresentViaConfirmedKeyIsNotStale() throws {
        try person("p-one", [verdict("resolution-confirmed", "work:chen2020a :: 某人")])
        try work("chen2020a", authors: [.key("p-one"), .literal("王五")],
                 split: ("某人與雷庚玲", ["某人", "雷庚玲"]))
        let load = try store.load()
        XCTAssertTrue(store.health(from: load).staleSplitRecords.isEmpty,
                      "「某人」已升格為 p-one（confirmed verdict 在），那一段仍在")
    }

    /// health 真的呼叫掃描——拿掉 `health(from:)` 裡的 append 這裡就紅。
    func testHealthActuallyCallsTheScan() throws {
        try person("p-one", [verdict("resolution-rejected", "work:chen2020a :: 某人與雷庚玲")])
        try work("chen2020a", authors: [.literal("王五")], split: ("某人與雷庚玲", ["某人", "雷庚玲"]))
        let load = try store.load()
        let health = store.health(from: load)
        XCTAssertEqual(health.orphanedSplitVerdicts.count, 1, "\(health.perRecordIssues.map(\.issue.message))")
        XCTAssertEqual(health.staleSplitRecords.count, 1)
        XCTAssertEqual(store.orphanedSplitVerdictIssues(in: load).count, 2, "直接呼叫與 health 同數")
        XCTAssertTrue(health.perRecordIssues.allSatisfy { $0.issue.severity == .warning }, "兩種都是 warning，validate 的 exit 仍 0")
    }

    /// 兩個消費面都要提到計數（#453 的同一形：計算屬性落在 `StoreHealthSurfaceTests` 反射的視野外）。
    func testBothFacesMentionOrphanedSplitVerdicts() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"),
                                 encoding: .utf8)
        let cli = try String(contentsOf: repo.appendingPathComponent("Sources/akashic/Commands.swift"),
                             encoding: .utf8)
        guard let start = service.range(of: "public func doctor() throws -> String {") else {
            return XCTFail("找不到 doctor()——本測試的前提不成立")
        }
        let doctorBody = String(service[start.lowerBound...].prefix(8000))
        XCTAssertTrue(doctorBody.contains("health.orphanedSplitVerdicts"), "MCP doctor() 沒有消費 orphanedSplitVerdicts")
        XCTAssertTrue(doctorBody.contains("health.staleSplitRecords"), "MCP doctor() 沒有消費 staleSplitRecords")
        XCTAssertTrue(cli.contains("health.orphanedSplitVerdicts"), "CLI validate 沒有消費 orphanedSplitVerdicts")
        XCTAssertTrue(cli.contains("health.staleSplitRecords"), "CLI validate 沒有消費 staleSplitRecords")
    }
}
