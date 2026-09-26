import Foundation
@testable import AkashicMCPKit

/// #573：repoint／demote 會刪判定記錄時，要求那些 venue 檔已在 git 裡 commit。測試照同一個流程走——在呼叫之前把 store
/// 放進 git 並 commit——而不是給產品碼開後門。
enum StoreGitCommit {
    /// 剝除 GIT_*（#239）：測試在 pre-push hook 裡跑，hook 環境帶著 GIT_DIR，`-C` 擋不住它。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private static func run(_ args: [String], in dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    /// 初始化（若尚未）並 commit store 的全部內容。
    static func commitAll(_ root: URL) {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) {
            run(["init", "-q"], in: root)
        }
        run(["add", "-A"], in: root)
        run(["commit", "-q", "--allow-empty", "-m", "fixture"], in: root)
    }
}

extension AkashicService {
    /// 先 commit store 再回傳自己——用法：`try service.committed(root).resolveVenues(…)`。
    func committed(_ root: URL) -> AkashicService {
        StoreGitCommit.commitAll(root)
        return self
    }
}
