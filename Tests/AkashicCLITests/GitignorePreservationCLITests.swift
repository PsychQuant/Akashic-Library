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

    // MARK: - b33 verify X5：沒有測試釘住的形狀（第 7／11 列）與新的分類（第 2／14／15／22 列）

    /// 唯讀（0444）而目錄可寫：在建立任何東西之前拒絕（`faccessat` 的預檢；拿掉它時 0444 會在寫入那一步才被 `open` 擋下、佈局已建好）。
    /// 舊版會整份替換它——changelog 記的行為改變。
    func testReadOnlyGitignoreIsRefusedBeforeAnythingIsBuilt() throws {
        try XCTSkipIf(geteuid() == 0, "root 寫得進 0444 的檔")
        let original = Data("*.srt\n".utf8)
        let a = try storeDir("readonly-add", gitignore: original)
        chmod(a.appendingPathComponent(".gitignore").path, 0o444)
        let r = try cli(["file", "add", "readonly", a.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("沒有寫入權限") && r.output.contains("這一次也沒有建立任何東西"), r.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("store.yaml").path), "預檢在建立任何東西之前")
        XCTAssertEqual(try bytes(a.appendingPathComponent(".gitignore")), original)
        let d = try storeDir("readonly-doctor", gitignore: original)
        chmod(d.appendingPathComponent(".gitignore").path, 0o444)
        let rd = try cli(["doctor", "--library", d.path])
        XCTAssertEqual(rd.status, 0, rd.output)
        XCTAssertTrue(rd.output.contains("⚠ .gitignore 沒有 sources 排除區塊，doctor 沒有改寫它") && rd.output.contains("沒有寫入權限"), rd.output)
        XCTAssertEqual(try bytes(d.appendingPathComponent(".gitignore")), original)
    }

    /// 目錄與 FIFO：不是一般檔，什麼都不建。
    func testADirectoryOrAFifoIsNotAGitignore() throws {
        let dirCase = base.appendingPathComponent("dir-case")
        try FileManager.default.createDirectory(at: dirCase.appendingPathComponent(".gitignore"), withIntermediateDirectories: true)
        let fifoCase = base.appendingPathComponent("fifo-case")
        try FileManager.default.createDirectory(at: fifoCase, withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(fifoCase.appendingPathComponent(".gitignore").path, 0o644), 0)
        for (i, dir) in [dirCase, fifoCase].enumerated() {
            let r = try cli(["file", "add", "odd\(i)", dir.path, "--config", config])
            XCTAssertNotEqual(r.status, 0, r.output)
            XCTAssertTrue(r.output.contains("不是一般檔"), r.output)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.yaml").path))
        }
    }

    /// 懸空的 symlink 與迴圈：說「打不開」，不說「指向的內容沒有區塊」（第 22 列：那時沒有內容可言）；symlink 本身不動。
    func testBrokenSymlinksSayTheTargetCannotBeOpened() throws {
        let dangling = base.appendingPathComponent("dangling")
        try FileManager.default.createDirectory(at: dangling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dangling.appendingPathComponent(".gitignore").path,
                                                   withDestinationPath: base.appendingPathComponent("nowhere").path)
        let loop = base.appendingPathComponent("loop")
        try FileManager.default.createDirectory(at: loop, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: loop.appendingPathComponent(".gitignore").path, withDestinationPath: ".gitignore")
        for (i, dir) in [dangling, loop].enumerated() {
            let r = try cli(["file", "add", "broken\(i)", dir.path, "--config", config])
            XCTAssertNotEqual(r.status, 0, r.output)
            XCTAssertTrue(r.output.contains("指向的檔打不開"), r.output)
            XCTAssertFalse(r.output.contains("指向的內容沒有"), r.output)
            XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: dir.appendingPathComponent(".gitignore").path), "symlink 不動")
            let rd = try cli(["doctor", "--library", dir.path])
            XCTAssertEqual(rd.status, 0, rd.output)
            XCTAssertTrue(rd.output.contains("指向的檔打不開"), rd.output)
        }
    }

    /// 硬連結：附加會改到別處共用的同一個 inode（第 14 列：舊版的原子替換會拆掉連結、另一條路徑不動；c86ae785 起照樣附加）。
    func testAHardLinkedGitignoreIsRefusedLikeASymlink() throws {
        let shared = base.appendingPathComponent("shared-gitignore")
        let original = Data("*.srt\n".utf8)
        try original.write(to: shared)
        let dir = base.appendingPathComponent("hardlinked")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(link(shared.path, dir.appendingPathComponent(".gitignore").path), 0)
        let r = try cli(["file", "add", "hardlinked", dir.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("硬連結"), r.output)
        let rd = try cli(["doctor", "--library", dir.path])
        XCTAssertEqual(rd.status, 0, rd.output)
        XCTAssertTrue(rd.output.contains("硬連結"), rd.output)
        XCTAssertEqual(try bytes(shared), original, "別處共用的那個檔不得被改")
    }

    /// 標記在、排除規則不在（寫到一半中斷）：不算已在（第 2 列：先前永遠被當成已在而不補）；不改寫既有的區塊、拒絕／報。
    /// 手工寫的區塊用 `/sources/`、CRLF、前後空白也算數。
    func testAMarkerWithoutTheRuleIsNotTreatedAsPresent() throws {
        let half = Data("*.srt\n# BEGIN akashic sources — 存檔的來源內容\n".utf8)
        let a = try storeDir("half-add", gitignore: half)
        let r = try cli(["file", "add", "half", a.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("標記之後沒有排除"), r.output)
        XCTAssertEqual(try bytes(a.appendingPathComponent(".gitignore")), half)
        let d = try storeDir("half-doctor", gitignore: half)
        let rd = try cli(["doctor", "--library", d.path])
        XCTAssertEqual(rd.status, 0, rd.output)
        XCTAssertTrue(rd.output.contains("標記之後沒有排除"), rd.output)
        XCTAssertEqual(try bytes(d.appendingPathComponent(".gitignore")), half)

        for (i, rule) in ["/sources/\r\n", "  sources  \n", "sources/**\n"].enumerated() {
            let hand = Data("# BEGIN akashic sources\n# 手寫的\n\(rule)# END akashic sources\n".utf8)
            let dir = try storeDir("hand-\(i)", gitignore: hand)
            let rr = try cli(["file", "add", "hand\(i)", dir.path, "--config", config])
            XCTAssertEqual(rr.status, 0, "\(rule)：\(rr.output)")
            XCTAssertEqual(try bytes(dir.appendingPathComponent(".gitignore")), hand, "手工區塊不改寫")
        }
    }

    /// 大到 git 不讀（≥ 100 MiB；稀疏檔，不真的佔空間）：不讀、不寫（第 15 列：先前整檔讀進來、RSS 約 3.3 倍）。
    func testAGitignoreTooLargeForGitIsNeitherReadNorAppended() throws {
        let dir = base.appendingPathComponent("huge")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gi = dir.appendingPathComponent(".gitignore")
        FileManager.default.createFile(atPath: gi.path, contents: Data("*.srt\n".utf8))
        XCTAssertEqual(truncate(gi.path, off_t(LibraryStore.gitignoreSizeLimit)), 0)
        let r = try cli(["file", "add", "huge", dir.path, "--config", config])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("git 不讀"), r.output)
        var st = stat()
        XCTAssertEqual(stat(gi.path, &st), 0)
        XCTAssertEqual(st.st_size, off_t(LibraryStore.gitignoreSizeLimit), "沒有附加")
    }

    // MARK: - 寫入失敗與回滾（注入；第 1／9 列）

    private func layoutStore(_ name: String, gitignore: Data?) throws -> (LibraryStore, URL) {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let gitignore { try gitignore.write(to: dir.appendingPathComponent(".gitignore")) }
        return (LibraryStore(root: dir), dir.appendingPathComponent(".gitignore"))
    }

    /// 寫到一半失敗：截回原長，原因是 `writeFailed`、`.gitignore` 逐位元組不變。
    func testAPartialWriteIsRolledBackToTheOriginalLength() throws {
        let original = Data("*.srt\n".utf8)
        let (store, gi) = try layoutStore("partial", gitignore: original)
        let problem = try SourcesIgnoreIO.$write.withValue({ fd, bytes in
            let n = bytes.prefix(10).withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            return (n, EIO)
        }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertEqual(problem, .writeFailed(errno: EIO))
        XCTAssertTrue(problem?.leavesGitignoreUntouched == true)
        XCTAssertEqual(try bytes(gi), original)
    }

    /// 截斷也失敗：不再說「已截回原長」——`rollbackFailed`、`leavesGitignoreUntouched == false`，訊息說尾端可能留著半段。
    func testAFailedTruncateIsReportedNotHidden() throws {
        let original = Data("*.srt\n".utf8)
        let (store, gi) = try layoutStore("truncfail", gitignore: original)
        let problem = try SourcesIgnoreIO.$write.withValue({ fd, bytes in
            let n = bytes.prefix(10).withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            return (n, ENOSPC)
        }) {
            try SourcesIgnoreIO.$truncate.withValue({ _, _ in EIO }) { try store.ensureLayout(sourcesIgnore: .report) }
        }
        XCTAssertEqual(problem, .rollbackFailed(writeErrno: ENOSPC, truncateErrno: EIO))
        XCTAssertFalse(problem!.leavesGitignoreUntouched)
        XCTAssertTrue(problem!.reason.contains("可能留著半段區塊"), problem!.reason)
        XCTAssertEqual(try bytes(gi).count, original.count + 10, "截斷失敗：留著寫進去的 10 個位元組")
        let err = StoreIOError.sourcesIgnoreNotWritten(problem!, layoutWritten: true)
        XCTAssertFalse(err.localizedDescription.contains(".gitignore 沒有改寫"), err.localizedDescription)
    }

    /// 寫入期間別的寫入者附加了位元組：不截（截了會刪掉別人的），具名回報。
    func testAnotherWritersBytesAreNotTruncatedAway() throws {
        let original = Data("*.srt\n".utf8)
        let (store, gi) = try layoutStore("otherwriter", gitignore: original)
        let other = Data("other/\n".utf8)
        let path = gi.path
        let problem = try SourcesIgnoreIO.$write.withValue({ fd, bytes in
            let n = bytes.prefix(10).withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(other); h.closeFile() }
            return (n, EIO)
        }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertEqual(problem, .rollbackFailed(writeErrno: EIO, truncateErrno: nil))
        XCTAssertTrue(try bytes(gi).suffix(other.count) == other, "別人的位元組要還在")
    }

    /// 新建的 `.gitignore` 一個位元組都沒寫進去就失敗：刪掉自己建的空檔（原因是 `writeFailed`，不是 `openFailed`）。
    func testACreatedFileThatGotNothingIsRemoved() throws {
        let (store, gi) = try layoutStore("created", gitignore: nil)
        let problem = try SourcesIgnoreIO.$write.withValue({ _, _ in (0, ENOSPC) }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertEqual(problem, .writeFailed(errno: ENOSPC))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gi.path))
    }

    /// 判讀與 UTF-8 驗證：`isValidUTF8` 與先前的「解碼再編碼要逐位元組相同」對邊界序列給同一個答案。
    func testUTF8ValidationMatchesTheRoundTrip() {
        let cases: [[UInt8]] = [[0x61], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], [0xF0, 0x9F, 0x98, 0x80], [0xC0, 0x80], [0xE0, 0x80, 0x80],
                                [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xF8, 0x88, 0x80, 0x80, 0x80], [0x80], [0xC3], [0xEF, 0xBB, 0xBF, 0x61]]
        for c in cases {
            XCTAssertEqual(LibraryStore.isValidUTF8(c), Array(String(decoding: c, as: UTF8.self).utf8) == c, "\(c)")
        }
        XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array("a\nb".utf8)), .needsBlock(needsNewline: true))
        XCTAssertEqual(LibraryStore.judgeSourcesIgnore([]), .needsBlock(needsNewline: false))
        XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array(LibraryStore.sourcesIgnoreBlock.utf8)), .blockPresent)
        XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array("# BEGIN akashic sources\n!sources/\n".utf8)), .markerWithoutRule, "否定規則不算")
        XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array("sources/\n# BEGIN akashic sources\n".utf8)), .markerWithoutRule, "規則要在標記之後")
    }
}
