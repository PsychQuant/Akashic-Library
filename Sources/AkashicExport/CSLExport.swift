import Foundation
import AkashicCore

/// CSL-JSON 輸出（pandoc / Zotero 互通格式）。同 `.bib`——衍生產物。
public enum CSLExport {

    public static func cslJSON(entries: [Entry], people: [Person],
                               organizations: [Organization] = [],
                               venues: [Venue]) throws -> String {
        // #669：重複的 key 留第一筆（列舉順序），不 trap——validate 以 error 報重複
        let peopleByKey = Dictionary(people.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let venuesByKey = Dictionary(venues.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let organizationsByKey = Dictionary(organizations.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let items: [[String: Any]] = entries
            .sorted { $0.citekey < $1.citekey }
            .map { entry in
                // #158 verify R3-A：這裡是**序列化**不是顯示——CSL-JSON 寫檔時保留
                // 原始位元組是對的。消毒屬**輸出邊界**（CLI 的 stdout 分支、MCP 的
                // tool result），修在這裡會破壞匯出檔的正確性。追蹤於 #165。
                var item: [String: Any] = [
                    "id": entry.citekey,   // display-safe-exempt: entry.citekey：序列化面，消毒屬輸出邊界（#165）
                    "type": entry.type.cslType,
                    "title": entry.title,   // display-safe-exempt: entry.title：同上（#165）
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
                // CSL 的 `DOI`／`ISBN`／`ISSN` 是**單值字串**（不是陣列）。ISBN／ISSN 多值以逗號分隔——與 `.bib` 那面同一個
                // 慣例；DOI 是例外，見下（#543）。
                func emitIdentifiers<T: Identifier>(_ ids: [T], as key: String) {
                    guard !ids.isEmpty else { return }
                    item[key] = ids.map(\.normalized).joined(separator: ", ")
                }
                // DOI 只放一個、其餘接進 note——與 `.bib` 同一條裁決（#543）；逗號串起來的 DOI 是一條死連結
                if let first = entry.doi.first {
                    item["DOI"] = first.normalized
                    let rest = BibExport.otherDOIs(entry)
                    if !rest.isEmpty {
                        // 本匯出不輸出來源的 note（fieldMap 沒有它），所以 note 只裝這一句——不是「接在既有 note 後面」（#543 R1 verify DA 第 31 列）
                        item["note"] = BibExport.appendingOtherDOIs(to: nil, rest)
                    }
                }
                emitIdentifiers(entry.isbn, as: "ISBN")
                // ISSN 住 venue（§8 之後）。只在 `fields` 沒有殘留時才拉，
                // 與 `.bib` 那面同判準——遷移略過的那些仍在 `fields`，不得被覆蓋。
                // **venue 優先於 work 的殘留**（#425 verify）——與 `.bib` 那面同一條規則。
                let venueISSNs = entry.venues.compactMap { ref -> Venue? in
                    if case .key(let k) = ref { return venuesByKey[k] } else { return nil }
                }.flatMap(\.issn)
                if !venueISSNs.isEmpty {
                    emitIdentifiers(venueISSNs, as: "ISSN")
                }
                return item
            }
        let data = try JSONSerialization.data(
            withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
