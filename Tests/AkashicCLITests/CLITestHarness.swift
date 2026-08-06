import XCTest
import Foundation

/// CLI E2E 測試共用 harness（#110 verify：`runCLI` 曾被複製成三份，教訓註解沒跟過去
/// ——「同一保護兩個入口」正是 #101/#112 三次沙箱逃逸的形狀，收斂回單一入口）。
enum CLITestHarness {
    static var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    /// 跑 akashic binary。
    ///
    /// **一律先清掉所有 `AKASHIC_*` 再注入**（#101 verify R1/R2）：
    /// `LibraryLocator.resolveDetailed` 的順序是 explicit → `$AKASHIC_LIBRARY` → registry，
    /// 省略 `--library` 的測試在**有設該變數的開發機上**會跑去打使用者的真實 store。
    /// 剝除必須**無條件**（R2 抓到包在 `if let env` 裡的版本，不帶 env 的呼叫全裸）——
    /// 本 helper 的 `env` 刻意 non-optional，讓那個形狀連寫都寫不出來。
    /// 繼承父環境其餘變數（PATH 等）仍需要，故只剔除 `AKASHIC_*`。
    @discardableResult
    static func run(_ args: [String], env: [String: String]) throws
        -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic")
        process.arguments = args
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        process.environment = childEnv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // **先讀到 EOF、再 waitUntilExit**（#114）：反過來會 pipe 緩衝死鎖——
        // 輸出超過 pipe buffer（64 KB）時子程序 block 在 write、父程序 block 在
        // waitUntilExit 互等。既有測試輸出都小所以沒踩過；#114 的 2 MB 行測試
        // 第一個踩到。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
