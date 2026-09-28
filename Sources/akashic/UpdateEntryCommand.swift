import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// work（entry）的部分更新（`update-entry`）——MCP `akashic_update_entry` 的 CLI 面，兩面同一個 `AkashicService.updateEntry`。
///
/// 契約寫在 service（`EntryUpdate.swift` 的檔頭），這裡不複製一份會分岔的副本。CLI 面只有三個自己的決定：
/// 1. **預設乾跑**，`--apply` 才寫；`--apply` 走 #298 的目標確認閘（`WriteGateRulings` 的 `update-entry` 格）。
/// 2. 寫入面封閉例外形：只印 service payload，不設 `--json`、沒有人可讀分支（`mcp-cli-parity` 的既有裁決）。
/// 3. 只看參數的檢查在 `validate()`、早於開 store（#654 的形）。
struct UpdateEntryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-entry",
        abstract: "work 的部分更新（預設乾跑，--apply 才寫）：--remove-field 移除 fields 的值（#544）、--add-source 宣告已存的內容是這篇的副本（#614）；兩者各自單獨呼叫")

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
                             + "（要刪用 resolve-venues --drop-venue）；主來源是 Zotero 的記錄另附 zoteroNote（#544）"))
    var removeField: [String] = []

    @Option(name: .customLong("add-source"), parsing: .upToNextOption,
            help: ArgumentHelp("宣告已存進 sources/ 的內容是這篇作品的副本（可多個 digest，sha256: 加 64 個小寫十六進位，0 byte 內容的 digest 拒收；寫進 akashic.sources，"
                             + "store-format §2.4.1）。每個新加的 digest 都要已經在本機的 sources/、而且 sources/index.jsonl 有它的取得記錄"
                             + "（先用 store-source 存）——本機沒有、孤兒 blob、shard 讀不到、index 壞到判不出來，都整批拒絕、零寫入。"
                             + "add-only、冪等：已在的列在 sourcesAlreadyPresent，沒有新東西就不寫。報告逐個帶 index 的取得記錄"
                             + "（origin、mediaType、note…），乾跑時用來確認是哪份內容。空內容的 digest、同一次重複、一次超過 200 個都拒絕。"
                             + "不與 --remove-field 組合（#614）"))
    var addSource: [String] = []

    @Flag(name: .long, help: "實際寫入（預設只列出會做什麼）")
    var apply = false

    func validate() throws {
        try argvCheck { try AkashicService.checkUpdateEntryArguments(removeFields: removeField, addSources: addSource) }
    }

    func run() throws {
        if apply { try options.assertDestructiveTargetNamed("update-entry") }
        let store = try options.openStore()
        // `key:` 必帶（#220 HIGH）：漏掉會讓已註冊的 store 被當成 keyless 而長出第二份 index
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateEntry(citekey: citekey, removeFields: removeField, addSources: addSource, dryRun: !apply))
    }
}
