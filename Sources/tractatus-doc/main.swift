import ArgumentParser
import Foundation
import TractatusDocs

@main
struct TractatusDocCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tractatus-doc",
        abstract: "驗證並產生《邏輯哲學論》與 Akashic-Library 的逐條對照文件。",
        subcommands: [ValidateCommand.self, RenderCommand.self]
    )

    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let failure as TractatusValidationFailure {
            let message = (failure.errorDescription ?? "validation failed") + "\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            Foundation.exit(1)
        } catch {
            let code = exitCode(for: error)
            let message = fullMessage(for: error) + "\n"
            let handle: FileHandle = code == .success ? .standardOutput : .standardError
            try? handle.write(contentsOf: Data(message.utf8))
            Foundation.exit(code.rawValue)
        }
    }
}

private struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "離線驗證正典來源、逐條語料與專案證據。"
    )

    @Option(name: .long, help: "語料根目錄。")
    var root = "docs/tractatus"

    @Flag(name: .long, help: "建構期間允許缺卷或缺命題；其他錯誤仍會失敗。")
    var allowIncomplete = false

    mutating func run() throws {
        let summary = try TractatusDocuments.validate(
            root: URL(fileURLWithPath: root),
            allowIncomplete: allowIncomplete
        )
        print(summary)
    }
}

private struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "由 strict-valid YAML 產生決定性的四欄 Markdown。"
    )

    @Option(name: .long, help: "語料根目錄。")
    var root = "docs/tractatus"

    @Option(name: .long, help: "產生檔的路徑。")
    var output = "docs/tractatus/generated/tractatus-project-map.md"

    @Flag(name: .long, help: "只比對產生結果，不寫入檔案。")
    var check = false

    mutating func run() throws {
        let summary = try TractatusDocuments.render(
            root: URL(fileURLWithPath: root),
            output: URL(fileURLWithPath: output),
            check: check
        )
        print(summary)
    }
}
