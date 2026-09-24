import Foundation
import AkashicCore
import AkashicStoreIO

@main
struct AkashicMCPMain {
    static func main() async {
        // `--store-format`：印出編譯進去的 store format 後結束（#630）。發布腳本以此確認產物
        // 真的由當下的原始碼建出——v0.12.0 出貨的是兩週前的舊產物，而它沒有任何一道檢查會紅。
        if CommandLine.arguments.dropFirst().first == "--store-format" {
            print(StoreVersion.supported)
            return
        }
        do {
            let server = try AkashicMCPServer()
            try await server.run()
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data((displaySafeErrorMultiline(error, prefix: "akashic-mcp 啟動失敗：") + "\n").utf8))
            exit(1)
        }
    }
}
