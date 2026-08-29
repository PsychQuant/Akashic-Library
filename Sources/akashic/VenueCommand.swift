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
        // **異寫法與權威形分開顯示**（#422）——在此之前它們混在 names 的時間軸裡，
        // 而讀的人以為拿到時間序。值取自 service（已 displaySafe），原樣轉印。
        if let vari = obj["variant"] as? [String], !vari.isEmpty {
            print("  variant：\(vari.joined(separator: "；"))")   // display-safe-exempt: 值取自 AkashicService.venue（已逐欄位 displaySafe），二次消毒非冪等
        }
        // **三態**（#406）：印 true／false，缺席**什麼都不印**——那是「尚未判定」，
        // 而印「未判定」會讓它看起來像一個已經查過的結論。
        if let p = obj["paginated"] as? Bool {
            print("  paginated：\(p ? "是（本刊使用頁碼）" : "否（article number 制）")")   // display-safe-exempt: 編譯期常量
        }
        if let issn = obj["issn"] as? [[String: Any]], !issn.isEmpty {
            let rendered = issn.map { one -> String in
                let v = one["value"] as? String ?? "?"
                if let m = one["medium"] as? String { return "\(v)（\(m)）" }
                return v
            }
            print("  ISSN：\(rendered.joined(separator: "、"))")   // display-safe-exempt: service 已逐值消毒（40），displaySafe 不冪等
        }
        if let note = obj["note"] as? String { print("  note：\(note)") }
        if let vs = obj["verdicts"] as? [[String: Any]], !vs.isEmpty {
            print("  歸戶判定（\(vs.count)）：")
            for v in vs {
                let kind = v["kind"] as? String ?? "?"
                let state = v["state"] as? String ?? "?"
                let lit = v["literal"] as? String ?? "?"
                let holder = v["holder"] as? String ?? "?"
                print("    [\(kind)/\(state)] 「\(lit)」← \(holder)")   // display-safe-exempt: service 已逐欄位消毒，displaySafe 不冪等
            }
        }
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
        abstract: "建發表載體實體（type 值域：\(VenueType.domainDescription)；需 store format ≥ 11）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "kebab-case venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption, help: "名稱變體（可多個）")
    var names: [String]

    @Option(name: .long, help: "\(VenueType.domainDescription)")
    var type: String

    @Option(name: .long, help: "備註（選填）")
    var note: String?

    /// #394：建檔時就知道 ISSN 是常見的。少了它得「先建再更新」——一次操作變兩次，
    /// 中間有一個 ISSN 不在的狀態。不合法即整個拒絕、零寫入；相等看正規形。
    @Option(name: .long, parsing: .upToNextOption,
            help: "ISSN（可多個；print 與 electronic 是兩個真的號。不合法即整批拒絕）")
    var issn: [String] = []

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.addVenue(key: key, names: names, type: type, note: note,
                                   issn: issn.isEmpty ? nil : issn))
    }
}

struct UpdateVenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-venue",
        abstract: "venue 的部分更新（#306／#394）——append 語意：--add-name 與 --add-issn 只附加不重複的值（整組替換刻意不提供）；--note／--type 替換")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "既有 venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption, help: "要附加的名稱變體（可多個；重複自動略過）")
    var addName: [String] = []

    @Option(name: .long, help: "備註（替換；選填）")
    var note: String?

    @Option(name: .long, help: "\(VenueType.domainDescription)（替換；選填）")
    var type: String?

    /// **append 語意，與 `--add-name` 一致**（#394）。ISSN 本來就是清單——print 與
    /// electronic 是兩個真的號。相等看正規形；任一個不合法即整個呼叫拒絕、零寫入。
    @Option(name: .customLong("add-issn"), parsing: .upToNextOption,
            help: "要附加的 ISSN（可多個；正規形相同者自動略過，不合法即整批拒絕）")
    var addISSN: [String] = []

    /// #406：「本刊是否使用頁碼」的**判定**。判定要留 verdict 與證據
    /// （`identity-is-judged-not-matched`），所以設它必附 `--judgement` 與
    /// `--rests-on`（缺任一即整個呼叫拒絕、零寫入）。`nil` 是誠實的未判定狀態，
    /// 不得折成任何預設值——floor 檢查對 nil 照報缺 pages。
    @Option(name: .long,
            help: "「本刊是否使用頁碼」的判定：true＝傳統頁碼刊、false＝article-number 制。必附 --judgement 與 --rests-on（#406）")
    var paginated: Bool?

    @Option(name: .long, help: "paginated 判定的理由（設 --paginated 時必填）")
    var judgement: String?

    @Option(name: .customLong("rests-on"), parsing: .upToNextOption,
            help: "判定所依據的證據 digest（sha256:64hex，至少一個——先用 store-source 存證據拿 digest）")
    var restsOn: [String] = []

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateVenue(key: key,
                                      addNames: addName.isEmpty ? nil : addName,
                                      note: note, type: type,
                                      addISSN: addISSN.isEmpty ? nil : addISSN,
                                      paginated: paginated, judgement: judgement,
                                      restsOn: restsOn.isEmpty ? nil : restsOn))
    }
}

/// `names` 的異寫法搬進 `variant` 分割（#422，format 13 → 14）。
///
/// **CLI-only，維運例外**（`mcp-cli-parity` 的既有裁決形狀）：格式遷移不可逆、要求每個
/// 將被改寫的檔自身受 git 追蹤，而 MCP 的 LLM 消費者不是那個角色。
struct MigrateVenueVariants: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-venue-variants",
        abstract: "把 names 的異寫法搬進 variant 分割（#422；需另手動 bump format 至 14）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只預演；只改寫 git 追蹤中的檔）")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名——**只在 --apply 時**。
        if apply { try options.assertDestructiveTargetNamed("migrate-venue-variants") }
        let store = try options.openStore()
        print("目標 store：\(displaySafe(store.root.path, max: 300))")
        let report = try VenueVariantMigration.run(store: store, apply: apply)
        let prefix = apply ? "✓" : "（dry-run）"
        if report.planned.isEmpty && report.failed.isEmpty {
            print("沒有可分類的 venue——names 皆單筆、已分割、或帶時間（沿革不動）")
        } else {
            print("\(prefix) \(apply ? "已分類" : "將分類") \(report.planned.count) 筆"
                  + "；單一名字 \(report.singleName.count)、已分割 \(report.alreadyPartitioned.count)"
                  + "、帶時間（沿革，不動）\(report.hasTemporal.count)")
            // **逐筆印出來給人看**——若某一筆其實是沿革，這是唯一的攔截點。
            for p in report.planned.prefix(40) {
                let vs = p.variants.map { displaySafe($0, max: 120) }.joined(separator: "、")
                print("  \(displaySafe(p.key, max: 120)) → variant: \(vs)")
            }
            if report.planned.count > 40 { print("  …另 \(report.planned.count - 40) 筆") }
            if !report.failed.isEmpty {
                print("拒寫 \(report.failed.count) 筆（其餘照常；commit 後重跑——遷移是冪等的）：")
                for f in report.failed.prefix(20) {
                    print("  ⚠ \(displaySafe(f.key, max: 120))——\(displaySafe(f.reason, max: 300))")
                }
            }
        }
        if let next = VenueVariantMigration.nextStep(report: report, apply: apply) { print(next) }
    }
}

struct ResolveVenuesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-venues",
        abstract: "venue 解析：不帶參數列候選與歧義；--apply 升格 literal 為 key（寫 confirmed verdict）；--reject 否決（寫 rejected verdict）；--repoint 改指已歸戶的邊（兩側都寫 verdict）；--demote 退回 literal（原字串從 verdict 取回，#418）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, parsing: .upToNextOption,
            help: "要套用的候選 id（citekey:venueIndex）")
    var apply: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "要否決的候選 id（同形）——CLI 面維持分兩次呼叫（互動面天然序列；組合腿是 MCP 的 LLM 批次需求，#272 同裁決）")
    var reject: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "把已歸戶的邊改指到另一個 venue（citekey:venueIndex:newKey）——歸錯戶的退路，#418")
    var repoint: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "把誤升的邊退回 literal（citekey:venueIndex）——原字串從 verdict 取回，無損，#418")
    var demote: [String] = []

    func run() throws {
        // CLI 契約同 resolve-people：apply 與 reject 分兩次呼叫
        if !apply.isEmpty, !reject.isEmpty {
            throw ValidationError("--apply 與 --reject 請分兩次呼叫（組合腿是 MCP 面的契約差異，見 mcp-cli-parity）")
        }
        // **`--repoint` 不與另外兩者組合**：它們解的是不同階段的問題（升格 vs 修正
        // 已升格的），混在一次呼叫裡會讓「哪一批寫了、哪一批沒寫」難以判讀，而改指
        // 本來就是在修一個錯誤——它最需要的是清楚的失敗語意（#418）。
        // **修正類的兩個旗標都單獨呼叫**：它們修的是已歸戶的邊，與升格／否決不同階段，
        // 而混在一次呼叫會讓「哪一批寫了」難以判讀（#418）。
        let fixers = [("--repoint", repoint), ("--demote", demote)].filter { !$0.1.isEmpty }
        if let f = fixers.first, fixers.count > 1 || !apply.isEmpty || !reject.isEmpty {
            throw ValidationError("\(f.0) 請單獨呼叫（它修的是已歸戶的邊，與升格／否決不同階段）")
        }
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.resolveVenues(apply: apply.isEmpty ? nil : apply,
                                        reject: reject.isEmpty ? nil : reject,
                                        repoint: repoint.isEmpty ? nil : repoint,
                                        demote: demote.isEmpty ? nil : demote))
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
