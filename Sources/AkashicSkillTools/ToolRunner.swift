import Foundation
import AkashicCore

/// 跑一個外部命令（`pdfinfo`、`pdftotext`、`safari-browser`），收 stdout／stderr（#629）。
///
/// 經 `/usr/bin/env` 依 PATH 解析命令名（舊腳本的 `subprocess.run(["pdfinfo", …])` 也是 PATH 解析）；`env` 找不到命令回 127，
/// 這裡把它翻成「沒有安裝」的具名錯誤。stdout 與 stderr 各用一條執行緒讀到 EOF——先讀一條再讀另一條，在輸出超過 pipe 緩衝
/// （64 KB）時會與子程序互相等待。
///
/// **這裡不跑 git。** 第一版有一個 `git(_:)`（`/usr/bin/env git`、只剝 `GIT_*`），輸出路徑閘用它；R1 verify 指出它比 repo 既有的
/// 加固 helper 弱（PATH 上的 shim 能替 `check-ignore` 作答、目標 repo 的 `core.fsmonitor` 會在閘裡執行）。現在 git 呼叫一律走
/// `LibraryStore.hardenedGit`（#585 的同一支：`/usr/bin/git` 絕對路徑、剝 `GIT_*`、`-c core.fsmonitor=false`、
/// `-c core.attributesFile=/dev/null`、`GIT_ATTR_NOSYSTEM=1`），本型別不再有第二份。
enum ToolRunner {
    struct Result {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        private var flag = false
        var data: Data { get { lock.lock(); defer { lock.unlock() }; return stored } set { lock.lock(); stored = newValue; lock.unlock() } }
        var timedOut: Bool { get { lock.lock(); defer { lock.unlock() }; return flag } set { lock.lock(); flag = newValue; lock.unlock() } }
    }

    /// poppler 對下載來的第三方 PDF 跑的逾時（秒）。舊實作（`subprocess.run` 無逾時）遇到病態 PDF 會無限期卡住整批——`fetch`
    /// 的驗證在 `closeOwnTab` 之後，卡住時連留給人看的分頁都沒有（R1 verify 第 51 則）。一般 PDF 的 `pdftotext -l 2` 在毫秒到秒的量級。
    static let popplerTimeout: TimeInterval = 120

    static func run(_ argv: [String], stdin: Data? = nil, environment: [String: String]? = nil, timeout: TimeInterval? = nil) throws -> Result {
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
        // `env` 用 exec 取代自己，所以 `p` 就是那個外部命令；逾時先 SIGTERM，兩秒後還在就 SIGKILL（只殺自己啟動的那個 pid）
        var watchdog: DispatchWorkItem?
        if let timeout {
            let pid = p.processIdentifier
            let item = DispatchWorkItem {
                guard p.isRunning else { return }
                outBox.timedOut = true
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(pid, SIGKILL) } }
            }
            watchdog = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
        p.waitUntilExit()
        watchdog?.cancel()
        group.wait()
        if outBox.timedOut {
            throw SkillToolError.failure("\(displaySafeInvisible(argv.first ?? "", max: 80)) 逾時（\(Int(timeout ?? 0)) 秒），已中止")   // display-safe-exempt: timeout：Double 轉 Int 的秒數
        }
        if p.terminationStatus == 127, errBox.data.starts(with: Data("env:".utf8)) {
            throw SkillToolError.failure("找不到命令 \(displaySafeInvisible(argv.first ?? "", max: 80))（不在 PATH 上）")
        }
        return Result(status: p.terminationStatus, stdout: outBox.data, stderr: errBox.data)
    }
}
