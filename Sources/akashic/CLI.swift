import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

@main
struct AkashicCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "akashic",
        abstract: "Akashic-Library — 檔案為本的文獻整合系統",
        subcommands: [
            ImportZotero.self, Validate.self, ExportBib.self,
            ResolvePeople.self, Doctor.self, Query.self, Graph.self, Rename.self,
        ])
}

/// library root 解析：--library flag → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// 全 config 驅動，無寫死個人路徑（發布餘地）。
struct LibraryOptions: ParsableArguments {
    @Option(name: .long, help: "library root（預設 $AKASHIC_LIBRARY 或 ~/.akashic/config.yaml 的 library:）")
    var library: String?

    func resolveRoot() throws -> URL {
        do {
            return try LibraryLocator.resolve(explicit: library)
        } catch {
            throw ValidationError((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
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
