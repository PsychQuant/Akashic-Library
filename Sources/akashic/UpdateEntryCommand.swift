import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// work（entry）的部分更新（`update-entry`）——MCP `akashic_update_entry` 的 CLI 面，兩面同一個 `AkashicService.updateEntry`。
///
/// 契約寫在 service（`EntryUpdate.swift` 的檔頭），這裡不複製一份會分岔的副本。CLI 面只有三個自己的決定（三條腿——`--remove-field`、
/// `--add-source`、`--remove-zotero-source`——各自單獨呼叫，同一份決定）：
/// 1. **預設乾跑**，`--apply` 才寫；`--apply` 走 #298 的目標確認閘（`WriteGateRulings` 的 `update-entry` 格）。
/// 2. 寫入面封閉例外形：只印 service payload，不設 `--json`、沒有人可讀分支（`mcp-cli-parity` 的既有裁決）。
/// 3. 只看參數的檢查在 `validate()`、早於開 store（#654 的形）。
struct UpdateEntryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-entry",
        abstract: "work 的部分更新（預設乾跑，--apply 才寫）：--remove-field 移除 fields 的值（#544）、--add-source 宣告已存的內容是這篇的副本（#614）、--remove-zotero-source 移除記下的 Zotero 來源（#680）；三者各自單獨呼叫")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "citekey")
    var citekey: String

    @Option(name: .customLong("remove-field"), parsing: .upToNextOption,
            help: ArgumentHelp("移除 fields 的值（可多個）：<鍵>=理由。鍵要與 fields 現有的鍵逐字相符（先用 get-entry 看）。"
                             + "移除是判定（「這個值不是來源給這個欄位的資料」），理由必填、至多 4,096 位元組；理由只印在報告"
                             + "（fieldRemovals，全文），不寫進 store——要留在 git 就寫進 commit message。被移除的值在報告裡只印前 300 字"
                             + "與位元組數，全文在 git 的移除前副本裡，所以實跑要求這筆 work 的檔已在 git 裡 commit、乾淨。"
                             + "指向被移除鍵的 fields.<鍵> reference 一併刪除，逐鍵列筆數（referencesRemoved）。"
                             + "鍵不存在、同一鍵兩次、理由空白或過長、一次超過 200 個，都整批拒絕、零寫入。"
                             + "由被移除的值推導出來的 literal venue 邊不動、列在 venueEdgesFromRemovedValues"
                             + "（要刪用 resolve-venues --drop-venue）；已歸戶的 key 邊連同 venue 上的 confirmed verdict 也不動、"
                             + "列在 venueKeyEdgesFromRemovedValues（先 resolve-venues --demote 再 --drop-venue）。"
                             + "reintroductionNote 說明三條會把值補回來的路徑：import-wos 回填、enrich、Zotero pull"
                             + "（主來源是 Zotero 的記錄另附 zoteroNote）——store 不記得這個值被判定過不屬於這裡。"
                             + "移除 APA7 必要欄位時附 apa7RequiredNowMissing（export-bib 會印 ERROR，validate 不報）（#544）"))
    var removeField: [String] = []

    @Option(name: .customLong("add-source"), parsing: .upToNextOption,
            help: ArgumentHelp("宣告已存進 sources/ 的內容是這篇作品的副本（可多個 digest，sha256: 加 64 個小寫十六進位，0 byte 內容的 digest 拒收；寫進 akashic.sources，"
                             + "store-format §2.4.1）。每個新加的 digest 都要已經在本機的 sources/、而且 sources/index.jsonl 有它的取得記錄"
                             + "（先用 store-source 存）——本機沒有、孤兒 blob、shard 讀不到、index 壞到判不出來，都整批拒絕、零寫入。"
                             + "add-only、冪等：已在的列在 sourcesAlreadyPresent，沒有新東西就不寫。報告逐個帶 index 的取得記錄"
                             + "（origin、mediaType、note…；CLI 全列，MCP 面截 20 筆），乾跑時用來確認是哪份內容。空內容的 digest、同一次重複、"
                             + "一次超過 200 個、blob 的位置不是普通檔都拒絕。連好之後 get-entry 的 sources 看得到。"
                             + "沒有移除腿（#677）：連錯了以 git 還原那個 work 檔——本面不要求檔已 commit，連結前先 commit store。"
                             + "不與 --remove-field 組合（#614）"))
    var addSource: [String] = []

    @Option(name: .customLong("remove-zotero-source"), parsing: .upToNextOption,
            help: ArgumentHelp("移除這筆記下的 Zotero 來源（可多個）：<來源鍵>=理由。來源鍵是 <library_id>:<zotero_key>（如 5:GRP00001；先用 get-entry 看 provenance），"
                             + "沒記 library_id 的來源是 ?:<zotero_key>（validate 對「附加來源沒記 library_id」的警告給的就是這個鍵，#679）。"
                             + "主來源與附加來源都能移除；同一筆的主來源與附加來源是同一個來源時兩處都拿掉。"
                             + "移除是判定（「這個來源不屬於這一筆」），理由必填、至多 4,096 位元組；理由只印在報告（zoteroSourceRemovals，全文），不寫進 store——"
                             + "要留在 git 就寫進 commit message。被移除的來源只剩 git 的移除前副本，所以實跑要求這筆 work 的檔已在 git 裡 commit、乾淨。"
                             + "主來源移除而附加來源仍在時，附加來源不升格為主來源（升格會把書目欄位的改寫權交給另一個 library，同 App 的「與 Zotero 脫鉤」；"
                             + "primaryRemovedNote 說明）；連結狀態前後在 zoteroLinkState（intact／orphaned／additionalSourceOrphaned）。"
                             + "被移除的來源若在 Zotero 端仍有那個條目，下一次 import-zotero 會為它另建一筆新 entry（reimportNote）。"
                             + "這筆沒有的來源、同來源兩次、形狀錯、理由空白或過長、一次超過 200 個，都整批拒絕、零寫入（#680）"))
    var removeZoteroSource: [String] = []

    @Flag(name: .long, help: "實際寫入（預設只列出會做什麼）")
    var apply = false

    func validate() throws {
        try argvCheck {
            try AkashicService.checkUpdateEntryArguments(removeFields: removeField, addSources: addSource,
                                                         removeZoteroSources: removeZoteroSource)
        }
    }

    func run() throws {
        if apply { try options.assertDestructiveTargetNamed("update-entry") }
        let store = try options.openStore()
        // `key:` 必帶（#220 HIGH）：漏掉會讓已註冊的 store 被當成 keyless 而長出第二份 index
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateEntry(citekey: citekey, removeFields: removeField, addSources: addSource,
                                      removeZoteroSources: removeZoteroSource, dryRun: !apply,
                                      sourcesLimit: nil))   // CLI 全列（輸出進人的終端機）；MCP 面截 20 筆，理由見 `sourcesAddedCap`
    }
}
