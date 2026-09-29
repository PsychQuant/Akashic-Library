import Foundation
import AkashicCore

/// `safari-browser` 的一次呼叫（#629）：引數向量進、退出碼與 stdout／stderr 出。
///
/// 抓取編排（`FulltextFetch`）只透過這個介面碰瀏覽器，所以它的整條路徑——含中止條款的每個出口——可以在測試裡對一個記憶體內的
/// 假瀏覽器跑，不需要 Safari、不連網（舊實作的路徑測試是對一個 Python stub 跑同樣的事）。介面刻意貼著命令列：引數向量
/// 逐字就是 `safari-browser` 收到的那一串，「這支程式對瀏覽器說了什麼」是可以在測試裡逐條斷言的。
public protocol SafariBrowser {
    func run(_ args: [String]) -> SafariRun
}

public struct SafariRun {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public init(status: Int32, stdout: String = "", stderr: String = "") {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
    /// Shell 的 `$(…)` 會去掉尾端換行；抓取編排用的每個值都是那樣取的。
    public var value: String { stdout.trimmingTrailingNewlines() }
}

extension String {
    func trimmingTrailingNewlines() -> String {
        var s = Substring(self)
        while s.last == "\n" || s.last == "\r" { s = s.dropLast() }
        return String(s)
    }
}

/// 真的 `safari-browser`（或 `--bin` 指定的路徑）。
public struct ProcessSafariBrowser: SafariBrowser {
    public let executable: String

    public init(executable: String) { self.executable = executable }

    public func run(_ args: [String]) -> SafariRun {
        do {
            let r = try ToolRunner.run([executable] + args)
            return SafariRun(status: r.status, stdout: String(decoding: r.stdout, as: UTF8.self),
                             stderr: String(decoding: r.stderr, as: UTF8.self))
        } catch {
            return SafariRun(status: 127, stderr: displaySafeErrorText(error))
        }
    }

    /// `command -v "$BIN" || [ -x "$BIN" ]`：有斜線的當路徑檢查可執行，否則在 PATH 上找。
    public static func isAvailable(_ executable: String) -> Bool {
        let fm = FileManager.default
        if executable.contains("/") { return fm.isExecutableFile(atPath: executable) }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { fm.isExecutableFile(atPath: "\($0)/\(executable)") }
    }
}
