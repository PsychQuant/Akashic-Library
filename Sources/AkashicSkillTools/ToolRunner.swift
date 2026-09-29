import Foundation
import AkashicCore

/// 跑一個外部命令（`pdfinfo`、`pdftotext`、`git`），收 stdout／stderr（#629）。
///
/// 經 `/usr/bin/env` 依 PATH 解析命令名（舊腳本的 `subprocess.run(["pdfinfo", …])` 也是 PATH 解析）；`env` 找不到命令回 127，
/// 這裡把它翻成「沒有安裝」的具名錯誤。stdout 與 stderr 各用一條執行緒讀到 EOF——先讀一條再讀另一條，在輸出超過 pipe 緩衝
/// （64 KB）時會與子程序互相等待。
enum ToolRunner {
    struct Result {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// 跑 git 用的環境：剝除 `GIT_*` 與 xcrun 選路的三個變數（與 `AkashicStoreIO` 的 `scrubbedGitEnvironment` 同一條理由，#234／#239）。
    ///
    /// `git -C <dir>` 擋不住 `GIT_DIR`——從 git hook 裡執行時，`GIT_DIR` 指向的是**呼叫 hook 的那個 repo**，於是 `check-ignore`
    /// 問的是錯的 repo，「這個輸出路徑會不會落進沒有忽略它的 git 工作樹」這道閘就 fail-open（放行第三方全文寫進版控範圍）。
    /// 舊的 `fetch-fulltext.sh` 用裸的 `git -C`，沒有這個保護；移植時補上，不是照抄。
    /// 這個模組裡每一處 spawn git 都走 `git(_:)`（`GitSpawnHygieneTests` 逐檔檢查）。
    static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("GIT_") && !["DEVELOPER_DIR", "TOOLCHAINS", "SDKROOT"].contains($0.key)
        }
    }

    /// 在剝除過的環境裡跑 git。
    static func git(_ args: [String]) throws -> Result {
        try run(["git"] + args, environment: scrubbedGitEnvironment)
    }

    static func run(_ argv: [String], stdin: Data? = nil, environment: [String: String]? = nil) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        if let environment { p.environment = environment }
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = stdin == nil ? FileHandle.nullDevice : inp
        do { try p.run() } catch {
            throw SkillToolError.failure("無法執行 \(displaySafeInvisible(argv.first ?? "", max: 80))：\(displaySafeErrorText(error))")
        }
        let outBox = Box(), errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outBox.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if let stdin {
            inp.fileHandleForWriting.write(stdin)
            try? inp.fileHandleForWriting.close()
        }
        p.waitUntilExit()
        group.wait()
        if p.terminationStatus == 127, errBox.data.starts(with: Data("env:".utf8)) {
            throw SkillToolError.failure("找不到命令 \(displaySafeInvisible(argv.first ?? "", max: 80))（不在 PATH 上）")
        }
        return Result(status: p.terminationStatus, stdout: outBox.data, stderr: errBox.data)
    }
}
