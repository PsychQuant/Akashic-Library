import Foundation
import AkashicCore

@main
struct AkashicMCPMain {
    static func main() async {
        do {
            let server = try AkashicMCPServer()
            try await server.run()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            try? FileHandle.standardError.write(contentsOf: Data("akashic-mcp 啟動失敗：\(displaySafeMultiline(message))\n".utf8))
            exit(1)
        }
    }
}
