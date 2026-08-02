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
            ResolvePeople.self, Doctor.self, Query.self, Graph.self, Rename.self, LibraryCmd.self, FileCmd.self,
        ])
}

/// library root 解析：--library flag → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// 全 config 驅動，無寫死個人路徑（發布餘地）。
struct LibraryOptions: ParsableArguments {
    @Option(name: .long, help: "library root（預設 $AKASHIC_LIBRARY 或 ~/.akashic/config.yaml 的 library:）")
    var library: String?

    func resolveRoot() throws -> URL {
        try resolved().root
    }

    /// #37：index 位置取決於 registry key，所以解析要保留 key 而不只是 root。
    func resolved() throws -> LibraryLocator.Resolved {
        do {
            return try LibraryLocator.resolveDetailed(explicit: library)
        } catch {
            throw ValidationError((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// 開既有 library（entries/ 必須存在）；不自動建立。
    func openStore() throws -> LibraryStore {
        let r = try resolved()
        let root = r.root
        let store = LibraryStore(root: root, key: r.key)
        guard FileManager.default.fileExists(atPath: store.entriesDir.path) else {
            throw ValidationError("『\(root.path)』不是 Akashic library（缺 entries/）。先跑 akashic doctor --library <path> 建立佈局。")
        }
        return store
    }
}

extension LibraryLoad {
    /// 人類可讀的 quarantine 報告行。
    /// R11（R10-verify M18/M19）：reason 是 Yams 展開的**逐字檔案內容**、
    /// 不截斷且可含 double-quoted scalar 解碼出的真 ESC——經 displaySafe
    /// 消毒後才進 stdout（未消毒時可清螢幕並在報告裡偽造統計行）。
    var quarantineLines: [String] {
        quarantined.map { "  ✗ \(displaySafe($0.file, max: 200)) — \(displaySafe($0.reason, max: 512))" }
    }
}
