import Foundation
import AkashicCore

@main
struct AkashicMCPMain {
    static func main() async {
        do {
            let server = try AkashicMCPServer()
            try await server.run()
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data((displaySafeErrorMultiline(error, prefix: "akashic-mcp 啟動失敗：") + "\n").utf8))
            exit(1)
        }
    }
}
