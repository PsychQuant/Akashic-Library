import Foundation

@main
struct AkashicMCPMain {
    static func main() async {
        do {
            let server = try AkashicMCPServer()
            try await server.run()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("akashic-mcp 啟動失敗：\(message)\n".utf8))
            exit(1)
        }
    }
}
