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
            Migrate.self, ExportTables.self, ImportWoS.self, BootstrapPeople.self,
            ResolveDivergence.self, RecordDivergence.self, AuthorizeNames.self,
            Fmt.self,
        ])
}

/// library root 解析：--library flag → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// 全 config 驅動，無寫死個人路徑（發布餘地）。
struct LibraryOptions: ParsableArguments {
    @Option(name: .long, help: "library root（預設 $AKASHIC_LIBRARY 或 ~/.akashic/config.yaml 的 library:）")
    var library: String?

    /// 開 library，佈局不存在就建（`doctor` / `import-zotero` 用）。
    ///
    /// **必須經由這裡，不要自己 `LibraryStore(root:)`**（#101）。它與 `openStore()` 的
    /// 差別只在「不存在就建」vs「不存在就拒絕」，兩者都保留 registry key。
    ///
    /// 曾經有一個 `resolveRoot()` 只回傳 root，而它的**兩個呼叫點都因此丟掉了 key**：
    /// `doctor` 與 `import-zotero` 於是把已註冊 store 當成未註冊的，替它建一個永遠用
    /// 不到的 in-store `.akashic/`，並且**重建錯的那個 index**——`~/.akashic/index/
    /// <key>.sqlite` 從來沒被 `doctor` 更新過。少一個丟得掉 key 的入口，比修兩個呼叫點
    /// 更可靠。
    func openOrCreateStore() throws -> LibraryStore {
        let r = try resolved()
        let store = LibraryStore(root: r.root, key: r.key)
        try store.ensureLayout()
        return store
    }

    /// #37：index 位置取決於 registry key，所以解析要保留 key 而不只是 root。
    func resolved() throws -> LibraryLocator.Resolved {
        do {
            return try LibraryLocator.resolveDetailed(explicit: library)
        } catch {
            throw ValidationError((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// 開既有 library；不自動建立。
    ///
    /// **#35：兩種佈局都算數。** 判準原本只看 `entries/`，format 2 的 store 沒有那個
    /// 目錄——遷移完成後每個指令都會說「這不是 Akashic library」。
    func openStore() throws -> LibraryStore {
        let r = try resolved()
        let root = r.root
        let store = LibraryStore(root: root, key: r.key)
        let fm = FileManager.default
        guard fm.fileExists(atPath: store.entitiesDir.path)
                || fm.fileExists(atPath: store.entriesDir.path) else {
            throw ValidationError("『\(root.path)』不是 Akashic library（缺 entities/ 與 entries/）。先跑 akashic doctor --library <path> 建立佈局。")
        }
        // **refuse-if-newer 的 choke point**（#115）。`StoreVersion.check` 曾只在
        // `load()` 被呼叫——凡不經 load() 的路徑全部繞過：`fmt` 的全庫
        // read-modify-write 在 format 太新的 store 上照改寫 exit 0（#112 DA 實測，
        // 用本 binary 的舊語意改寫較新格式的記錄）、`library create` 對 malformed
        // marker 照走。修在這裡讓**全部** CLI 指令（現在與未來的）一次涵蓋；
        // 與 load() 內的 check 冗餘無害（冪等讀 marker）。read-only 指令同受閘——
        // 按舊語意誤讀，讀跟寫一樣危險。`openOrCreateStore` 由 #106 的 strict
        // ensureLayout 保護，不再重複。
        try StoreVersion.check(root: root)
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
