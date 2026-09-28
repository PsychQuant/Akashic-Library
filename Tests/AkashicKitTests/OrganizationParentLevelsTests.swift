import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport

/// #667：`load.sql` 對任意深度的機構鏈都要載得進 DuckDB。
///
/// #92 把 organization 拆成「骨架 INSERT ＋ 回填 UPDATE」兩步，但回填是**一句** UPDATE。
/// 三層鏈（c→b→a）時同一句同時設 b→a 與 c→b，DuckDB 報外鍵錯誤、整份腳本中止——live store
/// 的 `data-science-statistical-cooperation-center → institute-of-statistical-science →
/// academia-sinica` 就是這個形狀。現在回填逐層、由上而下，層數由匯出端從同一次匯出的
/// organization 表算好；腳本尾端的檢查句對沒回填到的列（成環、或層數不符）中止。
final class OrganizationParentLevelsTests: XCTestCase {

    private func org(_ key: String, parent: String? = nil) -> Organization {
        var o = Organization(key: key, names: TimelineOf([TemporalValue(value: key.uppercased())]))
        if let parent { o.parents = TimelineOf([TemporalValue(value: .key(parent))]) }
        return o
    }

    /// a ← b ← c ← d，另有 a ← e：最深的是 d，第 3 層。
    private var chain: [Organization] {
        [org("a"), org("b", parent: "a"), org("c", parent: "b"), org("d", parent: "c"), org("e", parent: "a")]
    }

    func testLevelsCountTheDeepestChain() {
        let t = RelationalExport.tables(entries: [], people: [], organizations: chain).organization
        XCTAssertEqual(RelationalExport.organizationParentLevels(t), 3)
    }

    func testNoParentsIsZeroLevels() {
        let t = RelationalExport.tables(entries: [], people: [], organizations: [org("a"), org("b")]).organization
        XCTAssertEqual(RelationalExport.organizationParentLevels(t), 0)
    }

    /// 成環的列到不了根，不計入層數——檢查句會對它們出聲，這裡不替它們決定層數。
    func testACycleIsNotCounted() {
        let t = RelationalExport.tables(entries: [], people: [],
                                        organizations: [org("x", parent: "y"), org("y", parent: "x"),
                                                        org("r"), org("s", parent: "r")]).organization
        XCTAssertEqual(RelationalExport.organizationParentLevels(t), 1)
    }

    /// 一層一句、由上而下，且不再有那一句「從 CSV 一次回填全部」的 UPDATE。
    func testScriptBackfillsOneLevelPerStatementTopDown() throws {
        let sql = RelationalExport.duckDBScript(csvDirectory: "/tmp/x", organizationParentLevels: 3)
        let positions = try (1...3).map { k in
            try XCTUnwrap(sql.range(of: "l.level = \(k);"), "第 \(k) 層要有自己的一句").lowerBound
        }
        XCTAssertEqual(positions, positions.sorted(), "由上而下：第 1 層先填")
        XCTAssertNil(sql.range(of: "l.level = 4;"), "層數是多少就幾句")
        XCTAssertFalse(sql.contains("UPDATE organization SET parent_id = c.parent_id"),
                       "#667 之前那一句會對三層鏈中止")
        XCTAssertTrue(sql.contains("SELECT error("), "沒回填到的列要中止，不留安靜的 NULL")
    }

    func testZeroLevelsEmitsNoUpdateButKeepsTheCheck() {
        let sql = RelationalExport.duckDBScript(csvDirectory: "/tmp/x", organizationParentLevels: 0)
        XCTAssertFalse(sql.contains("UPDATE organization"))
        XCTAssertTrue(sql.contains("SELECT error("))
    }

    // MARK: - 真的交給 duckdb 跑（本機有 duckdb CLI 才跑；CI 的端對端步驟是權威）

    private func duckdb() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        for d in dirs {
            let u = URL(fileURLWithPath: d).appendingPathComponent("duckdb")
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        throw XCTSkip("找不到 duckdb CLI——端對端由 ci.yml 的 load.sql 步驟負責")
    }

    /// 寫出同一次匯出的 CSV 與 load.sql，交給 duckdb 跑；回傳 (exit code, stderr, parent 對照)。
    private func load(_ orgs: [Organization], levels: Int? = nil) throws -> (Int32, String, [String: String]) {
        let bin = try duckdb()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-667-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tables = RelationalExport.tables(entries: [], people: [], organizations: orgs)
        for t in tables.all {
            try RelationalExport.csv(t).write(to: dir.appendingPathComponent("\(t.name).csv"), atomically: true, encoding: .utf8)
        }
        let n = levels ?? RelationalExport.organizationParentLevels(tables.organization)
        let script = dir.appendingPathComponent("load.sql")
        try RelationalExport.duckDBScript(csvDirectory: dir.path, organizationParentLevels: n)
            .write(to: script, atomically: true, encoding: .utf8)
        let db = dir.appendingPathComponent("x.db").path
        func run(_ args: [String]) throws -> (Int32, String, String) {
            let p = Process()
            p.executableURL = bin
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
        }
        let (rc, _, stderr) = try run([db, "-c", ".read \(script.path)"])
        guard rc == 0 else { return (rc, stderr, [:]) }
        let (_, csv, _) = try run([db, "-csv", "-noheader", "-c",
                                   "SELECT c.org_key, p.org_key FROM organization c JOIN organization p ON c.parent_id = p.organization_id"])
        var parentOf: [String: String] = [:]
        for line in csv.split(separator: "\n") {
            let f = line.split(separator: ",").map(String.init)
            if f.count == 2 { parentOf[f[0]] = f[1] }
        }
        return (rc, stderr, parentOf)
    }

    func testAFourLevelChainLoadsWithEveryParentBackfilled() throws {
        let (rc, stderr, parentOf) = try load(chain)
        XCTAssertEqual(rc, 0, stderr)
        XCTAssertEqual(parentOf, ["b": "a", "c": "b", "d": "c", "e": "a"])
    }

    /// 負控：層數給少了（1 層＝#667 之前能正確處理的深度），檢查句要中止並說出幾筆沒回填。
    func testTooFewLevelsAbortsLoudly() throws {
        let (rc, stderr, _) = try load(chain, levels: 1)
        XCTAssertNotEqual(rc, 0)
        XCTAssertTrue(stderr.contains("2 筆的上級機構沒有回填"), stderr)   // c、d
    }
}
