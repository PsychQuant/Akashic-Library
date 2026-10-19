import XCTest
import Foundation
@testable import AkashicStoreIO

/// #700 b42 verify：`.gitignore` 的 sources 區塊不能確定生效時給人的處置，與寫入失敗之後留下什麼。
///
/// - MEDIUM 0（同 LOW 3、6，devil's advocate 19 校準）：`ruleNegatedLater` 的處置叫人跑 `git check-ignore -v`，說「它只列出被排除的」、
///   「兩個都列出是判讀保守」。`-v` 也列出最後符合的是否定規則（`!` 開頭）的路徑，一個存檔子目錄也代表不了其他的。這裡**照處置寫的指令真的跑
///   git**，拿 `git ls-files --others --exclude-standard`（git add 會收進去的檔）當對照。
/// - MEDIUM 1（同 LOW 9）：`file add` 的拒絕把首句、原因、「沒有改寫」與處置接成一行，CLI 逐行截 400，處置被截掉。這裡量每一種原因組出來的每一行，
///   並在真 binary 的輸出裡找完整的處置句。
/// - MEDIUM 2：新建的 `.gitignore` 寫入失敗時以路徑 `unlink`，路徑在寫入期間被不用 `flock` 的程式換成使用者的檔就刪掉它。
///
/// scratch：`--config`、`--library` 與 `AKASHIC_HOME` 都指暫存目錄；git 剝掉 `GIT_*`、不讀使用者與系統設定。
final class GitignoreRemedyCLITests: XCTestCase {
    private var base: URL!
    private var home: URL!
    private var config: String { home.appendingPathComponent("config.yaml").path }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-gitignore-remedy-\(UUID().uuidString)")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": home.path])
    }

    private static let block = "# BEGIN akashic sources\nsources/\n# END akashic sources\n"
    private static let contentBlock = "# BEGIN akashic sources\nsources/*\n# END akashic sources\n"

    /// 區塊之後有否定規則、判成 `ruleNegatedLater` 的形狀（b42 verify 第 0、3、6、19 則用過的每一種）。
    private static let negatedShapes: [(name: String, text: String)] = [
        ("dir rule then !*", block + "!*\n"),
        ("dir rule then !sources/", block + "!sources/\n"),
        ("content rule then !*.jsonl", contentBlock + "!*.jsonl\n"),
        ("content rule then !sources/index.jsonl", contentBlock + "!sources/index.jsonl\n"),
        ("content rule then the index and one shard", contentBlock + "!sources/index.jsonl\n!sources/00/\n"),
        ("content rule then another shard", contentBlock + "!sources/ab/\n"),
        ("content rule then !sources/f*", contentBlock + "!sources/f*\n"),
    ]

    /// 磁碟上建出來的路徑：處置點名的兩個，加上它沒點名的存檔子目錄（`ab`、`ff`）——對照「兩個都印出不代表其他的」。
    private static let materialized = ["sources/index.jsonl", "sources/00/x", "sources/ab/x", "sources/ff/x"]

    // MARK: - git

    private func git(_ args: [String], in dir: URL) -> (status: Int32, out: String) {
        // 共用名稱 scrubbedGitEnvironment 讓 GitSpawnHygieneTests 認得這一處已剝除 GIT_*（#234／#239）
        var scrubbedGitEnvironment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") && $0.key != "XDG_CONFIG_HOME" }
        scrubbedGitEnvironment["HOME"] = base.appendingPathComponent("git-home").path
        scrubbedGitEnvironment["GIT_CONFIG_NOSYSTEM"] = "1"
        scrubbedGitEnvironment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        p.environment = scrubbedGitEnvironment
        let out = Pipe()
        p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 一個 git 工作樹，`.gitignore` 是 `text`，`materialized` 的檔都在磁碟上（空檔）。
    private func repo(_ name: String, gitignore text: String) throws -> URL {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(git(["init", "-q"], in: dir).status, 0)
        try Data(text.utf8).write(to: dir.appendingPathComponent(".gitignore"))
        for path in Self.materialized {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return dir
    }

    /// 對照：`git add` 會收進去的檔（沒被排除的、未追蹤的）。
    private func notExcluded(in dir: URL) -> Set<String> {
        let r = git(["ls-files", "--others", "--exclude-standard", "--", "sources"], in: dir)
        XCTAssertEqual(r.status, 0)
        return Set(r.out.split(separator: "\n").map(String.init))
    }

    /// 處置裡給的那一條指令（`git check-ignore` 起、到「 看」為止），切成 argv（去掉 `git`）。
    private func remedyCommand(_ remedy: String) throws -> [String] {
        let start = try XCTUnwrap(remedy.range(of: "git check-ignore"), remedy)
        let end = try XCTUnwrap(remedy.range(of: " 看", range: start.upperBound..<remedy.endIndex), remedy)
        return remedy[start.lowerBound..<end.lowerBound].split(separator: " ").dropFirst().map(String.init)
    }

    /// 照處置寫的指令真的跑 git：它印出的路徑恰好是被排除的那幾個（處置說「它只印出被排除的路徑，沒印出來的那一個沒被排除」）。
    /// 修前的指令帶 `-v`：`!*`、`!*.jsonl` 之後，沒被排除的路徑照樣印出（那一行的規則以 `!` 開頭）——照字面讀，兩個都列出被說成「判讀保守」。
    func testTheNegationRemedysCommandPrintsExactlyTheExcludedPaths() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"), "沒有 git")
        let remedy = SourcesIgnoreProblem.ruleNegatedLater.remedy
        let argv = try remedyCommand(remedy)
        XCTAssertEqual(argv.first, "check-ignore", remedy)
        let named = argv.dropFirst().filter { !$0.hasPrefix("-") }
        XCTAssertFalse(named.isEmpty, remedy)
        for (k, shape) in Self.negatedShapes.enumerated() {
            XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array(shape.text.utf8)), .ruleNegatedLater, "前提：\(shape.name)")
            let dir = try repo("cmd-\(k)", gitignore: shape.text)
            let open = notExcluded(in: dir)
            // 點名的路徑（目錄形就看它底下的檔）有沒有被排除
            let excluded = Set(named.filter { p in !open.contains { $0 == p || (p.hasSuffix("/") && $0.hasPrefix(p)) } })
            let r = git(argv, in: dir)
            let printed = Set(r.out.split(separator: "\n").map { line in String(line.split(separator: "\t").last ?? line) })
            XCTAssertEqual(printed, excluded, "\(shape.name)：處置的指令印出的不是被排除的那幾個（git add 會收的：\(open.sorted())）\n\(r.out)")
        }
        XCTAssertFalse(remedy.contains("判讀保守"), "「兩個都列出是判讀保守」不成立：\(remedy)")
    }

    /// 處置對 `-v` 的讀法照 git 成立：每一行是路徑與最後符合它的規則，規則以 `!` 開頭的路徑沒被排除、其餘的被排除；沒出現在輸出裡的路徑沒被排除。
    /// 「兩個都印出只說明這兩個」：有一種形狀點名的兩個都被排除、而別的存檔子目錄沒有。「檔尾補一行頂格的 sources/」對每一種都有效、判讀也照算已在。
    func testTheNegationRemedysReadingOfGitHoldsForEveryShape() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/git"), "沒有 git")
        let remedy = SourcesIgnoreProblem.ruleNegatedLater.remedy
        XCTAssertTrue(remedy.contains("以 ! 開頭"), remedy)
        XCTAssertTrue(remedy.contains("其他存檔子目錄"), remedy)
        XCTAssertTrue(remedy.contains("檔尾補一行頂格的 sources/"), remedy)
        let named = try remedyCommand(remedy).dropFirst().filter { !$0.hasPrefix("-") }
        var namedAllExcludedButAnotherShardOpen = false
        for (k, shape) in Self.negatedShapes.enumerated() {
            let dir = try repo("v-\(k)", gitignore: shape.text)
            let open = notExcluded(in: dir)
            let r = git(["check-ignore", "-v"] + Self.materialized, in: dir)
            var listed: Set<String> = []
            for line in r.out.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                XCTAssertEqual(parts.count, 2, "\(shape.name)：\(line)")
                let path = String(parts[1])
                let pattern = parts[0].split(separator: ":", maxSplits: 2).last.map(String.init) ?? ""
                listed.insert(path)
                XCTAssertEqual(pattern.hasPrefix("!"), open.contains(path), "\(shape.name)：\(line)（git add 會收的：\(open.sorted())）")
            }
            for path in Self.materialized where !listed.contains(path) {
                XCTAssertTrue(open.contains(path), "\(shape.name)：沒出現在 -v 的輸出裡卻被排除：\(path)")
            }
            if named.allSatisfy({ !open.contains($0) }), Self.materialized.contains(where: { open.contains($0) }) {
                namedAllExcludedButAnotherShardOpen = true
            }
            // 檔尾補一行頂格的 sources/
            let fixed = shape.text + "sources/\n"
            try Data(fixed.utf8).write(to: dir.appendingPathComponent(".gitignore"))
            XCTAssertEqual(notExcluded(in: dir), [], "\(shape.name)：補了 sources/ 之後仍有沒被排除的檔")
            XCTAssertEqual(LibraryStore.judgeSourcesIgnore(Array(fixed.utf8)), .blockPresent, shape.name)
        }
        XCTAssertTrue(namedAllExcludedButAnotherShardOpen, "語料裡要有「點名的都被排除、別的存檔子目錄沒有」的形狀，處置那一句才有對照")
    }

    // MARK: - 400 字的 sink

    /// 每一種原因、兩種 `layoutWritten`：`file add` 的拒絕經 CLI 頂層的 sink（加 `Error: `、逐行截 400）之後每一行都放得下，處置完整出現；
    /// 匯入的 warning（最長的動作名、加匯入那一句）每一行也放得下——MCP `akashic_import_wos` 的 index rebuild 失敗時，warning 接在錯誤訊息後面、
    /// 經同一個 400 的 sink。
    func testEveryComposedLineFitsTheSinkAndKeepsTheRemedy() {
        for problem in Self.allProblems {
            for layoutWritten in [false, true] {
                let text = "Error: " + (LibraryStore.sourcesIgnoreRefusal(problem, layoutWritten: layoutWritten).errorDescription ?? "")
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    XCTAssertLessThanOrEqual(line.unicodeScalars.count, 400, "\(problem)：\(line)")
                }
                XCTAssertTrue(text.contains(problem.remedy + "："), "\(problem)：\(text)")
            }
            for line in problem.warningLines(by: "akashic_import_zotero", note: SourcesIgnoreProblem.importContinuedNote,
                                             rerun: SourcesIgnoreProblem.importRerun) {
                XCTAssertLessThanOrEqual(line.unicodeScalars.count, 400, "\(problem)：\(line)")
            }
        }
    }

    /// 真 binary：區塊之後有否定規則、只排除內容而 `sources/` 裡另有 `.gitignore`——兩種處置最長的拒絕，處置整句都在輸出裡、沒有被截。
    func testFileAddShowsTheWholeRemedy() throws {
        let negated = base.appendingPathComponent("negated")
        try FileManager.default.createDirectory(at: negated, withIntermediateDirectories: true)
        try Data((Self.block + "!sources/\n").utf8).write(to: negated.appendingPathComponent(".gitignore"))
        let nested = base.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try Data(Self.contentBlock.utf8).write(to: nested.appendingPathComponent(".gitignore"))
        try Data("!*\n".utf8).write(to: nested.appendingPathComponent("sources/.gitignore"))
        for (dir, problem) in [(negated, SourcesIgnoreProblem.ruleNegatedLater), (nested, .contentRuleWithNestedGitignore)] {
            let r = try cli(["file", "add", dir.lastPathComponent, dir.path, "--config", config])
            XCTAssertNotEqual(r.status, 0, r.output)
            XCTAssertTrue(r.output.contains(problem.remedy), "\(problem)：處置要整句都在：\(r.output)")
            XCTAssertTrue(r.output.contains("不要再貼一份"), r.output)
            XCTAssertFalse(r.output.contains("（已截斷）"), r.output)
        }
    }

    // MARK: - 新建的檔

    /// `lockTimedOutAfterCreating`（與寫入失敗的新建）留下一個這一次新建的空檔：拒絕與 warning 不說「沒有改寫」（b42 verify LOW 5、INFO 13、16：
    /// 原因說「這一次新建了它」，同一則訊息的尾句卻說「.gitignore 沒有改寫」）。
    func testACreatedEmptyGitignoreIsNotCalledUntouched() {
        for problem in Self.allProblems where problem.effect == .createdEmpty {
            let warning = problem.warningLines(by: "doctor").joined(separator: "\n")
            XCTAssertFalse(warning.contains("沒有改寫"), "\(problem)：\(warning)")
            XCTAssertTrue(warning.contains("doctor 新建了它（空的）"), "\(problem)：\(warning)")
            for layoutWritten in [false, true] {
                let refusal = LibraryStore.sourcesIgnoreRefusal(problem, layoutWritten: layoutWritten).errorDescription ?? ""
                XCTAssertFalse(refusal.contains("沒有改寫"), "\(problem)：\(refusal)")
                XCTAssertTrue(refusal.contains(".gitignore 是這一次新建的空檔"), "\(problem)：\(refusal)")
            }
        }
        XCTAssertEqual(Self.allProblems.filter { $0.effect == .createdEmpty },
                       [.lockTimedOutAfterCreating, .writeFailedAfterCreating(errno: EIO)])
    }

    private func layoutStore(_ name: String, gitignore: Data?) throws -> (LibraryStore, URL) {
        let dir = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let gitignore { try gitignore.write(to: dir.appendingPathComponent(".gitignore")) }
        return (LibraryStore(root: dir), dir.appendingPathComponent(".gitignore"))
    }

    /// MEDIUM 2：新建的 `.gitignore` 寫入失敗，而寫入期間不用 `flock` 的程式（編輯器、`git checkout`、`mv`）把路徑原子換成使用者的檔。
    /// 修前以路徑 `unlink`：使用者擋 raw 逐字稿的規則被刪掉，訊息還說「沒有改寫」。現在新建的檔一律不以路徑刪（同 `lockTimedOutAfterCreating`）。
    func testAFailedWriteDoesNotDeleteTheFileThatReplacedTheCreatedOne() throws {
        let (store, gi) = try layoutStore("replaced", gitignore: nil)
        let users = Data("*.srt\n*.mp3\n".utf8)
        let staged = gi.deletingLastPathComponent().appendingPathComponent(".gitignore.new")
        try users.write(to: staged)
        let path = gi.path
        let problem = try SourcesIgnoreIO.$write.withValue({ _, _ in
            _ = rename(staged.path, path)
            return (0, ENOSPC)
        }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertEqual(try? Data(contentsOf: gi), users, "使用者的檔要留著")
        XCTAssertEqual(problem, .writeFailedAfterCreating(errno: ENOSPC))
    }

    /// 新建的 `.gitignore` 寫到一半失敗：截回空的、檔留著（不以路徑刪），原因說它留著；下一次照常附加。
    func testAFailedWriteLeavesTheCreatedFileEmpty() throws {
        let (store, gi) = try layoutStore("created-partial", gitignore: nil)
        let problem = try SourcesIgnoreIO.$write.withValue({ fd, bytes in
            let n = bytes.prefix(10).withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            return (n, ENOSPC)
        }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertEqual(problem, .writeFailedAfterCreating(errno: ENOSPC))
        XCTAssertEqual(try Data(contentsOf: gi), Data(), "截回空的、留著")
        XCTAssertTrue(problem!.reason.contains("留著"), problem!.reason)
        XCTAssertNil(try store.ensureLayout(sourcesIgnore: .report), "下一次照常附加")
        XCTAssertEqual(try Data(contentsOf: gi), Data(LibraryStore.sourcesIgnoreBlock.utf8))
    }

    /// LOW 8：先看在等 `LOCK_SH` 的時候，路徑上的檔被刪掉（或換掉）。修前取到鎖之後不再看路徑：讀已經不在路徑上的那個 inode，判成要附加，
    /// 再以路徑問寫入權限得到 `ENOENT`，報「沒有寫入權限」。現在取到鎖之後比對路徑仍指著打開的那個檔，不是就重看。
    func testAFirstLookThatWaitedForTheLockRereadsWhenThePathChanged() throws {
        let (store, gi) = try layoutStore("sh-replaced", gitignore: Data("*.srt\n".utf8))
        let path = gi.path
        let fired = Flag()
        let problem = try SourcesIgnoreIO.$tryLock.withValue({ fd, operation in
            if operation == LOCK_SH, !fired.value { fired.value = true; unlink(path) }
            return flock(fd, operation | LOCK_NB) == 0 ? nil : errno
        }) { try store.ensureLayout(sourcesIgnore: .report) }
        XCTAssertTrue(fired.value, "前提：先看真的取了 LOCK_SH")
        XCTAssertNil(problem, "重看之後檔案不在、照常新建")
        XCTAssertEqual(try Data(contentsOf: gi), Data(LibraryStore.sourcesIgnoreBlock.utf8))
    }

    private final class Flag: @unchecked Sendable { var value = false }

    /// 每一種原因（`testEveryProblemsHeadlineAndRemedyAgreeWithWhatWasRead` 以沒有 `default` 的 switch 釘住數量）。
    private static let allProblems: [SourcesIgnoreProblem] = [
        .unreadable(errno: EACCES), .notUTF8Text, .symlink, .brokenSymlink(errno: ENOENT), .notRegularFile, .hardLinked, .tooLarge,
        .markerWithoutRule, .ruleNegatedLater, .contentRuleWithNestedGitignore, .notWritable(errno: EACCES), .openFailed(errno: EMFILE),
        .changedWhileChecking, .lockTimedOut, .lockTimedOutAfterCreating, .writeFailed(errno: EIO), .writeFailedAfterCreating(errno: EIO),
        .rollbackFailed(writeErrno: EIO, truncateErrno: nil),
    ]
}
