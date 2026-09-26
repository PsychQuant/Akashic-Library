import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit
import BiblatexAPA

/// `akashic create-entry` —— CLI 的**無損**建檔入口（#206）。
///
/// ## 為什麼要有這支
///
/// 在此之前，能帶任意欄位的入口**只有 MCP** 的 `akashic_create_entry`；CLI 的
/// 33 個 subcommand 沒有一個做得到。實際後果：要把一份 `.bib` 無損收進 store，
/// 得繞過 CLI、用 stdio 驅動 `akashic-mcp` 逐筆呼叫——那條路只有寫程式的人走得到。
///
/// **能不能無損匯入，不該取決於使用者會不會寫 script。**
/// 見 `.claude/rules/lossless-intake.md`。
///
/// ## 與 MCP 共用同一條寫入路徑
///
/// 走 `AkashicService.createEntries`（#455；單筆的 `createEntry` 是它的薄包裝）——citekey 生成、
/// quarantine 檔名佔位、format gate、index rebuild 全部白拿，且**不會與 MCP 面分岔**。
///
/// ## 批次語意（#455，使用者裁決 2026-09-03）
///
/// 整個陣列**一次**呼叫 service：一次 load、批次內消解 citekey 碰撞、一次 rebuild。
/// **可預期的失敗（type 值域、識別碼形狀、欄位鍵、format 閘）整批擋、零寫入**——先前逐筆呼叫時
/// 第 k 筆失敗，前 k−1 筆已經落地；現在什麼都不寫，exit 非零並指名是第幾筆。磁碟層的 I/O 失敗
/// 逐筆收容、其餘照寫、rebuild 照跑，並 exit 非零。
struct CreateEntryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-entry",
        abstract: "建庫外文獻，**保留來源的所有欄位**（JSON 或 .bib；citekey 自動生成）。"
            + "陣列一次寫入：可預期的失敗整批擋、零寫入（#455）")

    enum Format: String, ExpressibleByArgument, CaseIterable {
        case json, bib
    }

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "輸入格式：json（同 MCP fields object）或 bib（biblatex）")
    var format: Format = .json

    @Option(name: .long, help: "輸入檔路徑；省略時讀 stdin")
    var file: String?

    @Flag(name: .long, help: "只回報會建什麼，不寫入")
    var dryRun = false

    func run() throws {
        let raw: Data
        if let file {
            raw = try Data(contentsOf: URL(fileURLWithPath: (file as NSString).expandingTildeInPath))
        } else {
            raw = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let text = String(data: raw, encoding: .utf8) else {
            throw RuntimeFailure.state("輸入不是合法的 UTF-8")
        }

        let drafts: [EntryDraft]
        switch format {
        case .json: drafts = try Self.parseJSON(raw)
        case .bib:
            // **未終止的 entry 必須報出來**（#207）。`BibParser` 的收集迴圈是
            // `while braceDepth > 0 && i + 1 < lines.count`——檔案在 entry 中途
            // 結束時它因為第二個條件退出，而 `parseEntry` **照常被呼叫**，
            // 產出一筆只含截斷點之前欄位的 entry，沒有任何錯誤。
            //
            // 半筆比缺欄位更糟：它讓「這筆記錄只有兩個欄位」與「這個檔案壞了」
            // 變成同一個觀察。現實成因不罕見——下載中斷、複製到一半、編輯器
            // 沒存完、`head -n` 之類的處理。
            //
            // 根因在 submodule，但**邊界的擁有者是這裡**（同 #176／#206 的立場）：
            // 換一個 parser、或它的行為改了，這道檢查仍然成立。
            try Self.refuseUnterminatedEntries(text)
            drafts = Self.parseBib(text)
        }
        guard !drafts.isEmpty else {
            // **零筆不得靜默。**「解析成功但一筆都沒有」與「格式沒被辨識」是兩件事，
            // 而使用者從 exit 0 + 無輸出分不出來（同 import-wos 的既有立場）。
            throw RuntimeFailure.state("解析出 0 筆——確認 --format \(format.rawValue) 與輸入相符")
        }

        if dryRun {
            print("（dry-run）將建 \(drafts.count) 筆：")
            for d in drafts {
                print("  \(displaySafe(d.title, max: 90))"
                    + "  [\(displaySafe(d.type, max: 40))]"
                    + "  作者 \(d.authors.count)"
                    + "  欄位 \(d.fields.count)")
            }
            return
        }

        let store = try options.openStore()
        // `key:` 不可省——見 `PersonCommand.swift` 的長註解（verify #220 HIGH）。
        // **先前的註解說「寫入路徑所以沒炸」——那是假的**（#218 R2 verify MEDIUM，
        // regression 與 DA 兩個 lens 各自打臉）。這兩支同樣走 `ensureFreshIndex()`，
        // 在已註冊的 store 裡會**建整份第二個 index**；`create-entry` 之後 `query`
        // 看不到新資料，而且不自癒（query 的 `ensureCurrent()` 不看 mtime）。
        // 差別只在它們的**主要產出**不取自 index，不是它們不碰 index。
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 一次呼叫（#455）：可預期的失敗由 service 整批 throw（ArgumentParser 印錯、exit 非零）；
        // 這裡只剩磁碟層的逐筆結果。
        let report = try service.createEntries(drafts)
        for c in report.created {
            // citekey 由 StoreKey 文法保證只含 [a-z0-9-]；id 是 UUID
            print("{\"citekey\":\"\(displaySafe(c.citekey, max: 200))\",\"id\":\"\(c.id.uuidString)\"}")   // display-safe-exempt: UUID
        }
        print("✓ created \(report.created.count)")   // display-safe-exempt: Int
        if !report.writeFailures.isEmpty {
            print("failed \(report.writeFailures.count)（磁碟層，其餘已寫入且 index 已重建）：")   // display-safe-exempt: Int
            for f in report.writeFailures.prefix(10) {
                print("  ! \(displaySafe(f.title, max: 80)) — \(displaySafeClipOnly(f.error, max: 3_200))")   // display-safe-exempt: error 已消毒（生產端 displaySafeError，R28 D80），只截
            }
            // **有任何一筆沒寫成就非零退出**：`akashic create-entry … && next` 不得在部分寫入時往下走
            throw ExitCode(1)
        }
    }

    // MARK: - 解析

    /// draft 的形狀住在 service（#455）——先前 CLI 自己有一份同名 struct 再逐欄轉呼叫，
    /// 兩份會分岔。識別碼走結構化欄位而不是 `fields`（#394）。
    typealias EntryDraft = AkashicService.EntryDraft

    /// JSON：單一 object 或 object 陣列。形狀與 MCP `akashic_create_entry` 相同。
    static func parseJSON(_ data: Data) throws -> [EntryDraft] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        let objects: [[String: Any]]
        if let one = parsed as? [String: Any] { objects = [one] }
        else if let many = parsed as? [[String: Any]] { objects = many }
        else { throw RuntimeFailure.state("JSON 必須是 object 或 object 陣列") }

        return try objects.map { o in
            guard let type = o["type"] as? String, !type.isEmpty,
                  let title = o["title"] as? String, !title.isEmpty else {
                throw RuntimeFailure.state("每筆都必須有非空的 type 與 title")
            }
            // **形狀不符一律報錯，不靜默降級**（#206 verify C2）。
            //
            // 第一版寫 `(o["authors"] as? [String]) ?? []`：Swift 的 `as? [String]`
            // 在**任一**元素不是字串時整個陣列失敗，於是 `["A","B",2025]` 會靜默
            // 變成**零個作者**、exit 0、無警告。同理 `o["date"] as? String` 對
            // `"date": 2025`（JSON 數字）回 nil，`o["fields"] as? [String: Any]`
            // 對陣列回 nil → 整個 fields 消失。
            //
            // 那正是本 change 所寫的規則要防的核心行為。貼 CSL-JSON 的作者物件
            // （`{"family":…,"given":…}`）也會全滅——而那是最可能的貼上來源之一。
            var fields: [String: String] = [:]
            if let f = o["fields"] {
                guard let dict = f as? [String: Any] else {
                    throw RuntimeFailure.state("「\(displaySafeInvisible(title, max: 120))」的 fields 必須是 object，實際是 \(Self.shapeName(f))")
                }
                for (k, v) in dict {
                    // **JSON null 跳過，不寫成 "<null>"**（verify M5）。來源說「沒有值」，
                    // 寫進一個字面 `<null>` 是**捏造**——store 會斷言一個來源沒說的東西。
                    if v is NSNull { continue }
                    if let s = v as? String { fields[k] = s; continue }
                    if let n = v as? NSNumber {
                        // Bool 判定先於數字：JSON 的 true/false 進 [String: Any] 是
                        // NSNumber，`as? Int` 對它也成立（YAML 那邊踩過同一個坑）
                        fields[k] = CFGetTypeID(n) == CFBooleanGetTypeID()
                            ? (n.boolValue ? "true" : "false") : n.stringValue
                        continue
                    }
                    // 巢狀 object／array：`String(describing:)` 會產出
                    // `{\n a = 1;\n}` 這種 NSDictionary dump——技術上「沒丟」，
                    // 實際不可讀也不可還原。報錯讓使用者自己決定要攤平成什麼。
                    throw RuntimeFailure.state(
                        "「\(displaySafeInvisible(title, max: 120))」的欄位 \(displaySafeInvisible(k, max: 120)) 是 \(Self.shapeName(v))，"
                        + "無法無損轉成字串——請先在來源攤平成純量")
                }
            }
            // **識別碼**（#394）。與 `authors` 同一條紀律：形狀不符**報錯**，不靜默降級。
            // 一個 `"doi": "10.x"`（字串而非陣列）若被靜默接受成零個 DOI，結果是一筆
            // 「呼叫端以為帶 DOI、實際沒有」的 work——那正是本檔上方註解所防的形狀。
            func idList(_ key: String) throws -> [String] {
                guard let raw = o[key] else { return [] }
                guard let arr = raw as? [Any] else {
                    throw RuntimeFailure.state(
                        "「\(displaySafeInvisible(title, max: 120))」的 \(displaySafeInvisible(key, max: 200)) 必須是陣列，實際是 \(Self.shapeName(raw))")
                }
                return try arr.map { el in
                    guard let s = el as? String else {
                        throw RuntimeFailure.state(
                            "「\(displaySafeInvisible(title, max: 120))」的 \(displaySafeInvisible(key, max: 200)) 含非字串元素（\(Self.shapeName(el))）")
                    }
                    return s
                }
            }
            let doi = try idList("doi")
            let pmid = try idList("pmid")
            let isbn = try idList("isbn")

            var authors: [String] = []
            if let a = o["authors"] {
                guard let arr = a as? [Any] else {
                    throw RuntimeFailure.state("「\(displaySafeInvisible(title, max: 120))」的 authors 必須是陣列，實際是 \(Self.shapeName(a))")
                }
                for el in arr {
                    guard let s = el as? String else {
                        throw RuntimeFailure.state(
                            "「\(displaySafeInvisible(title, max: 120))」的 authors 含非字串元素（\(Self.shapeName(el))）。"
                            + "作者一律用顯示名字串；CSL-JSON 的 {family,given} 物件請先合併成一個字串")
                    }
                    authors.append(s)
                }
            }
            var date: String?
            if let d = o["date"], !(d is NSNull) {
                if let s = d as? String { date = s }
                else if let n = d as? NSNumber { date = n.stringValue }   // "date": 2025 很常見
                else { throw RuntimeFailure.state("「\(displaySafeInvisible(title, max: 120))」的 date 必須是字串或數字，實際是 \(Self.shapeName(d))") }
            }
            return EntryDraft(type: type, title: title, authors: authors,
                              date: date, fields: fields,
                              doi: doi, pmid: pmid, isbn: isbn)
        }
    }

    /// 錯誤訊息用的形狀名。訊息要說「實際是什麼」，否則使用者只知道錯了、
    /// 不知道錯在哪個形狀。
    static func shapeName(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case is String: return "字串"
        case is [Any]: return "陣列"
        case is [String: Any]: return "object"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? "布林" : "數字"
        default: return String(describing: type(of: v))
        }
    }

    /// 掃描原始文字，找出**大括號沒有閉合**的 entry。
    ///
    /// 判準是每個 `@` 開頭的 entry 區塊自己的大括號要平衡。與 btparse 一樣
    /// **不看 backslash**（#176 量過：btparse 數大括號時完全忽略 backslash，
    /// 所以模仿它的計數才是對的）。字串字面量內的大括號同樣計數——biblatex 的
    /// 引號值裡的大括號本來就參與配對。
    static func refuseUnterminatedEntries(_ text: String) throws {
        var depth = 0
        var startLine: Int?
        var startKey = ""
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("%") { continue }        // 註解行不計（BibParser 亦然）
            if depth == 0, trimmed.hasPrefix("@") {
                startLine = i + 1
                startKey = trimmed.split(separator: "{").dropFirst().first
                    .map { String($0.prefix(while: { $0 != "," })) } ?? "?"
            }
            for ch in line {
                if ch == "{" { depth += 1 }
                if ch == "}" { depth = max(0, depth - 1) }
            }
            if depth == 0 { startLine = nil }
        }
        guard depth == 0, startLine == nil else {
            throw RuntimeFailure.state(
                "第 \(startLine.map(String.init) ?? "?") 行起的 entry"
                + "「\(displaySafeInvisible(startKey, max: 80))」大括號未閉合——"
                + "檔案可能被截斷。**拒絕整份匯入**：半筆記錄會讓「這筆只有幾個欄位」"
                + "與「這個檔案壞了」變成同一個觀察，事後無法區分")
        }
    }

    /// `.bib`：走 `BibParser`，**除 title／author／date 外的欄位全部原樣保留**。
    static func parseBib(_ text: String) -> [EntryDraft] {
        BibParser.parse(content: text).entries.map { e in
            var fields: [String: String] = [:]
            for key in e.fields.keys {
                let lower = key.lowercased()
                // 這三個抽成一級欄位，其餘留在 fields
                if lower == "title" || lower == "author" || lower == "date" { continue }
                guard let v = e.fields[key] else { continue }
                fields[FieldKey.normalized(lower) ?? lower] = v
            }
            let authorRaw = e.fields.caseInsensitiveValue(forKey: "AUTHOR") ?? ""
            // #325 階段二：`.bib` 帶的是 **biblatex 詞彙**（`@ARTICLE`），要讀回模型
            // 詞彙（`periodical-article`）。有損逆向的判準與原像選擇見
            // `WorkType.init?(biblatexEntryType:fields:)`；對映不到就原樣往下傳，
            // 由 `AkashicService.createEntry` 產出列出值域的拒絕訊息——**守衛只留
            // 一份**（`entity-backlink-completeness` 執行細節 2 的同一個立場：
            // 兩處各判一次就是兩條會分岔的路徑）。
            let mapped = WorkType(biblatexEntryType: e.entryType, fields: fields)
            return EntryDraft(
                type: mapped?.rawValue ?? e.entryType.lowercased(),
                title: e.fields.caseInsensitiveValue(forKey: "TITLE") ?? "",
                authors: splitBibAuthors(authorRaw),
                date: e.fields.caseInsensitiveValue(forKey: "DATE")
                    ?? e.fields.caseInsensitiveValue(forKey: "YEAR"),
                // **`.bib` 路徑刻意不帶結構化識別碼**（#394）。`.bib` 的 `DOI = {...}`
                // 進 `fields`，走**殘留路徑**——`migrate-identifiers` 會升格它。
                // 在這裡順手升格會製造第二條升格路徑，而那條路徑對「解不了的 token」
                // 的處置與遷移端不同（遷移把它留在殘留並報出來），兩者會分岔。
                fields: fields)
        }
    }

    /// biblatex 的 `A and B and C` → 顯示名陣列，並把 `Family, Given` 翻成
    /// `Given Family`。
    ///
    /// **翻面不是美觀偏好，是 citekey 正確性**：`AkashicService.createEntry` 取
    /// 「空格後最後一字」當姓（假設 `Given Family`），而 biblatex 慣例是
    /// `Family, Given`。不翻的話 `Terada, Yoshikazu` 會被當成姓 `Yoshikazu`，
    /// citekey 產出 `yoshikazu2024…`。
    ///
    /// 方向與 store 的既有分布一致：literal 作者 2071 筆是 `Given Family`、
    /// 只有 60 筆帶逗號。
    ///
    /// **機構名（`{...}` 標記）不翻**——那是 #6 的既有約定，切開會產出
    /// 「Organization, World Health」這種錯誤輸出。
    ///
    /// **切分必須是 brace-aware 的**（#206 verify C3）。第一版先
    /// `components(separatedBy: " and ")` 再檢查 `hasPrefix("{")`——順序反了：
    /// 守衛在切完之後才跑，護不住已經被切斷的名字。`{Barnes and Noble Publishing}`
    /// 會裂成 `{Barnes` 與 `Noble Publishing}`，接著 family/given 翻面對碎片生效，
    /// round-trip 匯出 `\textbraceleft{}Barnes and Publishing\textbraceright{}, Noble`。
    /// 真實輸入不罕見：`{Ministry of Health and Welfare}`、
    /// `{Department of Health and Human Services}`。
    ///
    /// 原本的測試用 `{{World Health Organization, Europe}}`——**不含 `" and "`**，
    /// 所以從來沒碰到這條路。
    static func splitBibAuthors(_ raw: String) -> [String] {
        splitTopLevelAnd(raw)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(flipFamilyGiven)
    }

    /// 只在**大括號深度 0** 處切 `" and "`。
    static func splitTopLevelAnd(_ raw: String) -> [String] {
        var out: [String] = []
        var buf = ""
        var depth = 0
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{" { depth += 1 }
            if c == "}" { depth = max(0, depth - 1) }
            if depth == 0, c == " ", i + 4 < chars.count,
               chars[i + 1] == "a", chars[i + 2] == "n", chars[i + 3] == "d", chars[i + 4] == " " {
                out.append(buf); buf = ""; i += 5; continue
            }
            buf.append(c); i += 1
        }
        out.append(buf)
        return out
    }

    /// `Family, Given` → `Given Family`。機構名與無逗號的原樣。
    static func flipFamilyGiven(_ name: String) -> String {
        if name.hasPrefix("{") || !name.contains(",") { return name }
        let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // **三段是 `Family, Suffix, Given`**（biblatex 的 `Smith, Jr., John`
        // ＝「John Smith Jr.」）。第一版 `maxSplits: 1` 把它讀成
        // `Jr., John` + `Smith` → 產出 `Jr., John Smith`（verify M6）。
        switch parts.count {
        // display-safe-exempt: 這兩行組的是**作者姓名本身**（會存進 Entry.authors），
        // 不是給人看的訊息。消毒它等於把來源的名字改掉——同 #171 劃下的
        // documentSafe/displaySafe 分界：內容面保真、訊息面消毒。守衛的 `return "`
        // 判準分不出「回傳一個值」與「回傳一句話」，這是它的已知形狀。
        case 2 where !parts[1].isEmpty:
            return "\(parts[1]) \(parts[0])"   // display-safe-exempt: 見上——組的是姓名內容非訊息
        case 3 where !parts[1].isEmpty && !parts[2].isEmpty:
            return "\(parts[2]) \(parts[0]) \(parts[1])"   // display-safe-exempt: 同上
        default:
            return name   // 四段以上不猜——原樣保留比重組錯誤好
        }
    }
}
