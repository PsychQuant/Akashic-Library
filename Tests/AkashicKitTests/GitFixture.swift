import Foundation
import XCTest

/// 測試用的**真** git 工作樹（#73）。
///
/// 在 #73 之前，測試靠「建一個名為 `.git` 的空目錄」滿足版控前提——因為當時的
/// 檢查只做 `fileExists(".git")`。那個檢查的弱點正是 #71 R1 的 security lens 指出的：
/// 任何祖先目錄下名為 `.git` 的東西（空目錄、隨手建的檔案）都算數。
///
/// #73 把前提升級成「本次要刪的檔案 tracked 且 clean」，假 `.git` 就不再夠用了。
/// 測試必須造出**真的可回溯**的狀態，因為那正是被測的性質。
enum GitFixture {

    /// 子程序環境：**剝除全部 `GIT_*`**（#234）。
    ///
    /// `-C <dir>` 不足以把 git 綁在 fixture 上——**`GIT_DIR` 的優先權高於 `-C`**。
    /// 從 git hook（例如 `.githooks/pre-push`）裡跑測試時，git 會在環境注入
    /// `GIT_DIR`／`GIT_INDEX_FILE` 等，於是每一句 fixture 的 git 都作用在**真實
    /// repo** 上：`init` 讓它變 `core.bare = true`、`config` 覆寫使用者身分、
    /// `add -A` 暫存整棵樹、`commit` 把 fixture commit 推進真實歷史。實際發生過
    /// （2026-08-12 01:08，main 被 20 個「Test seed」commit 劫持）。
    ///
    /// 用**前綴剝除**而非列舉具名變數：git 版本會新增變數，列舉會隨時間漏掉，
    /// 而 fixture 對任何 `GIT_*` 都沒有需求。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    @discardableResult
    static func run(_ args: [String], in dir: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// 讀一個值回來（containment 斷言用；失敗回 nil）。
    static func capture(_ args: [String], in dir: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.environment = scrubbedGitEnvironment
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `git init` + 最小 identity。identity 明寫是因為 CI runner 沒有全域設定，
    /// 而 `git commit` 少了它會失敗——失敗訊息還跟被測的東西無關。
    ///
    /// **init 後立即斷言 containment**（#234 第二層）：環境剝除是「讓它不會跑錯
    /// 地方」，這道斷言是「萬一還是跑錯了，當場停住」。剝除靠的是前綴規則，而
    /// 規則可能被未來的 git 或某條沒想到的路徑繞過；斷言不靠規則，它直接問
    /// 「這個 repo 的 git dir 到底在哪」。**寫入型 fixture 的圍籬不能只有一層**
    /// ——第一層漏掉時，代價是使用者的真實 repo。
    static func initRepo(_ dir: URL, file: StaticString = #filePath, line: UInt = #line) {
        run(["init", "-q"], in: dir)

        let resolvedFixture = URL(fileURLWithPath: dir.path).resolvingSymlinksInPath().path
        guard let gitDir = capture(["rev-parse", "--absolute-git-dir"], in: dir) else {
            XCTFail("""
                GitFixture: `git init` 後解析不到 git dir——fixture 未成形，後續每一句
                git 都會落到別處。（#234）
                """, file: file, line: line)
            return
        }
        let resolvedGitDir = URL(fileURLWithPath: gitDir).resolvingSymlinksInPath().path
        guard resolvedGitDir.hasPrefix(resolvedFixture + "/") else {
            XCTFail("""
                GitFixture: git dir 落在 fixture 之外——**拒絕繼續**，否則接下來的
                config／add／commit 會寫進別人的 repo（#234 的實際後果）。
                fixture：\(resolvedFixture)
                git dir：\(resolvedGitDir)
                最可能的原因：環境仍帶著 `GIT_*`（例如從 git hook 裡跑測試）。
                """, file: file, line: line)
            return
        }

        run(["config", "user.email", "test@example.invalid"], in: dir)
        run(["config", "user.name", "Test"], in: dir)
        run(["config", "commit.gpgsign", "false"], in: dir)
    }

    /// 把當下 store 的全部內容 commit 進去——「刪掉找得回來」的狀態。
    static func commitAll(_ dir: URL, message: String = "fixture", file: StaticString = #filePath, line: UInt = #line) {
        // 與 `commit(_:paths:)` 同一條紀律（#558 R2 verify 第 24 列：R2 只修了一個 helper，而全部新測試的前提靠這一個）
        let a = run(["add", "-A"], in: dir)
        guard a == 0 else { return XCTFail("GitFixture.commitAll：`git add -A` 回 \(a)", file: file, line: line) }
        let c = run(["commit", "-q", "-m", message, "--allow-empty"], in: dir)
        guard c == 0 else { return XCTFail("GitFixture.commitAll：`git commit` 回 \(c)", file: file, line: line) }
    }

    /// 只 commit 指定的路徑——讓 fixture 能精確製造「某一個檔 untracked、其餘 tracked」
    /// 的狀態（#558：閘對 divergence 記錄有效、對被併實體無效，兩者要分得開才測得到）。
    static func commit(_ dir: URL, paths: [String], message: String = "fixture",
                       file: StaticString = #filePath, line: UInt = #line) {
        // 任一句非零就當場停（#558 R1 verify 第 13／14／16／18 列）：pathspec 打錯或「nothing to commit」時 fixture 會靜默退化成
        // 「兩個檔都 untracked」，而它宣稱的「**精確**製造某一個檔 untracked、其餘 tracked」就沒有被任何東西驗過——同 `initRepo` 的紀律。
        let a = run(["add", "--"] + paths, in: dir)
        guard a == 0 else { return XCTFail("GitFixture.commit：`git add` 回 \(a)（pathspec：\(paths)）", file: file, line: line) }
        let c = run(["commit", "-q", "-m", message, "--"] + paths, in: dir)
        guard c == 0 else { return XCTFail("GitFixture.commit：`git commit` 回 \(c)（pathspec：\(paths)）", file: file, line: line) }
    }

    /// `initRepo` + `commitAll` 的常用組合。
    static func initAndCommit(_ dir: URL) {
        initRepo(dir)
        commitAll(dir, message: "seed")
    }
}
