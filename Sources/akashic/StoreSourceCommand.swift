import ArgumentParser
import Foundation
import AkashicCore
import AkashicMCPKit

/// 存一份 source 的位元組進 `sources/`（#264）。
///
/// `SourceStore.storeSource` 的寫入面防護在 #224 就完成了，但**全樹零 production
/// 呼叫端**——這個能力先前只有寫 Swift 的人做得到。與 #206 對匯入面的判準同形：
/// 能不能做，不該取決於使用者會不會寫 script。
///
/// ## 為什麼是讀取面的 `--json` 慣例，不是寫入面的封閉例外
///
/// `mcp-cli-parity` 的寫入面封閉例外（只回 service payload、無人可讀分支）是給
/// `link`／`tag`／`set-status` 那種「做完就好」的命令。本命令的 receipt 有四個欄位，
/// 其中 `discardedProvenance` 攜帶「你這份敘述沒被寫入」——**人需要看得懂**，所以走
/// 讀取面的慣例：`--json` 原樣轉印，人可讀分支從同一個 payload 渲染。
struct StoreSourceCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "store-source",
        abstract: "存一份 source 的位元組進 sources/（內容定址、冪等；#264）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "要存入的檔案路徑")
    var path: String

    @Option(name: .long, help: "內容的 media type，如 application/pdf")
    var mediaType: String

    @Option(name: .long, help: "**你何時取得**這份內容（ISO 8601）——非存入時間")
    var retrieved: String

    @Option(name: .long, help: "來源（URL 或可辨識的出處敘述）")
    var origin: String

    @Option(name: .long, help: "取得方式，如 browser-download / api / scan")
    var acquisition: String

    @Option(name: .long, help: "補充敘述（可選）")
    var note: String?

    @Flag(name: .long, help: "輸出 service 的 JSON payload 原樣")
    var json = false

    func run() throws {
        // 必填欄位、路徑可讀性、排除驗證全由 service 判——CLI 不重寫判準（否則兩處會分岔）
        //
        // **`key:` 必帶**（#220 HIGH）：漏掉會讓已註冊的 store 被當成 keyless 而長出
        // 第二份 index。`PersonCLITests.testEveryCLIServiceConstructionPassesRegistryKey`
        // 是這條的機械防線——本命令第一版就漏了，被它抓到。
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.storeSource(
            path: path, mediaType: mediaType, retrieved: retrieved,
            origin: origin, acquisition: acquisition, note: note)

        if json {
            print(payload)
            return
        }

        // 人可讀分支從**同一個 payload** 渲染——不重新查、不重新判斷。
        let obj = (try? JSONSerialization.jsonObject(with: Data(payload.utf8)))
            as? [String: Any] ?? [:]
        let digest = obj["digest"] as? String ?? "(未知)"
        let created = obj["indexEntryCreated"] as? Bool ?? false
        let excluded = obj["exclusionVerified"] as? Bool ?? false

        print("digest：\(digest)")   // display-safe-exempt: SHA-256 十六進位，由本 binary 計算
        print(created ? "✓ 已建立 index 條目" : "· index 條目早已存在（冪等，未重複寫入）")
        print(excluded ? "✓ 已確認排除於版控之外" : "⚠ 排除未經確認")

        // **丟棄必須可見**（`lossless-intake` 執行細節 3）。只在 JSON 裡多一個鍵不夠——
        // 人不會去讀 JSON，而「我剛才寫的那段敘述其實沒進去」正是最需要被看見的事。
        if let discarded = obj["discardedProvenance"] as? [String: Any] {
            print("")
            print("⚠ 你這次交來的敘述**沒有被寫入**（既有條目以先到為準）：")
            for key in ["mediaType", "retrieved", "origin", "acquisition", "note"] {
                if let v = discarded[key] as? String {
                    print("    \(key)：\(v)")   // display-safe-exempt: service 已對每個值 displaySafe
                }
            }
            print("  要改既有條目的敘述，本命令做不到——那是另一個動作。")
        }
    }
}
