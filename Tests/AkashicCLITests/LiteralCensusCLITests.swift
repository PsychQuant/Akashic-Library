import XCTest
import Foundation

/// `akashic literal-census`（#629）的 CLI 面：真 binary，沙箱紀律同其他 CLI 測試（`--library` 指 scratch、
/// `AKASHIC_HOME` 指 scratch、`HOME` 指 scratch——路徑縮寫要看得到 `~`）。計數與版面的細節在
/// `LiteralCensusTests`（AkashicKitTests）；這裡只驗**命令接得起來**：exit code、stdout／stderr 的分工、唯讀。
final class LiteralCensusCLITests: XCTestCase {
    private var base: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-census-cli-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func makeStore(marker: String?) throws -> URL {
        let root = home.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try "work:\nid: 11111111-1111-1111-1111-111111111111\ncitekey: t\ntype: periodical-article\ntitle: t\nauthors:\n- key: p\n- literal: A\nvenues:\n- literal: V\n"
            .write(to: root.appendingPathComponent("entities/x.yaml"), atomically: true, encoding: .utf8)
        if let marker { try marker.write(to: root.appendingPathComponent("store.yaml"), atomically: true, encoding: .utf8) }
        return root
    }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": home.appendingPathComponent(".akashic-home").path, "HOME": home.path])
    }

    /// 印出四域、路徑縮成 `~`（輸出會貼進 issue，不印使用者名）、exit 0。
    func testPrintsFourDomainsWithTheHomePrefixShrunkToTilde() throws {
        let root = try makeStore(marker: "format: 12\n")
        let r = try run(["literal-census", "--library", root.path])
        XCTAssertEqual(r.status, 0, r.output)
        let lines = r.output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "store: ~/store（format 12）", r.output)
        for (i, name) in ["author", "venue", "affiliation", "org-parents"].enumerated() {
            XCTAssertTrue(lines[i + 1].hasPrefix(name), lines[i + 1])
        }
        XCTAssertTrue(lines[1].contains("總邊     2｜literal 邊 1（佔 50.0%）｜key 1｜distinct literal 1"), lines[1])
        XCTAssertFalse(r.output.contains(home.path), "輸出不得含 HOME 的完整路徑（會貼進 issue）")
    }

    /// 讀端會整體拒開的 store 照樣印計數，並掛全域警告——警告是報告的一部分，exit 仍是 0。
    func testTooNewStorePrintsCountsWithAWarningAndStillExitsZero() throws {
        let root = try makeStore(marker: "format: 99999\n")
        let r = try run(["literal-census", "--library", root.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("**超過你的 binary 支援上限"), r.output)
        XCTAssertTrue(r.output.contains("⚠ 讀端會整體拒開此 store"), r.output)
        XCTAssertTrue(r.output.contains("author"), "拒開的 store 仍要印計數")
    }

    /// `entities/`、`entries/`、`people/` 皆缺：exit 2，訊息在 stderr。
    func testNotAStoreExitsTwo() throws {
        let empty = home.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let r = try run(["literal-census", "--library", empty.path])
        XCTAssertEqual(r.status, 2, r.output)
        XCTAssertTrue(r.output.contains("不是 Akashic store"), r.output)
    }

    /// 唯讀：跑完之後 store 底下沒有多任何檔、marker 沒被動（普查不得為了報告去「修」一個壞的 marker）。
    func testDoesNotWriteAnythingIntoTheStore() throws {
        let root = try makeStore(marker: "garbage\n")
        func snapshot() throws -> [String: Data] {
            var out: [String: Data] = [:]
            for case let p as String in FileManager.default.enumerator(atPath: root.path)! {
                var d: ObjCBool = false
                if FileManager.default.fileExists(atPath: root.appendingPathComponent(p).path, isDirectory: &d), !d.boolValue {
                    out[p] = try Data(contentsOf: root.appendingPathComponent(p))
                }
            }
            return out
        }
        let before = try snapshot()
        let r = try run(["literal-census", "--library", root.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("marker 不合 grammar"), r.output)
        XCTAssertEqual(try snapshot(), before)
    }
}
