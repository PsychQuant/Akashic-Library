import XCTest
import Foundation
@testable import AkashicStoreIO

/// #700 b31 W5 MEDIUM 0、1，以真 binary 重現：`ensureLayout` 對讀不懂的 `.gitignore` 先前當成空檔、整份以「只含 sources 區塊」的內容替換——
/// 使用者原有的規則（擋 raw 逐字稿的 `*.srt` 之類）全部消失、沒有任何訊息；symlink 被換成一般檔。`file add`、`doctor` 都經過那裡。
///
/// 現在：讀不懂的不改寫——`file add` 在建立任何東西之前具名拒絕（不寫 registry、不建 store.yaml）；`doctor` 照常建佈局、`.gitignore` 不動、
/// 印一則 warning、結束碼 0。要加區塊時只在尾端附加位元組。每一格都逐位元組比對 `.gitignore`（symlink 則比對它指向的檔，並確認它還是 symlink）。
///
/// scratch：`--config`、`--library` 與 `AKASHIC_HOME` 都指暫存目錄。
final class GitignorePreservationCLITests: XCTestCase {
    private var base: URL!
    private var home: URL!
    private var config: String { home.appendingPathComponent("config.yaml").path }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-gitignore-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        // mode 000 的檔留著也刪得掉（目錄可寫）；保險起見先放開
        if let e = FileManager.default.enumerator(atPath: base.path) {
            for case let p as String in e { chmod(base.appendingPathComponent(p).path, 0o755) }
        }
        try? FileManager.default.removeItem(at: base)
    }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": home.path])
    }

    /// 一個裝著給定 `.gitignore` 位元組的 store 目錄。
    private func storeDir(_ name: String, gitignore: Data) throws -> URL {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try gitignore.write(to: dir.appendingPathComponent(".gitignore"))
        return dir
    }

    private func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    private static let latin1 = Data([0x23, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x0A]) + Data("*.srt\n*.mp3\n**/*_notes.md\n".utf8)
    /// Windows PowerShell 的 `>` 重導向寫出的形狀：UTF-16LE、帶 BOM。
    private static let utf16 = "*.srt\nnode_modules/\n".data(using: .utf16LittleEndian).map { Data([0xFF, 0xFE]) + $0 }!

    /// `file add` 拒絕的共同斷言：非零結束、訊息說出原因與要加的那段、`.gitignore` 位元組不變、registry 沒寫、佈局沒建。
    private func assertFileAddRefused(_ dir: URL, original: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let r = try cli(["file", "add", "k\(abs(dir.lastPathComponent.hashValue % 1000))", dir.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, r.output, file: file, line: line)
        XCTAssertTrue(r.output.contains(".gitignore 沒有改寫") && r.output.contains("# BEGIN akashic sources"), r.output, file: file, line: line)
        XCTAssertEqual(try bytes(dir.appendingPathComponent(".gitignore")), original, "原有內容要逐位元組保留", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.yaml").path), "拒絕時什麼都不建", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config), "拒絕時不寫 registry", file: file, line: line)
    }

    /// `doctor` 的共同斷言：結束碼 0、印 warning、`.gitignore` 位元組不變、佈局照建。
    private func assertDoctorWarns(_ dir: URL, original: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let r = try cli(["doctor", "--library", dir.path])
        XCTAssertEqual(r.status, 0, r.output, file: file, line: line)
        XCTAssertTrue(r.output.contains("⚠ .gitignore 沒有 sources 排除區塊，doctor 沒有改寫它"), r.output, file: file, line: line)
        XCTAssertEqual(try bytes(dir.appendingPathComponent(".gitignore")), original, "原有內容要逐位元組保留", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.yaml").path), "doctor 照常建佈局", file: file, line: line)
    }

    func testLatin1GitignoreIsNeitherRewrittenByFileAddNorByDoctor() throws {
        let a = try storeDir("latin1-add", gitignore: Self.latin1)
        try assertFileAddRefused(a, original: Self.latin1)
        let d = try storeDir("latin1-doctor", gitignore: Self.latin1)
        try assertDoctorWarns(d, original: Self.latin1)
    }

    func testUTF16GitignoreIsNeitherRewrittenByFileAddNorByDoctor() throws {
        let a = try storeDir("utf16-add", gitignore: Self.utf16)
        try assertFileAddRefused(a, original: Self.utf16)
        let d = try storeDir("utf16-doctor", gitignore: Self.utf16)
        try assertDoctorWarns(d, original: Self.utf16)
    }

    func testUnreadableGitignoreIsNeitherRewrittenByFileAddNorByDoctor() throws {
        try XCTSkipIf(geteuid() == 0, "root 讀得到 mode 000 的檔")
        let original = Data("*.srt\n".utf8)
        let a = try storeDir("unreadable-add", gitignore: original)
        chmod(a.appendingPathComponent(".gitignore").path, 0o000)
        let ra = try cli(["file", "add", "unreadable", a.path, "--config", config])
        XCTAssertNotEqual(ra.status, 0, ra.output)
        XCTAssertTrue(ra.output.contains("讀不到"), ra.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("store.yaml").path), "拒絕時什麼都不建")
        let d = try storeDir("unreadable-doctor", gitignore: original)
        chmod(d.appendingPathComponent(".gitignore").path, 0o000)
        let rd = try cli(["doctor", "--library", d.path])
        XCTAssertEqual(rd.status, 0, rd.output)
        XCTAssertTrue(rd.output.contains("讀不到"), rd.output)
        for dir in [a, d] {
            let gi = dir.appendingPathComponent(".gitignore")
            var st = stat()
            XCTAssertEqual(lstat(gi.path, &st), 0)
            XCTAssertEqual(st.st_mode & 0o777, 0, "模式不得被換掉（先前的原子替換建出 0644 的新檔）")
            chmod(gi.path, 0o644)
            XCTAssertEqual(try bytes(gi), original, "原有內容要逐位元組保留")
        }
    }

    func testSymlinkedGitignoreIsNotReplacedByFileAddNorByDoctor() throws {
        let dotfiles = base.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("gitignore")
        let original = Data("node_modules/\n*.srt\n".utf8)
        try original.write(to: target)
        for (name, run) in [("symlink-add", "add"), ("symlink-doctor", "doctor")] {
            let dir = base.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let link = dir.appendingPathComponent(".gitignore")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let r = run == "add"
                ? try cli(["file", "add", "symlinked", dir.path, "--config", config])
                : try cli(["doctor", "--library", dir.path])
            XCTAssertEqual(r.status == 0, run == "doctor", r.output)
            XCTAssertTrue(r.output.contains("是 symlink"), r.output)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path, "symlink 本身不得被換成一般檔")
            XCTAssertEqual(try bytes(target), original, "symlink 指向的檔不得被改")
        }
    }

    /// 已有區塊、尾端另有非 UTF-8 位元組（先前 doctor 把它變回只剩區塊）：標記以位元組比對，兩個命令都不動它、也不出聲。
    func testExistingBlockWithTrailingNonUTF8BytesIsLeftAlone() throws {
        let original = Data(LibraryStore.sourcesIgnoreBlock.utf8) + Data([0x23, 0x20, 0xE9, 0x0A]) + Data("build/\n".utf8)
        let a = try storeDir("block-add", gitignore: original)
        let ra = try cli(["file", "add", "blocked", a.path, "--config", config])
        XCTAssertEqual(ra.status, 0, ra.output)
        XCTAssertEqual(try bytes(a.appendingPathComponent(".gitignore")), original)
        let d = try storeDir("block-doctor", gitignore: original)
        let rd = try cli(["doctor", "--library", d.path])
        XCTAssertEqual(rd.status, 0, rd.output)
        XCTAssertFalse(rd.output.contains("⚠ .gitignore"), rd.output)
        XCTAssertEqual(try bytes(d.appendingPathComponent(".gitignore")), original)
    }

    /// 正例：UTF-8 檔、沒有區塊、檔尾沒有換行（CRLF 結尾的前一行）——原有位元組逐一保留、補一個 `\n` 後附加區塊；symlink 指向的檔已有區塊時什麼都不做。
    func testUTF8GitignoreGetsTheBlockAppendedAfterItsOwnBytes() throws {
        let original = Data("a\r\nb".utf8)
        let dir = try storeDir("append", gitignore: original)
        let r = try cli(["file", "add", "append", dir.path, "--config", config])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(try bytes(dir.appendingPathComponent(".gitignore")),
                       original + Data("\n".utf8) + Data(LibraryStore.sourcesIgnoreBlock.utf8))

        let dotfiles = base.appendingPathComponent("dotfiles-ok")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("gitignore")
        let withBlock = Data("x/\n".utf8) + Data(LibraryStore.sourcesIgnoreBlock.utf8)
        try withBlock.write(to: target)
        let linked = base.appendingPathComponent("linked-ok")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent(".gitignore"), withDestinationURL: target)
        let r2 = try cli(["file", "add", "linked", linked.path, "--config", config])
        XCTAssertEqual(r2.status, 0, r2.output)
        XCTAssertEqual(try bytes(target), withBlock)
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: linked.appendingPathComponent(".gitignore").path))
    }
}
