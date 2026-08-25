import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

@main
struct AkashicCLI: ParsableCommand {
    /// **ArgumentParser 頂層錯誤輸出的消毒 choke point**（#114）。
    ///
    /// throw 路徑的終點曾完全沒有消毒：errorDescription 內插的使用者可控內容
    /// （store.yaml 逐字行、config key、Yams 錯誤展開）原樣落地 stderr——
    /// #112 verify 實測 ESC/BEL 穿透、2 MB 行無上限。逐條補 error 站點是假性
    /// 閉合（DA 裁決）：新增的 case 又會裸奔。這裡取代合成的 main()，在唯一
    /// 出口統一過 displaySafeMultiline（help/usage 是多行合法輸出——單行版
    /// displaySafe 會跳脫 LF 並截 200 字，不能直接用）。exit code 語意不變
    /// （沿用 ArgumentParser 的 exitCode(for:)）。
    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch {
            let full = fullMessage(for: error)
            // #297 item 1：頂層用不跳脫反斜線的變體——否則帶合法反斜線的常量
            // （`StoreKey.pattern`）與已消毒片段的 `\u{...}` 都會被弄壞。
            // 終端安全不受影響（控制字元／bidi 等仍全部跳脫），理由見該函式 doc。
            let safe = displaySafeAssembled(full)
            if !safe.isEmpty {
                let code = exitCode(for: error)
                // help/CleanExit 走 stdout（exit 0 的訊息是輸出不是錯誤），其餘 stderr。
                // **try? 是必要的**（#135 verify F1）：Foundation 的非 throwing
                // write(_:) 在 fd 已關（1>&- / daemon 情境）時擲不可捕捉的
                // NSFileHandleOperationException——程序 abort（rc 134）而
                // ArgumentParser 原版對寫入失敗是靜默忽略。EPIPE 兩者行為相同
                // （SIGPIPE），只有 EBADF 有差。
                let handle: FileHandle = code == .success ? .standardOutput : .standardError
                try? handle.write(contentsOf: Data((safe + "\n").utf8))
            }
            // 註：合成版 main 的 DEBUG async-misuse 檢查（failAsyncPlatform）未搬——
            // 本 CLI 無 AsyncParsableCommand；若未來加入 async 子命令需一併補回。
            Foundation.exit(exitCode(for: error).rawValue)
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "akashic",
        abstract: "Akashic-Library — 檔案為本的文獻整合系統",
        subcommands: [
            ImportZotero.self, Validate.self, ExportBib.self,
            ResolvePeople.self, Doctor.self, Query.self, Graph.self, Rename.self, RenamePerson.self, LibraryCmd.self, FileCmd.self,
            Migrate.self, MigrateProvenance.self, MigratePersonIdentity.self,
            ExportTables.self, ImportWoS.self, BootstrapPeople.self,
            ResolveDivergence.self, RecordDivergence.self, AuthorizeNames.self,
            BootstrapOrganizations.self, ResolveOrganizations.self,
            BootstrapVenues.self,
            EnrichFromZotero.self,   // #340：逐筆補值（add-only；與 pull 語意刻意不同）
            UpdatePersonCmd.self,
            Fmt.self, ViewCmd.self, CreateEntryCmd.self,
            PersonCmd.self,   // #218：person 的讀取面（寫入面是上面的 UpdatePersonCmd）
            // #219：parity 家族其餘五格——讀取聚合 ×2 + 關係／狀態寫入 ×3
            PeopleCmd.self, GetEntryCmd.self,
            LinkCmd.self, TagCmd.self, SetStatusCmd.self,
            AddPersonCmd.self,
        StoreSourceCmd.self, DivergencesCmd.self,
            // #304：venue 四能力（讀取 ×2 + 建檔 + 消歧）＋ migrate-venues；
            // MCP 對應面在同一 change 落表（mcp-cli-parity）
            VenueCmd.self, VenuesCmd.self, AddVenueCmd.self, UpdateVenueCmd.self, ResolveVenuesCmd.self,
            MigrateVenues.self,
        MigrateIdentifiers.self,
        ])
}

/// library root 解析：--library flag → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// 全 config 驅動，無寫死個人路徑（發布餘地）。
struct LibraryOptions: ParsableArguments {
    // #315：「library」在本專案承載三義，而**最危險的一對就在這裡與 MCP 之間**：
    // 這個旗標是「開哪個 store」（檔案系統路徑），MCP 的同名參數是「在這個 store 裡篩
    // 哪個 membership 分類」（`StoreKey`）。同名、鄰接、不同型別、不同語意，而**錯用
    // 不會報錯**——只會 scope 到錯的東西，然後回一個看起來完全合理的子集。
    //
    // help 文字因此明寫它**不是**什麼。這是 #315 的 option (2)（零成本下限）；改名
    // （option 1）需要裁決，而裁決本身有一個反直覺的方向：store 自己的目錄叫
    // `libraries/`，所以 membership 那個意思才是 store 的原生詞彙——**本旗標才是異類**。
    @Option(name: .long, help: """
        store root 路徑（預設 $AKASHIC_LIBRARY 或 ~/.akashic/config.yaml 的 library:）。        **不是** membership 分類——那是 MCP tool 的同名參數（見 #315）
        """)
    var library: String?

    /// 破壞性 `--apply` 的知情同意（#298）。
    ///
    /// 語意**不是**「跳過確認」而是「**我已確認目標就是 registry 解析到的那個**」
    /// ——它的安全性來自拒絕訊息**先說出了目標**，使用者是看過之後才加上它的。
    @Flag(name: .long,
          help: "破壞性 --apply 專用：我已確認目標是 registry 解析到的那個 store（未指定 --library 時必須）")
    var yes = false

    /// 破壞性寫入前的目標確認（#298）。**只在真的要寫時呼叫**——dry-run 不得被擋。
    ///
    /// 2026-08-16 的事故：在 scratch 目錄執行無 `--library` 的 `--apply`，解析循
    /// registry 打到真 store，867 個 person 檔被改名重發 id。核心不是解析錯了，是
    /// **呼叫者以為自己在 scratch**，而沒有任何東西告訴他。
    func assertDestructiveTargetNamed(_ command: String) throws {
        try DestructiveTargetGate.assertTargetNamed(
            command: command, explicitLibrary: library, yes: yes,
            resolved: try resolved().root)
    }

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
        // **version check 先於佈局檢查**（#134 verify F1）：refuse-if-newer 的存在
        // 理由正是「未來的 format 可能改目錄結構」（format 2 的 entries→entities
        // 就是先例）——若 layout guard 先跑，一個把目錄改名的 v7 store 會被告知
        // 「不是 Akashic library、先跑 doctor 建佈局」：診斷錯、指路也錯。
        try StoreVersion.check(root: root)
        let fm = FileManager.default
        guard fm.fileExists(atPath: store.entitiesDir.path)
                || fm.fileExists(atPath: store.entriesDir.path) else {
            throw ValidationError("『\(root.path)』不是 Akashic library（缺 entities/ 與 entries/）。先跑 akashic doctor --library <path> 建立佈局。")
        }
        // 上面的 StoreVersion.check 即 refuse-if-newer 的 choke point（#115）：
        // 曾只在 load() 被呼叫——凡不經 load() 的路徑全部繞過（fmt 的全庫
        // read-modify-write 在 format 太新的 store 上照改寫 exit 0，#112 DA 實測；
        // library create 對 malformed marker 照走）。放 openStore 讓全部 CLI 指令
        // 一次涵蓋；與 load() 內的 check 冗餘無害。openOrCreateStore 由 #106 的
        // strict ensureLayout 保護，不重複。
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
