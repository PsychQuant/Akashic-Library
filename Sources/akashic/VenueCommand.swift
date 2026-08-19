import ArgumentParser
import Foundation
import AkashicMCPKit
import AkashicCore
import AkashicStoreIO

/// venue 的 CLI 面（#304）。四個 subcommand 與 MCP 的
/// `akashic_venue`／`akashic_venues`／`akashic_add_venue`／`akashic_resolve_venues`
/// 落到 **同一個 `AkashicService` 函式**（entity-backlink 執行細節 2：一個讀取面
/// 只有一條實作路徑）。讀取面 `--json` 原樣轉印＋人可讀同源；寫入面是封閉例外形
/// （只回 service payload——mcp-cli-parity 的既有裁決）。

struct VenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "venue",
        abstract: "看一個發表載體：記錄 + 刊名沿革 + 文章編年 list（編年由反向邊算出，不存在記錄裡）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "venue key")
    var key: String

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_venue 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        // `key:` 不可省——同 PersonCmd 的 #220 教訓（keyless store 會分岔出第二份 index）
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.venue(key: key)
        if json { print(payload); return }
        try Self.render(payload)
    }

    /// 人可讀輸出。輸入是 service 回應（已逐欄位 displaySafe——本函式不從 store
    /// 另讀任何東西，且 `displaySafe` 不冪等，故不再包一次；同 PersonCmd 的 exemption）。
    static func render(_ payload: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            print(payload); return
        }
        let key = obj["key"] as? String ?? "?"
        let type = obj["type"] as? String ?? "?"
        print("\(key)（\(type)）")
        if let names = obj["names"] as? [[String: Any]], !names.isEmpty {
            print("  沿革：")
            for n in names {
                var line = "    \(n["value"] as? String ?? "?")"
                var span: [String] = []
                if let s = n["start"] as? String { span.append("start \(s)") }
                if let e = n["end"] as? String { span.append("end \(e)") }
                if n["ended"] as? Bool == true { span.append("已結束（時點未知）") }
                if let a = n["attested"] as? [String], !a.isEmpty {
                    span.append("attested \(a.joined(separator: ","))")
                }
                if !span.isEmpty { line += "（\(span.joined(separator: "、"))）" }
                print(line)
            }
        }
        if let auth = obj["authorized"] as? [String], !auth.isEmpty {
            print("  authorized：\(auth.joined(separator: "；"))")
        }
        if let note = obj["note"] as? String { print("  note：\(note)") }
        let count = obj["workCount"] as? Int ?? 0
        print("")
        print("文章（\(count)，編年）")
        if let works = obj["works"] as? [[String: Any]] {
            for w in works {
                let year = (w["year"] as? Int).map(String.init) ?? "—"
                print("\(w["citekey"] as? String ?? "?")\t\(year)\t\(w["title"] as? String ?? "")")   // display-safe-exempt: service 已逐欄位消毒（citekey 200／title 500），displaySafe 不冪等
            }
        }
        if count == 0 { print("（零篇——這是結果，不是錯誤）") }
    }
}

struct VenuesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "venues",
        abstract: "列出全部發表載體（key / type / 顯示名 / 文章數）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_venues 相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.venues()
        if json { print(payload); return }
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let rows = obj["venues"] as? [[String: Any]] else {
            print(payload); return
        }
        for r in rows {
            print("\(r["key"] as? String ?? "?")\t\(r["type"] as? String ?? "?")\t" +
                  "\(r["name"] as? String ?? "?")\t\(r["workCount"] as? Int ?? 0)")
        }
        print("（\(rows.count) 個 venue）")
    }
}

struct AddVenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-venue",
        abstract: "建發表載體實體（type 封閉三值：journal / conference / publisher；需 store format ≥ 11）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "kebab-case venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption, help: "名稱變體（可多個）")
    var names: [String]

    @Option(name: .long, help: "journal | conference | publisher")
    var type: String

    @Option(name: .long, help: "備註（選填）")
    var note: String?

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.addVenue(key: key, names: names, type: type, note: note))
    }
}

struct UpdateVenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-venue",
        abstract: "venue 異名補寫（#306）——append 語意：--add-name 只附加不重複的異名（整組替換刻意不提供）；--note／--type 替換")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "既有 venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption, help: "要附加的名稱變體（可多個；重複自動略過）")
    var addName: [String] = []

    @Option(name: .long, help: "備註（替換；選填）")
    var note: String?

    @Option(name: .long, help: "journal | conference | publisher（替換；選填）")
    var type: String?

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateVenue(key: key,
                                      addNames: addName.isEmpty ? nil : addName,
                                      note: note, type: type))
    }
}

struct ResolveVenuesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-venues",
        abstract: "venue 解析：不帶參數列候選與歧義；--apply 升格 literal 為 key（寫 confirmed verdict）；--reject 否決（寫 rejected verdict）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, parsing: .upToNextOption,
            help: "要套用的候選 id（citekey:venueIndex）")
    var apply: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "要否決的候選 id（同形）——CLI 面維持分兩次呼叫（互動面天然序列；組合腿是 MCP 的 LLM 批次需求，#272 同裁決）")
    var reject: [String] = []

    func run() throws {
        // CLI 契約同 resolve-people：apply 與 reject 分兩次呼叫
        if !apply.isEmpty, !reject.isEmpty {
            throw ValidationError("--apply 與 --reject 請分兩次呼叫（組合腿是 MCP 面的契約差異，見 mcp-cli-parity）")
        }
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.resolveVenues(apply: apply.isEmpty ? nil : apply,
                                        reject: reject.isEmpty ? nil : reject))
    }
}

struct MigrateVenues: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-venues",
        abstract: "從書目字串欄位回填 entry 的 venues literal ref（#304；需另手動 bump format 至 11）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只預演；只改寫 git 追蹤中的檔）")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("migrate-venues") }
        let store = try options.openStore()
        // 同 migrate-person-identity 的席 A NEW-3 緩解：破壞性/批次遷移**先回顯目標**
        // ——LibraryLocator 對 CWD 零感知（registry current 決定目標）。
        print("目標 store：\(displaySafe(store.root.path, max: 300))")
        let report = try VenueMigration.run(store: store, apply: apply)
        let prefix = apply ? "✓" : "（dry-run）"
        if report.planned.isEmpty && report.skippedExisting.isEmpty && report.failed.isEmpty {
            print("沒有可回填的 entry——journaltitle／booktitle／publisher 皆無或已有 venues")
        } else {
            print("\(prefix) \(apply ? "已回填" : "將回填") \(report.planned.count) 筆"
                  + "，已有 venues（跳過）\(report.skippedExisting.count) 筆"
                  + "，無載體來源 \(report.noVenueSource.count) 筆")
            for k in report.planned.prefix(20) { print("  \(displaySafe(k, max: 200))") }
            if report.planned.count > 20 { print("  …另 \(report.planned.count - 20) 筆") }
            if !report.failed.isEmpty {
                print("拒寫 \(report.failed.count) 筆（其餘照常；commit 後重跑——遷移是冪等的）：")
                for f in report.failed.prefix(20) {
                    print("  ⚠ \(displaySafe(f.citekey, max: 200))——\(displaySafe(f.reason, max: 300))")
                }
            }
        }
        if let next = VenueMigration.nextStep(report: report, apply: apply) {
            print(next)
        }
    }
}
