import Foundation
import XCTest

/// 跑**真的 `akashic` binary** 並捕捉 stdout（#171 verify 171-1）。
///
/// ## 為什麼需要它
///
/// `ExportSanitisationTests` 原本測的是 `displaySafeMultiline(...)` **在測試裡自己
/// 呼叫**的行為，從未經過被修的呼叫點。席位的 mutation 證明了後果：把 #165 的
/// 兩處修法整個還原，1014 條測試**一條都不紅**——那個測試檔量的是一個 PR 之前
/// 就已經正確的 library function。
///
/// CLI 的分支寫在 `ExportBib.run()` 裡（`if let output { 寫檔 } else { print }`），
/// 沒有可直呼的接縫。把它抽成 `func stdoutRendering(_ s: String) -> String` 再測，
/// 得到的是一個同義反覆的測試——**它會綠，但它證明不了 `print` 那一行真的呼叫了
/// 它**。唯一能證明的方式是跑真的 binary 看真的 stdout。
///
/// 這與本 repo 已經記過的教訓同源：747 條全綠仍漏掉兩個 MCP 入口，要用 stdio
/// 驅動真 binary 才現形。
enum CLIFixture {

    /// 測試 bundle 旁邊就是 `.build/<config>/` 的產物目錄。
    static var binary: URL {
        Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("akashic")
    }

    /// binary 不存在時應 **skip 而非 fail**——`swift test` 不保證先建 executable
    /// target，把環境問題報成測試失敗會製造假紅。但**存在時必須真的跑**。
    static func requireBinary() throws {
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("找不到 akashic binary（\(binary.path)）——先 `swift build`")
        }
    }

    struct Result { let status: Int32; let stdout: String; let stderr: String }

    static func run(_ args: [String], home: URL? = nil) -> Result {
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        if let home {
            var env = ProcessInfo.processInfo.environment
            // 絕不讓測試碰到真實的 `~/.akashic`
            env["AKASHIC_HOME"] = home.path
            env["HOME"] = home.path
            p.environment = env
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        // 大輸出要邊跑邊讀——pipe buffer 滿了會 deadlock（本 repo 的 96 KB
        // 上限註解提過同一個坑）。
        var outData = Data(), errData = Data()
        out.fileHandleForReading.readabilityHandler = { outData.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { errData.append($0.availableData) }
        do { try p.run() } catch { return Result(status: -1, stdout: "", stderr: "\(error)") }
        p.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        outData.append(out.fileHandleForReading.availableData)
        errData.append(err.fileHandleForReading.availableData)
        return Result(status: p.terminationStatus,
                      stdout: String(data: outData, encoding: .utf8) ?? "",
                      stderr: String(data: errData, encoding: .utf8) ?? "")
    }

    private final class BundleAnchor {}
}
