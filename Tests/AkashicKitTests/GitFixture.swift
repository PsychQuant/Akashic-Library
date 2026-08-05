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

    @discardableResult
    static func run(_ args: [String], in dir: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// `git init` + 最小 identity。identity 明寫是因為 CI runner 沒有全域設定，
    /// 而 `git commit` 少了它會失敗——失敗訊息還跟被測的東西無關。
    static func initRepo(_ dir: URL) {
        run(["init", "-q"], in: dir)
        run(["config", "user.email", "test@example.invalid"], in: dir)
        run(["config", "user.name", "Test"], in: dir)
        run(["config", "commit.gpgsign", "false"], in: dir)
    }

    /// 把當下 store 的全部內容 commit 進去——「刪掉找得回來」的狀態。
    static func commitAll(_ dir: URL, message: String = "fixture") {
        run(["add", "-A"], in: dir)
        run(["commit", "-q", "-m", message, "--allow-empty"], in: dir)
    }

    /// `initRepo` + `commitAll` 的常用組合。
    static func initAndCommit(_ dir: URL) {
        initRepo(dir)
        commitAll(dir, message: "seed")
    }
}
