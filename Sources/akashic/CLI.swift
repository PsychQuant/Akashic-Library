import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

@main
struct AkashicCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "akashic",
        abstract: "Akashic-Library — 檔案為本的文獻整合系統（Phase 1）",
        subcommands: [
            ImportZotero.self, Validate.self, ExportBib.self,
            ResolvePeople.self, Doctor.self, Query.self, Graph.self,
        ])
}

/// library root 解析：--library flag → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// 全 config 驅動，無寫死個人路徑（發布餘地）。
struct LibraryOptions: ParsableArguments {
    @Option(name: .long, help: "library root（預設 $AKASHIC_LIBRARY 或 ~/.akashic/config.yaml 的 library:）")
    var library: String?

    func resolveRoot() throws -> URL {
        if let explicit = library {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        if let env = ProcessInfo.processInfo.environment["AKASHIC_LIBRARY"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/config.yaml")
        if let content = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "library" {
                    let path = parts[1].trimmingCharacters(in: .whitespaces)
                    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                }
            }
        }
        throw ValidationError("""
        找不到 library root。三選一：
          1) --library <path>
          2) export AKASHIC_LIBRARY=<path>
          3) ~/.akashic/config.yaml 寫入「library: <path>」
        """)
    }

    /// 開既有 library（entries/ 必須存在）；不自動建立。
    func openStore() throws -> LibraryStore {
        let root = try resolveRoot()
        let store = LibraryStore(root: root)
        guard FileManager.default.fileExists(atPath: store.entriesDir.path) else {
            throw ValidationError("『\(root.path)』不是 Akashic library（缺 entries/）。先跑 akashic doctor --library <path> 建立佈局。")
        }
        return store
    }
}

extension LibraryLoad {
    /// 人類可讀的 quarantine 報告行。
    var quarantineLines: [String] {
        quarantined.map { "  ✗ \($0.file) — \($0.reason)" }
    }
}
