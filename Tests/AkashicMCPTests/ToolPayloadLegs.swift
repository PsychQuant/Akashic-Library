import Foundation

/// 每條寫入腿都要有 payload 情境（#700，使用者 2026-09-30 裁決）——兩張封閉表。
///
/// 守衛（`ToolPayloadLegTests`）從兩個來源列舉「腿」：
/// 1. **CLI 的裁決表**（`Sources/akashic/WriteGateRulings.swift`）：每一個會寫 store 的命令、三個逐腿命令的每一條寫入腿。
///    命令與腿先照機械規則對到 MCP（命令 `update-venue` → 工具 `akashic_update_venue`、旗標 `--drop-venue` → 參數
///    `drop_venue`）；對不上的在 `commands`／`legs` 寫一列——對到哪一個 MCP 工具與參數值，或為什麼只有 CLI。
///    對到的 MCP 參數必須有情境宣告它（`PayloadScenario.params`），只寫理由不算。
/// 2. **MCP 工具的參數**（真 binary `tools/list` 的 `inputSchema.properties`）：每一個參數要有情境宣告它，或在
///    `unexercised` 寫一列理由。**這一半才擋得到 #675**：`update-venue` 在裁決表裡是命令層的一格（逐腿只做三個命令，
///    見 `WriteGateRulings.swift` 的誠實邊界），`edit_name_segment` 這條新腿在裁決表裡看不到，在 `tools/list` 裡看得到。
///
/// 兩張表都是封閉列舉：新的一列要寫出它自己的理由，不從鄰居類推。
enum ToolPayloadLegs {
    /// 一條寫入腿在 MCP 面的對應。
    enum MCPLeg: Equatable {
        /// 對到 MCP 工具；`parameter` 是必須有情境宣告的參數（可帶值，`action=create`），`nil`＝這個工具有情境即可。
        case tool(String, parameter: String?)
        /// 只有 CLI——字串是這一格的理由。
        case cliOnly(String)
    }

    /// 會寫 store、機械規則對不上的 CLI 命令（`commandRulings` 的 gated／notGated）。
    static let commands: [String: MCPLeg] = [
        "library create": .tool("akashic_libraries", parameter: "action=create"),
        "library add": .tool("akashic_libraries", parameter: "action=add"),
        "library remove": .tool("akashic_libraries", parameter: "action=remove"),
        "library set-kind": .tool("akashic_libraries", parameter: "action=set-kind"),
        "file add": .cliOnly("mcp-cli-parity CLI-only 表的 `file add`／`file remove` 列（#700 R1 verify 第 9 則補）：註冊與除名 store 是改 registry——部署層的名冊，"
                             + "與 `--config` 同一個理由；MCP 的 akashic_files 只收 list／use（use 只在名冊內切換 session、不改名冊）"),
        "migrate": .cliOnly("mcp-cli-parity CLI-only 表：格式遷移＝維運例外"),
        "migrate-provenance": .cliOnly("mcp-cli-parity CLI-only 表：格式遷移＝維運例外"),
        "migrate-person-identity": .cliOnly("mcp-cli-parity CLI-only 表：格式遷移＝維運例外，不可逆、要求工作樹乾淨的人工 pre-flight"),
        "migrate-identifiers": .cliOnly("mcp-cli-parity CLI-only 表：格式遷移＝維運例外，跨記錄搬動資料（work 的 issn 移到 venue）"),
        "migrate-venues": .cliOnly("mcp-cli-parity CLI-only 表：格式遷移＝維運例外，部署鏈屬操作者角色"),
        "repair-venue-names": .cliOnly("mcp-cli-parity CLI-only 表：改寫既有記錄、只剩 git 那一份原位元組，乾跑逐筆過目屬操作者角色（#575）"),
        "bootstrap-people": .cliOnly("mcp-cli-parity CLI-only 表：批次建檔屬操作者規模；單筆由 akashic_add_person 覆蓋"),
        "bootstrap-organizations": .cliOnly("mcp-cli-parity CLI-only 表：批次建檔屬操作者規模；單筆由 akashic_add_organization 覆蓋"),
        "bootstrap-venues": .cliOnly("mcp-cli-parity CLI-only 表：批次建檔屬操作者規模；單筆由 akashic_add_venue 覆蓋"),
        "copy-zotero-attachments": .cliOnly("mcp-cli-parity CLI-only 表：維運例外＋批次屬操作者規模（走訪 Zotero 的 storage/、要求檔已 commit，#606）"),
        "authorize-names": .cliOnly("mcp-cli-parity CLI-only 表：批次策展＝操作者規模"),
        "resolve-divergence": .cliOnly("mcp-cli-parity CLI-only 表：合併＋全庫改寫＋刪檔，不可逆、要逐筆過目與乾淨的工作樹"),
        "rename": .cliOnly("mcp-cli-parity CLI-only 表：高風險身分操作（citekey 遷移含 verdict value 重寫）＝維運例外"),
        "rename-person": .cliOnly("mcp-cli-parity CLI-only 表：同 rename，遷移面更大（authors、divergence 候選、三種 holder 的 verdict）"),
        "fmt": .cliOnly("mcp-cli-parity CLI-only 表：全庫改寫＝維運例外"),
    ]

    /// 三個逐腿命令裡、機械規則對不上的寫入腿（`legRulings` 的 gated／notGated）。命令 → 旗標 → 對應。
    /// 2026-09-30 的全部寫入腿都對得上（`--drop-author` → `drop_author`……），所以是空的；新腿對不上時在這裡加一列。
    static let legs: [String: [String: MCPLeg]] = [:]

    /// MCP 工具的參數裡、**沒有**情境宣告的（工具 → 參數 → 理由）。有情境宣告的參數不得再列（列了即紅：過期）。
    static let unexercised: [String: [String: String]] = [
        "akashic_s2": [
            "fields": "所有端點共用的欄位選擇；回應是 Semantic Scholar 的原樣 JSON，不改變本工具的回應鍵",
            "ids": "batch 端點的輸入；情境只走 references（分頁端點）與 status——其他端點回的是 Semantic Scholar 的原樣 JSON",
            "name": "author_search 端點的輸入；同上，其他端點回原樣 JSON",
            "title": "match 端點的輸入；同上",
            "year": "match 端點的過濾；同上",
            "offset": "分頁端點的起點；情境的 references 從 0 開始，回應形狀相同",
        ],
        "akashic_search": [
            "author": "查詢條件；與 journal 回同一個形狀（陣列，元素鍵相同）",
            "library": "查詢條件（store 內的 membership 分類）；同上",
            "tag": "查詢條件；同上",
            "type": "查詢條件；同上",
            "year_from": "查詢條件；同上",
            "year_to": "查詢條件；同上",
        ],
        "akashic_person": ["library": "key 直查時的 membership 過濾；回應形狀不變"],
        "akashic_people": ["query": "姓名過濾；回應形狀不變"],
        "akashic_export": ["citekeys": "限定匯出哪幾筆；回應形狀由 format 決定"],
        "akashic_files": ["key": "只給 use；use 切換 session 的 active store、需要 registry，情境沒有走（ToolPayloadKeyGuardTests 的誠實邊界）"],
        "akashic_libraries": [
            "document": "文件型 library 的規則（create／set-kind 時）；情境以規則型與主題型走同一個回應形狀",
            "excluded": "規則型 library 的排除清單（create／set-kind 時）；同上",
            "types": "規則型 library 的作品類型限制（create／set-kind 時）；同上",
            "source": "規則的外部來源 id（只記來歷，不作檢查依據）；同上",
        ],
        "akashic_resolve_people": [
            "confirm_tiers": "apply 的承認參數：寬鬆提名層要列在這裡才套用，缺了整批拒絕——不是一條自己的腿，回應形狀同 apply",
        ],
        "akashic_import_zotero": ["library_id": "只匯入某一個 Zotero library；回應形狀與不限定時相同"],
        "akashic_enrich_from_zotero": ["library_id": "同 akashic_import_zotero：只讀某一個 Zotero library，回應形狀相同"],
        "akashic_import_wos": ["csv": "選解析器（CSV 或 tab-delimited）；兩種輸入回同一份報告形狀"],
    ]

    /// 機械規則：命令 `update-venue` → 工具 `akashic_update_venue`（巢狀命令帶空白，沒有機械對應）。
    static func mechanicalTool(_ command: String) -> String? {
        command.contains(" ") ? nil : "akashic_" + command.replacingOccurrences(of: "-", with: "_")
    }

    /// 機械規則：旗標 `--drop-venue` → 參數 `drop_venue`。
    static func mechanicalParameter(_ flag: String) -> String {
        String(flag.drop { $0 == "-" }).replacingOccurrences(of: "-", with: "_")
    }
}

/// `Sources/akashic/WriteGateRulings.swift` 的兩張表，**讀原始碼**。
///
/// 為什麼不 `import akashic`：本 target 已連結 `akashic-mcp` 執行檔模組；再連結 `akashic` 會讓一個 test bundle 帶兩個執行檔模組，
/// 預設的建置系統（Xcode 27 起是 swiftbuild）下沒有驗過。表的寫法是一格一行的字面值（`"命令": .gated`），
/// `WriteGateRulingsTests.testTheTableIsWrittenOneEntryPerLine`（AkashicCLITests，那裡 `@testable import akashic`）釘住「原始碼
/// 逐行讀出來的＝編譯後的表」——讀得出來的東西不會比編譯後的少。
struct WriteGateRulingSource {
    enum Kind: String { case gated, notGated, readOnly, perLeg }

    var commands: [String: Kind] = [:]
    var legs: [String: [String: Kind]] = [:]
    /// 在表的區段裡、看起來像一格卻讀不出來的行，以及重複的鍵——非空即紅。
    var unparsed: [String] = []

    static func load() throws -> WriteGateRulingSource {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let file = dir.appendingPathComponent("Sources/akashic/WriteGateRulings.swift")
        return parse(try String(contentsOf: file, encoding: .utf8))
    }

    static func parse(_ text: String) -> WriteGateRulingSource {
        enum Section { case none, commands, legs }
        var out = WriteGateRulingSource()
        var section = Section.none
        var currentCommand: String?
        let entry = try! NSRegularExpression(pattern: #"^\s*"([^"]+)"\s*:\s*\.(gated|notGated|readOnly|perLeg)\b"#)
        let legGroup = try! NSRegularExpression(pattern: #"^\s*"([^"]+)"\s*:\s*\[\s*$"#)
        func match(_ re: NSRegularExpression, _ line: String) -> [String]? {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
        }
        // `.newlines` 同時切 \n 與 \r\n（Swift 的 "\r\n" 是一個 Character，split(separator: "\n") 切不開）
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.contains("static let commandRulings") { section = .commands; continue }
            if line.contains("static let legRulings") { section = .legs; currentCommand = nil; continue }
            if line == "    ]" { section = .none; continue }   // 兩張表的字面值都以四格縮排的 `]` 收尾
            guard section != .none, trimmed.hasPrefix("\"") else { continue }
            switch section {
            case .commands:
                guard let g = match(entry, line), let kind = Kind(rawValue: g[1]) else { out.unparsed.append(line); continue }
                if out.commands.updateValue(kind, forKey: g[0]) != nil { out.unparsed.append("重複的命令：\(g[0])") }
            case .legs:
                if let g = match(legGroup, line) { currentCommand = g[0]; out.legs[g[0], default: [:]] = [:]; continue }
                guard let cmd = currentCommand, let g = match(entry, line), let kind = Kind(rawValue: g[1]), kind != .perLeg
                else { out.unparsed.append(line); continue }
                if out.legs[cmd, default: [:]].updateValue(kind, forKey: g[0]) != nil { out.unparsed.append("重複的腿：\(cmd) \(g[0])") }
            case .none:
                break
            }
        }
        return out
    }
}
