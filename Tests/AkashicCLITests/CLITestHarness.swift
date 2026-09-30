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
        try launch(executable: productsDirectory.appendingPathComponent("akashic"), arguments: args,
                   environment: childEnvironment(args, env: env))
    }

    /// 同 `run`，但經 `/usr/bin/time -l` 跑，另回子行程的尖峰 RSS（bytes，`maximum resident set size`）。#703 R1：記憶體的界要量
    /// 真 binary——測試行程自己的 heap 與 XCTest 每支測試外包的 autorelease pool 都會讓行程內量測失真，子行程的 `ru_maxrss` 只屬於它自己。
    /// 環境與 `run` 同一份（`childEnvironment`）。輸出裡找不到那一行就擲錯（量不到不等於量到 0）。
    static func runMeasuringPeakRSS(_ args: [String], env: [String: String]) throws
        -> (status: Int32, output: String, peakRSS: Int) {
        let r = try launch(executable: URL(fileURLWithPath: "/usr/bin/time"),
                           arguments: ["-l", productsDirectory.appendingPathComponent("akashic").path] + args,
                           environment: childEnvironment(args, env: env))
        guard let m = r.output.range(of: #"(\d+)\s+maximum resident set size"#, options: .regularExpression),
              let n = Int(r.output[m].prefix { $0.isNumber }) else {
            throw NSError(domain: "CLITestHarness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "/usr/bin/time -l 的輸出裡沒有 maximum resident set size：\(r.output.suffix(2_000))"])
        }
        return (r.status, r.output, n)
    }

    /// 子行程的環境（`run` 與 `runMeasuringPeakRSS` 共用——同一保護只有一個入口）。
    private static func childEnvironment(_ args: [String], env: [String: String]) -> [String: String] {
        var childEnv = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        for (k, v) in env { childEnv[k] = v }
        // #664：`s2` 呼叫沒指定就補上測試用的 keychain service 與暫存狀態目錄——一個忘了設
        // 覆寫的測試最壞只會以結束碼 3 結束，不會讀到開發機上真的金鑰、也不會連到真的 S2。
        if args.first == "s2" {
            if childEnv["AKASHIC_S2_KEYCHAIN_SERVICE"] == nil {
                childEnv["AKASHIC_S2_KEYCHAIN_SERVICE"] = "akashic-test-harness"
            }
            if childEnv["AKASHIC_S2_STATE_DIR"] == nil {
                childEnv["AKASHIC_S2_STATE_DIR"] = NSTemporaryDirectory() + "akashic-s2-harness"
            }
        }
        return childEnv
    }

    private static func launch(executable: URL, arguments: [String], environment: [String: String]) throws
        -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
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
