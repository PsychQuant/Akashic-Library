import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564 b40 Z1 第 4／7／17 列：`update-person --fields --dry-run` 只預演了 #631 前置、ended 閘與名字分類閘，實跑另有兩類拒絕乾跑看不到——
/// encode 的寫出上限（#648）與 `assertPersonWritable` 其餘的 format 閘。兩席都用真 binary 在 scratch store 重現（乾跑 `wouldChange`、實跑被拒）。
/// 乾跑現在走 `writePerson` 的同一條前置（`LibraryStore.preflightWrite(_:contentGate:)`）：內容閘以 `blockedBy*` 回報，其後的照擲。
/// 走真 binary：9 MiB 的 `--fields` 放不進 argv，只能從 stdin 給，而那一段是 CLI 自己的。
final class UpdatePersonDryRunPreflightCLITests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-564-b41-cli-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try store.writePerson(Person(key: "pz", names: PersonNames(authorized: ["Zhou, P."], variant: [])))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func entityBytes() throws -> [Data] {
        let dir = root.appendingPathComponent("entities")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            .map { try Data(contentsOf: dir.appendingPathComponent($0)) }
    }

    /// 9 MiB 的 note：寫出會超過讀取上限（8 MiB），實跑拒絕。乾跑先前回 `{"dryRun":true,"wouldChange":["note"]}`、rc 0；現在同樣拒絕、零寫入。
    func testANineMebibyteNoteIsRefusedByTheDryRunLikeTheRealRun() throws {
        let json = try JSONSerialization.data(withJSONObject: ["note": String(repeating: "x", count: 9 * 1024 * 1024)])
        let before = try entityBytes()
        for dryRun in [true, false] {
            let r = try CLITestHarness.run(["update-person", "--key", "pz", "--library", root.path] + (dryRun ? ["--dry-run"] : []),
                                           env: ["AKASHIC_HOME": home.path], stdin: json)
            XCTAssertNotEqual(r.status, 0, "dryRun=\(dryRun)：\(r.output.prefix(2_000))")
            XCTAssertTrue(r.output.contains("\(AliasEventBudget.maxBytes)"), "說出上限（dryRun=\(dryRun)）：\(r.output.prefix(2_000))")
            XCTAssertFalse(r.output.contains("wouldChange"), "dryRun=\(dryRun)：\(r.output.prefix(2_000))")
        }
        XCTAssertEqual(try entityBytes(), before, "零寫入")
    }

    /// format 9 的 store、一筆有巢狀 names 的 person：改 note 的實跑被「含巢狀 names，需要 store format ≥ 10」拒絕。乾跑先前只回 wouldChange，
    /// 現在照既有的形以 `blockedByFormatGate` 說實跑會被拒（內容閘在乾跑不擲出）。
    func testAFormatGateTheDryRunDidNotRehearseIsNowReported() throws {
        try StoreVersion.write(root: root, format: 9)
        let dry = try CLITestHarness.run(["update-person", "--key", "pz", "--library", root.path, "--fields", #"{"note":"x"}"#, "--dry-run"],
                                         env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        let p = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(dry.output.utf8)) as? [String: Any], dry.output)
        let blocked = try XCTUnwrap(p["blockedByFormatGate"] as? String, dry.output)
        XCTAssertTrue(blocked.hasPrefix("real run 會被拒：") && blocked.contains("≥ 10"), blocked)
        let real = try CLITestHarness.run(["update-person", "--key", "pz", "--library", root.path, "--fields", #"{"note":"x"}"#],
                                          env: ["AKASHIC_HOME": home.path])
        XCTAssertNotEqual(real.status, 0, real.output)
        XCTAssertTrue(real.output.contains("≥ 10"), real.output)
    }
}
