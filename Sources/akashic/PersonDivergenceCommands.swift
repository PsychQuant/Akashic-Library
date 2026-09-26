import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #250：parity 規則落地後的第一次演練——補掉最後兩個 MCP-only 格。
/// 與 MCP 同名 tool 共用同一個 `AkashicService` 函式（單一實作路徑，
/// #206 → #218 → #219 → #250 同一條裁決線）。

/// `add-person`——`akashic_add_person` 的 CLI 面（寫入面封閉例外形：只回
/// service payload，同 link／tag／set-status）。
///
/// 實證需求（#250 裁決理由）：#238 對 unkeyable 作者（CJK 名無唯一羅馬化）
/// 的處置是「請使用者指定 key 建 person」——那個動作在 CLI 上此前**不存在**
/// （`update-person` 不能建新、`bootstrap-people` 是批次）。
struct AddPersonCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-person",
        abstract: "新增單筆 person 記錄（key 已存在即拒；unkeyable 作者指定 key 的入口）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "person key（StoreKey 格式：小寫 ASCII 與連字號）")
    var key: String

    @Option(name: .long, parsing: .upToNextOption,
            help: "名字（可多個；#227 起全部進 variant——對外名字之後由 update-person 指定 authorized）")
    var name: [String]

    @Option(name: .long, help: "ORCID iD（可選）")
    var orcid: String?

    @Option(name: .long, help: "OpenAlex author ID（可選）")
    var openalex: String?

    func run() throws {
        // key 合法性、已存在拒絕、quarantined 檔保護全由 service 判——CLI 不重寫判準
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.addPerson(key: key, names: name, orcid: orcid, openalex: openalex))
    }
}

/// `divergences`——`akashic_divergences` 的 CLI 面（讀取面：`--json` 原樣轉印＋
/// 人可讀同源，照 `PersonCmd` 範式）。
///
/// #218 同形的裁決理由：CLI 能**寫** divergence（`record-divergence`／
/// `resolve-divergence`）卻不能**列**——能寫不能讀的格。
struct DivergencesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "divergences",
        abstract: "列出未決的同一性歧異記錄（記錄用 record-divergence、消解用 resolve-divergence）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_divergences 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.listDivergences()
        if json {
            print(payload)   // service 的輸出已 displaySafe，原樣轉印
            return
        }
        try Self.render(payload)
    }

    /// 把 service 的 JSON 排成人可讀。`internal` 供測試對照同一份 JSON 的兩種輸出。
    ///
    /// 不再 `displaySafe`：輸入是 `AkashicService.listDivergences()` 的回應，
    /// question／candidates 在 service 側已逐欄位消毒（`hasJudgement` 是布林、
    /// `shape` 是封閉列舉 rawValue）。逐行標 exempt marker 讓來源可見（同
    /// `PersonCmd.render` 的慣例）。
    static func render(_ payload: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8))
                as? [String: Any],
              let count = obj["count"] as? Int,
              let items = obj["divergences"] as? [[String: Any]] else {
            throw RuntimeFailure.state("service 回應不是預期形狀")
        }
        // **空集合要說出來**（entity-backlink 執行細節 4）：「零筆未決」是結果不是錯誤
        guard count > 0 else {
            print("（目前沒有未決的歧異記錄）")
            return
        }
        print("divergence（\(count)）")
        for d in items {
            print("")
            print("\((d["id"] as? String) ?? "?")")   // display-safe-exempt: 見本函式 doc（id 是 UUID 字串）
            print("  \((d["question"] as? String) ?? "")")   // display-safe-exempt: 見本函式 doc（service 已消毒）
            for c in d["candidates"] as? [[String: Any]] ?? [] {
                print("    - \((c["key"] as? String) ?? "?")（\((c["shape"] as? String) ?? "?")）")   // display-safe-exempt: 見本函式 doc（key 已消毒；shape 是封閉列舉）
            }
            if d["hasJudgement"] as? Bool == true {
                print("  （已附初步 judgement——內容見 --json）")
            }
        }
        print("")
        print("  消解：akashic resolve-divergence <id>（含合併與全庫改寫，需 tracked+clean）")
    }
}
