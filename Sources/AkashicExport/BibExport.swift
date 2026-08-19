import Foundation
import AkashicCore
import BiblatexAPA

/// `.bib` 是編譯產物——從 store 匯出、經 biblatex-apa-swift 序列化，
/// 永遠不是資料庫本體（spec ADR #10）。
public enum BibExport {
    /// Entry.fields（已是 biblatex 欄位名）之外的一級欄位對映。
    public static func bibEntry(for entry: Entry, people: [String: Person],
                                organizations: [String: Organization] = [:]) -> BibEntry {
        // 每個值都過 `braceSafe`（#176）。**逐個作者、不是 join 之後**——一個壞名字
        // 不該把整串作者一起拖進逃脫（那會改掉同一筆裡其他機構名的 `{...}` 標記）。
        var fields = OrderedDict()
        fields["title"] = braceSafe(entry.title)
        if !entry.authors.isEmpty {
            fields["author"] = entry.authors
                .map { braceSafe(bibName(for: $0, people: people,
                                         organizations: organizations)) }
                .joined(separator: " and ")
        }
        if let date = entry.date {
            fields["date"] = braceSafe(date)
        }
        for key in entry.fields.keys.sorted() {
            fields[key] = entry.fields[key].map(braceSafe)
        }
        return BibEntry(entryType: entry.type.biblatexEntryType, key: entry.citekey,
                        fields: fields, rawText: "", lineNumber: 0)
    }

    // MARK: - APA7 完整性報告（#326）

    /// 一筆 APA7 必要／建議欄位的缺漏。
    ///
    /// 與 `AkashicCore.ValidationIssue` 同名不同物——那個管 store schema，這個管
    /// **書目正確性**。兩者刻意不合併：語法正確（大括號平衡、可被 LaTeX 讀）與書目
    /// 正確（參考文獻印得出來）是兩件事，先前只有前者有守衛。
    public struct APA7Issue: Equatable {
        public enum Severity: String, Equatable { case error, warning }
        public let citekey: String
        public let severity: Severity
        public let message: String
    }

    /// `apa7Report` 的結果。
    ///
    /// **`uncheckedCitekeys` 是這個型別存在的理由。** `BibValidator` 的必要欄位表只
    /// 涵蓋 7 個 entry type（ARTICLE／PRESENTATION／REPORT／BOOK／INCOLLECTION／
    /// INPROCEEDINGS／THESIS），而 store 另有 `online`／`unpublished`／`misc` 等值
    /// （實測 47 筆）。對那些 type，validator 回空陣列——若只回 `issues`，「沒被檢查」
    /// 與「檢查過且乾淨」在輸出上**完全一樣**，而那正是本專案反覆記錄的靜默失敗形狀
    /// （`lossless-intake` 執行細節 3：「靜默是最糟的形式」）。
    ///
    /// type 值域的收斂是 #325 的範圍；本型別的責任只是**不假裝檢查過**。
    public struct APA7Report: Equatable {
        public let issues: [APA7Issue]
        public let uncheckedCitekeys: [String]

        /// 有沒有 error 級缺漏（warning 不算——它們是 recommended 欄位）。
        public var hasErrors: Bool { issues.contains { $0.severity == .error } }
    }

    /// biblatex-apa 的 `BibValidator` 涵蓋的 entry type（大寫正規化形）。
    ///
    /// **這份清單是對方的實作細節的鏡像**，會隨 dependency 演進而過期。它只用於
    /// 判定「這個 type 有沒有被檢查」，判錯的方向是**多報 unchecked**（保守、可見），
    /// 不是漏報 issue。
    private static let apa7CheckedTypes: Set<String> = [
        "ARTICLE", "PRESENTATION", "REPORT", "BOOK",
        "INCOLLECTION", "INPROCEEDINGS", "THESIS",
    ]

    /// 對每筆 entry 跑 APA7 必要欄位檢查，回報缺漏與**未被涵蓋的 type**。
    ///
    /// 不改變 `.bib` 內容——本函式是純讀取的旁路檢查（warn-only，#326 裁決）。
    public static func apa7Report(entries: [Entry], people: [Person],
                                  organizations: [Organization] = []) -> APA7Report {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let orgsByKey = Dictionary(uniqueKeysWithValues: organizations.map { ($0.key, $0) })
        var issues: [APA7Issue] = []
        var unchecked: [String] = []
        for entry in entries.sorted(by: { $0.citekey < $1.citekey }) {
            let bib = bibEntry(for: entry, people: peopleByKey, organizations: orgsByKey)
            guard apa7CheckedTypes.contains(entry.type.biblatexEntryType) else {
                unchecked.append(entry.citekey)
                continue
            }
            for issue in BibValidator.validate(entry: bib) {
                issues.append(APA7Issue(
                    citekey: entry.citekey,
                    severity: issue.severity == .error ? .error : .warning,
                    message: issue.message))
            }
        }
        return APA7Report(issues: issues, uncheckedCitekeys: unchecked)
    }

    public static func bibFile(entries: [Entry], people: [Person],
                               organizations: [Organization] = []) -> String {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let orgsByKey = Dictionary(uniqueKeysWithValues: organizations.map { ($0.key, $0) })
        return entries
            .sorted { $0.citekey < $1.citekey }
            .map { BibWriter.serialize(bibEntry(for: $0, people: peopleByKey,
                                                organizations: orgsByKey)) }
            .joined(separator: "\n\n") + "\n"
    }

    /// 顯示名 → biblatex「Family, Given」。無空格（CJK 全名）整體視為 family。
    static func bibName(for author: AkashicCore.Author, people: [String: Person],
                        organizations: [String: Organization] = [:]) -> String {
        let display: String
        switch author {
        // #81：對外名字由 `authorized` 指定，不由 `names` 的位置決定。書目是**羅馬化
        // 脈絡**，所以請求 latn；沒有指定時解析退到 key，讓缺口在書目上看得見而不是
        // 靜默印出索引系統產生的引用形（實測 84.6% 的記錄目前會走到這一步）。
        case .key(let k): display = people[k]?.displayName(in: .latn) ?? k
        // #323：團體作者。**直接回傳雙大括號形，不走下方的 familyGiven 分支**——
        // APA7 §9.11／biblatex 的 `author = {{Group Name}}` 慣例讓 BibTeX 不把團體名
        // 拆成「姓, 名」。這條路徑先前靠 `CorporateName.isMarked` 偵測 `{...}` 標記
        // （#6），現在有**型別保證**：不是猜這串像不像機構，是這個槽已判定為機構。
        case .organization(let k):
            let name = organizations[k]?.displayName ?? k
            // 已帶標記就不重複包——`{{{X}}}` 會讓 biblatex 多一層 group。
            return CorporateName.isMarked(name) ? "{\(CorporateName.unmark(name))}"
                                                : "{\(name)}"
        case .literal(let s): display = s
        }
        // #6：機構名（`{...}` 標記）原樣輸出——biblatex 的大括號本來就是「別動它」，
        // 切成 Family, Given 會產生 "Organization, World Health" 這種錯誤輸出。
        if CorporateName.isMarked(display) { return display }
        return familyGiven(display).map { "\($0.family), \($0.given)" } ?? display
    }

    /// 「Che Cheng」→ (family: Cheng, given: Che)；無空格回 nil（整體當 family）。
    static func familyGiven(_ display: String) -> (family: String, given: String)? {
        let tokens = display.split(separator: " ").map(String.init)
        guard tokens.count >= 2, let family = tokens.last else { return nil }
        return (family: family, given: tokens.dropLast().joined(separator: " "))
    }

    // MARK: - 大括號注入（#176）

    /// 值裡的大括號若**不平衡**，換成平衡的 LaTeX 命令。
    ///
    /// ## 為什麼守在這裡而不是只靠 writer
    ///
    /// 欄位值寫成 `{value}`。值裡有不平衡的 `}` 就提早關掉欄位，之後的內容被當成
    /// bibtex 語法——一個 title 可以開出一整筆不存在的 entry，而下游（LaTeX build、
    /// 文獻管理器、讀這份輸出的 LLM）分不出真假。
    ///
    /// `biblatex-apa-swift` 的 `BibWriter` 也有一份同樣的防護，**兩份不衝突**：平衡的
    /// 值兩邊都原樣通過，所以這裡先做完之後那邊是 no-op。留兩份不是重複，是因為
    /// **不受信任的內容源自 store，邊界的擁有者是這裡**——`BibWriter` 是共用的
    /// canonical library，哪天換一個 writer、或它的規則改了，洞就回來。
    ///
    /// 上面 `bibName` 的 `#6` 又讓這件事非做不可：機構名的 `{...}` **刻意原樣輸出**。
    /// 這個模組已經決定了「大括號要穿透」，那它就得負責穿透的是安全的形狀。
    ///
    /// ## `\}` 不是逃脫——量過的
    ///
    /// btparse（biber 背後的 parser，BibTeX 本尊亦然）**數大括號時不看 backslash**，
    /// `\}` 照樣關掉欄位。真的 `biber --tool` 對同一個注入 payload：
    ///
    /// | 輸出成 | biber |
    /// |---|---|
    /// | 未處理 | 2 筆 entry，偽造的與真的無從分辨 |
    /// | `\}` | **syntax error**，整檔零輸出／整筆被 skip |
    /// | `\textbraceright{}` | 1 筆 entry，payload 留成文字，0 error |
    ///
    /// 所以判準是**輸出永遠平衡**（下面三個替換各自 `{`+`}` 成對），不是「有沒有加
    /// backslash」。這是輸出的結構性質，對任何做括號計數的 parser 都成立。
    ///
    /// 同理，深度計數**刻意不跳過** `\{` / `\}`：它模仿的正是 btparse 自己的計數方式，
    /// 把它們當成已逃脫會低估。
    ///
    /// **平衡的值原樣通過**：biblatex 用 `{DNA}` 保護大小寫、機構名用 `{...}` 標記，
    /// 都是合法且常見的，動它們會改掉每一筆這種記錄的排版輸出。
    static func braceSafe(_ value: String) -> String {
        var depth = 0
        for ch in value {
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth < 0 { break }   // 關得比開的多
            }
        }
        guard depth != 0 else { return value }

        // 單次掃描。三個接續的 replacingOccurrences 會把本函式自己產生的大括號
        // 再逃脫一次。
        var out = ""
        out.reserveCapacity(value.count + 32)
        for ch in value {
            switch ch {
            case "{":  out += "\\textbraceleft{}"
            case "}":  out += "\\textbraceright{}"
            case "\\": out += "\\textbackslash{}"
            default:   out.append(ch)
            }
        }
        return out
    }
}
