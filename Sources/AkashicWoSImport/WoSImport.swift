import Foundation
import AkashicCore
import AkashicStoreIO

/// Web of Science 匯出 → Akashic entries（#21）。
///
/// ## 為什麼是 tab-delimited 而不是 xlsx
///
/// issue 寫的是 xlsx，但 **xlsx 是一個 zip**，而本專案沒有 zip 依賴（`Package.swift` 只有
/// Yams / ArgumentParser / MCP SDK / biblatex）。為了讀一個表格引入 zip 函式庫、或 shell out
/// 到 `unzip`，兩者都是為了格式而非為了能力付出代價。
///
/// **WoS 的匯出對話框原生就有「Tab delimited file」**——同樣的欄位、同樣的資料、零依賴。
/// 使用者匯出時選它即可；已經有 xlsx 的話，任何試算表軟體「另存為 TSV」也是一步。
///
/// 解析器本身**格式無關**（吃 `[[String: String]]`），所以日後真要加 xlsx 只需補一個
/// reader，`rows(from:)` 之後的邏輯完全不動。
///
/// ## 這個 importer 的真正價值不在讀檔，在 alias 配對
///
/// WoS 的 `Authors` 欄（`Su, YH; Chiou, JM`）與 `Author Full Names` 欄
/// （`Su, Ying-Hao; Chiou, Jeng-Min`）**同 index 對齊**——每位作者免費得到兩種寫法。
///
/// 這剛好補掉 `PersonResolver.normalize()` 不重排 `Last, First`、不移除連字號的
/// 限制（#81 起它經 `NameNormalization.matchingKey` 統一連字號**變體**與 NFKC，
/// 但重排與去連字號仍刻意不做）。**靠顯式列舉，不靠聰明的正規化**——
/// 每條 alias 都是可 `git diff` 的資料，錯配可追溯到哪一條造成。
public enum WoSImport {

    public struct Report: Equatable {
        public var created: [String] = []
        public var unchanged: [String] = []
        /// citekey 撞號且**內容不同**——不覆寫，列出讓人決定。
        public var conflicts: [String] = []
        /// 從兩欄配對出的 alias 組（每組是同一位作者的多種寫法）。
        public var aliasGroups: [[String]] = []
        public var skippedRows: [String] = []
    }

    // MARK: - 解析

    /// TSV/CSV → 逐列的欄位字典。第一列是表頭。
    ///
    /// WoS 的 tab-delimited 匯出**不 quote**（欄位內不含 tab），所以 tab 分隔可以直接切。
    /// CSV 走 RFC 4180（含 quoted 欄位與內嵌換行）——書目 title 常含逗號。
    public static func rows(from text: String, separator: Character = "\t") -> [[String: String]] {
        let fields = parseDelimited(text, separator: separator)
        guard let header = fields.first, header.count > 1 else { return [] }
        return fields.dropFirst().compactMap { row in
            guard row.contains(where: { !$0.isEmpty }) else { return nil }   // 全空列跳過
            var d: [String: String] = [:]
            for (i, name) in header.enumerated() where i < row.count {
                let v = row[i].trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { d[name.trimmingCharacters(in: .whitespaces)] = v }
            }
            return d
        }
    }

    /// RFC 4180 解析（quoted 欄位、`""` 逸出、內嵌換行）。
    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let n = text.index(after: i)
                    if n < text.endIndex, text[n] == "\"" { field.append("\""); i = n }
                    else { inQuotes = false }
                } else if c == "\r\n" {
                    field.append("\n")                // 引號內的換行一律正規化成 LF，
                } else { field.append(c) }            // 讓 LF 與 CRLF 兩份檔完全等價
            } else {
                switch c {
                // **`"\r\n"` 是單一 `Character`**（extended grapheme cluster），既不等於
                // `"\r"` 也不等於 `"\n"`。少了這個 case，CRLF 檔的換行永遠不被辨識，
                // 整份檔案被吞成一個 field → 0 列資料且不報錯（#89）。
                // WoS 從 Windows 匯出的 tab-delimited 檔原生就是 CRLF。
                case "\r\n": row.append(field); field = ""; rows.append(row); row = []
                case "\"": inQuotes = true
                case separator: row.append(field); field = ""
                case "\r": break                      // 單獨的 CR（舊 Mac 行尾）丟掉
                case "\n": row.append(field); field = ""; rows.append(row); row = []
                default: field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// 分號拆多作者。WoS 用 `; ` 分隔。
    static func splitAuthors(_ s: String?) -> [String] {
        (s ?? "").split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 兩欄同 index 配對出 alias 組。
    ///
    /// **長度不同時只配到較短的那個為止，其餘各自成組**——不猜對齊。WoS 偶爾兩欄的
    /// 作者數不同（團體作者、資料瑕疵），強行對齊會把 A 的縮寫配到 B 的全名上，
    /// 產生一條**錯的 alias**，而錯的 alias 會讓 `PersonResolver` 把兩個人合成一個。
    public static func aliasGroups(abbreviated: String?, full: String?) -> [[String]] {
        let a = splitAuthors(abbreviated), f = splitAuthors(full)
        guard !a.isEmpty || !f.isEmpty else { return [] }
        let paired = min(a.count, f.count)
        var out: [[String]] = (0..<paired).map { i in
            a[i] == f[i] ? [a[i]] : [a[i], f[i]]
        }
        out += a.dropFirst(paired).map { [$0] }
        out += f.dropFirst(paired).map { [$0] }
        return out
    }

    // MARK: - Entry 生成

    /// citekey：`<姓氏小寫><年份><title 首字>`，與 Zotero importer 的慣例對齊。
    /// 撞號時附加 `b`、`c`…（同 Zotero importer 的既有行為）。
    static func citekey(firstAuthor: String?, year: String?, title: String?,
                       taken: Set<String>) -> String? {
        let surname = (firstAuthor ?? "")
            .split(separator: ",").first.map(String.init)?
            .lowercased()
            .filter { $0.isLetter } ?? ""
        var y = ""
        if let year, let r = year.range(of: "[0-9]{4}", options: .regularExpression) {
            y = String(year[r])
        }
        let word = (title ?? "").split(separator: " ").first.map(String.init)?
            .lowercased().filter { $0.isLetter } ?? ""
        guard !surname.isEmpty, !y.isEmpty else { return nil }
        let base = surname + y + (word.isEmpty ? "x" : word)
        guard StoreKey.isValid(base) else { return nil }
        if !taken.contains(base) { return base }
        for suffix in "bcdefghijklmnopqrstuvwxyz" {
            let k = surname + y + String(suffix) + (word.isEmpty ? "x" : word)
            if StoreKey.isValid(k), !taken.contains(k) { return k }
        }
        return nil
    }

    /// 一列 → 一個 `Entry`。**作者全部落 `.literal`**——不自動歸戶，交給
    /// `PersonResolver` + App 裁決台（本 repo 的「絕不自動合併」鐵律）。
    public static func entry(from row: [String: String], taken: Set<String>) -> Entry? {
        let authors = splitAuthors(row["Authors"])
        let full = splitAuthors(row["Author Full Names"])
        // 顯示用全名優先——它是給人看的
        let display = full.isEmpty ? authors : full
        let title = row["Article Title"]
        let year = row["Publication Year"]
        guard let ck = citekey(firstAuthor: display.first, year: year, title: title,
                               taken: taken) else { return nil }
        var e = Entry(id: UUID(), citekey: ck, type: "article",
                      title: title ?? "", authors: display.map { .literal($0) },
                      date: row["Publication Date"].map { "\(year ?? "") \($0)"
                          .trimmingCharacters(in: .whitespaces) } ?? year)
        if let j = row["Source Title"] { e.fields["journaltitle"] = j }
        if let v = row["Volume"] { e.fields["volume"] = v }
        if let n = row["Issue"] { e.fields["number"] = n }
        if let d = row["DOI"] { e.fields["doi"] = d }
        if let p = row["Start Page"], let q = row["End Page"] { e.fields["pages"] = "\(p)--\(q)" }
        // 團體作者：WoS 另有 Group Authors 欄。以 #6 的大括號標記保護，不讓 export 切壞。
        if let g = row["Group Authors"], !g.isEmpty {
            e.authors += splitAuthors(g).map { .literal(CorporateName.mark($0)) }
        }
        // **殘餘收集**（#206）——上面對映完之後，**其餘所有欄位原樣進 `fields`**。
        //
        // 這不是「順便多收一點」，是 `.claude/rules/lossless-intake.md` 的硬性要求：
        // 沒收進來的欄位不是「資料缺一塊」，是那一族命題**永久不可判定**，而且沒有
        // 任何跡象顯示它曾經可判定。實測一份 CV 的非期刊條目經此匯入會靜默丟掉 21 個
        // 欄位（`eventtitle`／`venue`／`institution`／`eprint`…），對 presentation 而言
        // 那些就是主要內容。
        //
        // **`consumedColumns` 與上面的對映是兩份會分岔的清單**——這是本段唯一的
        // 維護風險，由 `testEveryConsumedColumnIsDeclared` 釘住：那條測試對每個
        // 宣告的欄位餵值、斷言它**不會**同時出現在殘餘裡。漏宣告 → 該欄位重複出現
        // （一次對映、一次殘餘）→ 紅。
        for (column, value) in row where !Self.consumedColumns.contains(column) {
            guard !value.isEmpty, let key = FieldKey.normalized(column) else { continue }
            // **不覆寫已對映的鍵。** 對映的結果是經過語意處理的（`pages` 是
            // start--end 合成、`date` 併了年與日）；殘餘是原樣搬運。撞名時語意的
            // 那份勝出，且**不靜默**——留給 report 的 `droppedColumns`。
            if e.fields[key] != nil { continue }
            e.fields[key] = value
        }
        return e
    }

    /// 上面 `entry(from:taken:)` 已經**個別**處理掉的 WoS 欄位。
    ///
    /// 殘餘收集用它當補集的基準。**封閉列舉**——新增一個具名對映就要同步加進來，
    /// 否則那個欄位會被收兩次（一次語意對映、一次原樣殘餘）。
    /// `testEveryConsumedColumnIsDeclared` 是機械檢查。
    static let consumedColumns: Set<String> = [
        "Authors", "Author Full Names", "Article Title", "Publication Year",
        "Publication Date", "Source Title", "Volume", "Issue", "DOI",
        "Start Page", "End Page", "Group Authors",
    ]

    // MARK: - 匯入

    /// 匯入一份 WoS 匯出檔。
    ///
    /// **idempotent**：同一份檔重跑不產生重複 entry。判準是 **citekey ＋ 內容**——
    /// citekey 已存在且內容相同 → `unchanged`；內容不同 → `conflicts`（**不覆寫**，
    /// 因為那可能是使用者手動改過的資料，而 WoS 的欄位比 store 的窄）。
    public static func run(text: String, store: LibraryStore,
                           separator: Character = "\t",
                           dryRun: Bool = false) throws -> Report {
        var report = Report()
        let load = try store.load()
        var taken = Set(load.entries.map(\.citekey))

        // **零列不得靜默。** 「匯入成功但一筆都沒進」與「檔案格式不被辨識」在
        // created/unchanged 都是 0 時輸出完全相同——#89 的 CRLF bug 就是靠這個
        // 沉默存活的。有內容卻解析不出資料列時，留下可診斷的訊息。
        if rows(from: text, separator: separator).isEmpty,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report.skippedRows.append(
                "整份檔案沒有解析出任何資料列：可能只有表頭，或分隔字元／行尾格式未被辨識"
                + "（本次以 \(separator == "\t" ? "tab" : "逗號") 分隔解析）")
        }

        // **身分判準先於碰撞避讓。** 這兩件事順序反了就不 idempotent：先避讓的話，
        // 重跑時「基底 citekey 已被自己上次匯入佔用」會生出 `su2015bfunctional`，
        // 於是每跑一次多一份。所以先問「這筆是不是同一篇」，是才比對、否才避讓。
        //
        // 身分用 **DOI 優先，無 DOI 則 (標題, 年份)**——citekey 是衍生的稱呼，
        // 拿它當身分正是上面那個 bug 的來源。
        func identity(_ e: Entry) -> String {
            if let doi = e.fields["doi"]?.lowercased(), !doi.isEmpty { return "doi:\(doi)" }
            let y = e.date?.prefix(4) ?? ""
            return "ty:\(e.title.lowercased())|\(y)"
        }
        let byIdentity = Dictionary(load.entries.map { (identity($0), $0) },
                                    uniquingKeysWith: { a, _ in a })

        for (i, row) in rows(from: text, separator: separator).enumerated() {
            let groups = aliasGroups(abbreviated: row["Authors"], full: row["Author Full Names"])
            // 先用「不避讓」的方式生一個試探性 entry，只為了算出身分
            guard let probe = entry(from: row, taken: []) else {
                report.skippedRows.append("第 \(i + 2) 列：缺第一作者姓氏或年份，無法生成 citekey")
                continue
            }
            report.aliasGroups += groups.filter { $0.count > 1 }

            if let existing = byIdentity[identity(probe)] {
                // 同一篇。比對時忽略 id（新生成的 UUID 必然不同）、citekey（衍生的稱呼）
                // 與 unknownFields。
                var a = existing, b = probe
                a.id = b.id; a.citekey = b.citekey
                a.unknownFields = []; b.unknownFields = []
                if a == b { report.unchanged.append(existing.citekey) }
                else { report.conflicts.append(existing.citekey) }
                continue
            }

            // 新的一篇——此時才做 citekey 碰撞避讓
            guard let e = entry(from: row, taken: taken) else {
                report.skippedRows.append("第 \(i + 2) 列：citekey 碰撞無法解決")
                continue
            }
            taken.insert(e.citekey)
            if !dryRun { try store.writeEntry(e) }
            report.created.append(e.citekey)
        }
        return report
    }
}
