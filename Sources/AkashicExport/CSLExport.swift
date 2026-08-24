import Foundation
import AkashicCore

/// CSL-JSON 輸出（pandoc / Zotero 互通格式）。同 `.bib`——衍生產物。
public enum CSLExport {

    public static func cslJSON(entries: [Entry], people: [Person],
                               venues: [Venue],
                               organizations: [Organization] = []) throws -> String {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let venuesByKey = Dictionary(venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let organizationsByKey = Dictionary(
            uniqueKeysWithValues: organizations.map { ($0.key, $0) })
        let items: [[String: Any]] = entries
            .sorted { $0.citekey < $1.citekey }
            .map { entry in
                // #158 verify R3-A：這裡是**序列化**不是顯示——CSL-JSON 寫檔時保留
                // 原始位元組是對的。消毒屬**輸出邊界**（CLI 的 stdout 分支、MCP 的
                // tool result），修在這裡會破壞匯出檔的正確性。追蹤於 #165。
                var item: [String: Any] = [
                    "id": entry.citekey,   // display-safe-exempt: 序列化面，消毒屬輸出邊界（#165）
                    "type": entry.type.cslType,
                    "title": entry.title,   // display-safe-exempt: 同上（#165）
                ]
                if !entry.authors.isEmpty {
                    item["author"] = entry.authors.map { author -> [String: Any] in
                        let display: String
                        switch author {
                        case .key(let k): display = peopleByKey[k]?.displayName(in: .latn) ?? k
                        // #323：團體作者**直接回傳 CSL 的 `literal` name variant**——
                        // 那正是 CSL 對機構名的標準表述，且不必經過下方的
                        // `CorporateName.isMarked` 字串偵測（型別已經判定了）。
                        case .organization(let k):
                            return ["literal": organizationsByKey[k]?.displayName ?? k]
                        case .literal(let s): display = s
                        }
                        // #6：CSL 的 `literal` name variant 正好對應機構名——
                        // 標記去掉後原樣輸出，不做 family/given 切分。
                        if CorporateName.isMarked(display) {
                            return ["literal": CorporateName.unmark(display)]
                        }
                        if let split = BibExport.familyGiven(display) {
                            return ["family": split.family, "given": split.given]
                        }
                        return ["literal": display]
                    }
                }
                if let date = entry.date,
                   let yearRange = date.range(of: "[0-9]{4}", options: .regularExpression),
                   let year = Int(date[yearRange]) {
                    item["issued"] = ["date-parts": [[year]]]
                }
                let fieldMap: [(String, String)] = [
                    ("journaltitle", "container-title"), ("booktitle", "container-title"),
                    ("volume", "volume"), ("number", "issue"), ("pages", "page"),
                    ("doi", "DOI"), ("url", "URL"), ("publisher", "publisher"),
                    ("location", "publisher-place"), ("abstract", "abstract"),
                    ("isbn", "ISBN"), ("issn", "ISSN"), ("language", "language"),
                ]
                for (bib, csl) in fieldMap {
                    if let value = entry.fields[bib], item[csl] == nil {
                        item[csl] = value
                    }
                }
                // **結構化識別碼在 `fields` 之後寫，覆蓋殘留**（#394 verify）。
                //
                // 這一段是 `BibExport` §7／§8 的鏡像。原本沒有，而 §8 的遷移移除了
                // 664 筆的 `fields.doi`——實測 csl-json 的識別碼因此掉到
                // DOI 3／ISSN 0／ISBN 2（遷移前 667／64／31），rc=0、零診斷。
                // `.bib` 有 mitigation、csl-json 沒有，因為驗收條件只量了 `.bib`。
                //
                // CSL 的 `DOI`／`ISBN`／`ISSN` 是**單值字串**（不是陣列），多值以
                // 逗號分隔——與 `.bib` 那面同一個慣例，不另創一種。
                func emitIdentifiers<T: Identifier>(_ ids: [T], as key: String) {
                    guard !ids.isEmpty else { return }
                    item[key] = ids.map(\.normalized).joined(separator: ", ")
                }
                emitIdentifiers(entry.doi, as: "DOI")
                emitIdentifiers(entry.isbn, as: "ISBN")
                // ISSN 住 venue（§8 之後）。只在 `fields` 沒有殘留時才拉，
                // 與 `.bib` 那面同判準——遷移略過的那些仍在 `fields`，不得被覆蓋。
                if entry.fields["issn"] == nil {
                    let venueISSNs = entry.venues.compactMap { ref -> Venue? in
                        if case .key(let k) = ref { return venuesByKey[k] } else { return nil }
                    }.flatMap(\.issn)
                    emitIdentifiers(venueISSNs, as: "ISSN")
                }
                return item
            }
        let data = try JSONSerialization.data(
            withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
