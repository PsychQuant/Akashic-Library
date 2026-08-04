import Foundation
import AkashicCore
import BiblatexAPA

/// `.bib` 是編譯產物——從 store 匯出、經 biblatex-apa-swift 序列化，
/// 永遠不是資料庫本體（spec ADR #10）。
public enum BibExport {
    /// Entry.fields（已是 biblatex 欄位名）之外的一級欄位對映。
    public static func bibEntry(for entry: Entry, people: [String: Person]) -> BibEntry {
        var fields = OrderedDict()
        fields["title"] = entry.title
        if !entry.authors.isEmpty {
            fields["author"] = entry.authors
                .map { bibName(for: $0, people: people) }
                .joined(separator: " and ")
        }
        if let date = entry.date {
            fields["date"] = date
        }
        for key in entry.fields.keys.sorted() {
            fields[key] = entry.fields[key]
        }
        return BibEntry(entryType: entry.type.uppercased(), key: entry.citekey,
                        fields: fields, rawText: "", lineNumber: 0)
    }

    public static func bibFile(entries: [Entry], people: [Person]) -> String {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        return entries
            .sorted { $0.citekey < $1.citekey }
            .map { BibWriter.serialize(bibEntry(for: $0, people: peopleByKey)) }
            .joined(separator: "\n\n") + "\n"
    }

    /// 顯示名 → biblatex「Family, Given」。無空格（CJK 全名）整體視為 family。
    static func bibName(for author: AkashicCore.Author, people: [String: Person]) -> String {
        let display: String
        switch author {
        // #81：對外名字由 `authorized` 指定，不由 `names` 的位置決定。書目是**羅馬化
        // 脈絡**，所以請求 latn；沒有指定時解析退到 key，讓缺口在書目上看得見而不是
        // 靜默印出索引系統產生的引用形（實測 84.6% 的記錄目前會走到這一步）。
        case .key(let k): display = people[k]?.displayName(in: .latn) ?? k
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
}
