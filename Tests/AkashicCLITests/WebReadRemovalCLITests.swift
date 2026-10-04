import XCTest
import Foundation

/// `akashic web-read landing`／`check` 只刪一般檔或 symlink（#692 b33 verify X2 第 0／1 列，真 binary）。
///
/// R4 把文件裡的 `check-read.py` 移成 Swift 時，`os.remove`（遇到目錄失敗、不刪）換成了 `FileManager.removeItem`——對目錄**整棵遞迴刪除**，
/// 而且在讀任何輸入之前就刪：`landing --out <目錄>` 把目錄換成一個一般檔、`check --raw <目錄>` 在 READ-FAIL 之後照樣把目錄刪掉、
/// `landing --out .` 刪掉目前目錄。現在：參數先驗，目錄與其他型態具名拒絕（結束碼 1）、**什麼都不刪**；symlink 刪的是連結本身。
final class WebReadRemovalCLITests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("webread-rm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try "https://journal.example.org\n".write(to: url("o.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func url(_ name: String) -> URL { base.appendingPathComponent(name) }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": url("home").path])
    }

    /// 一個裝著 sentinel 的目錄（含一層子目錄：遞迴刪除才會碰到它）。
    private func sentinelDir(_ name: String) throws -> URL {
        let dir = url(name)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "keep\n".write(to: dir.appendingPathComponent("sub/sentinel"), atomically: true, encoding: .utf8)
        return dir
    }

    private func assertIntact(_ dir: URL, file: StaticString = #filePath, line: UInt = #line) {
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue, "目錄要還在、還是目錄", file: file, line: line)
        XCTAssertEqual(try? String(contentsOf: dir.appendingPathComponent("sub/sentinel"), encoding: .utf8), "keep\n", "sentinel 要還在", file: file, line: line)
    }

    private var checkCommon: [String] {
        ["--limit", "100", "--landing", "-", "--before", url("o.txt").path, "--after", url("o.txt").path]
    }

    func testLandingOutPointingAtADirectoryDeletesNothing() throws {
        let dir = try sentinelDir("land-dir")
        let r = try cli(["web-read", "landing", "--origin", url("o.txt").path, "--out", dir.path, "--expect", "-"])
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("LANDING-FAIL") && r.output.contains("是目錄") && r.output.contains("什麼都沒刪"), r.output)
        assertIntact(dir)
    }

    func testCheckOutPointingAtADirectoryDeletesNothingNotEvenTheRawFile() throws {
        let dir = try sentinelDir("out-dir")
        let raw = url("raw.json")
        try #"{"truncated": false, "rawLength": 1, "text": "t"}"#.write(to: raw, atomically: true, encoding: .utf8)
        let r = try cli(["web-read", "check", "--raw", raw.path, "--out", dir.path] + checkCommon)
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("READ-FAIL --out") && r.output.contains("是目錄"), r.output)
        assertIntact(dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path), "參數不合時什麼都不刪（與命令列打錯的 64 同一邊）")
    }

    func testCheckRawPointingAtADirectoryDeletesNothing() throws {
        let dir = try sentinelDir("raw-dir")
        try "OLD".write(to: url("out.txt"), atomically: true, encoding: .utf8)
        let r = try cli(["web-read", "check", "--raw", dir.path, "--out", url("out.txt").path] + checkCommon)
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("READ-FAIL --raw") && r.output.contains("是目錄"), r.output)
        assertIntact(dir)
        XCTAssertEqual(try String(contentsOf: url("out.txt"), encoding: .utf8), "OLD", "參數不合時連 --out 都不刪")
    }

    /// `landing --out .`（b33 verify：先前刪掉目前目錄整個）。
    func testLandingOutDotDeletesNothing() throws {
        let dir = try sentinelDir("cwd")
        let p = Process()
        p.executableURL = CLITestHarness.productsDirectory.appendingPathComponent("akashic")
        p.arguments = ["web-read", "landing", "--origin", url("o.txt").path, "--out", ".", "--expect", "-"]
        p.currentDirectoryURL = dir
        p.environment = ["AKASHIC_HOME": url("home").path, "PATH": "/usr/bin:/bin"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 1)
        assertIntact(dir)
    }

    /// symlink：刪的是連結本身，它指向的檔不動（`os.remove` 的語意）；通過時寫回的是一般檔。
    func testASymlinkOutIsUnlinkedNotItsTarget() throws {
        let target = url("target.txt")
        try "precious\n".write(to: target, atomically: true, encoding: .utf8)
        let link = url("land.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let r = try cli(["web-read", "landing", "--origin", url("o.txt").path, "--out", link.path, "--expect", "-"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "precious\n", "symlink 指向的檔不得被改或刪")
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "寫回的是一般檔")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "https://journal.example.org\n")
    }
}
