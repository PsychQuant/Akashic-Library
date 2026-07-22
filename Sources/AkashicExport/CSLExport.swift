import Foundation
import AkashicCore

/// CSL-JSON 輸出（pandoc / Zotero 互通格式）。同 `.bib`——衍生產物。
public enum CSLExport {
    static let typeMap: [String: String] = [
        "article": "article-journal",
        "book": "book",
        "incollection": "chapter",
        "inproceedings": "paper-conference",
        "thesis": "thesis",
        "report": "report",
        "online": "webpage",
        "unpublished": "manuscript",
        "misc": "document",
    ]

    public static func cslJSON(entries: [Entry], people: [Person]) throws -> String {
        let peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        let items: [[String: Any]] = entries
            .sorted { $0.citekey < $1.citekey }
            .map { entry in
                var item: [String: Any] = [
                    "id": entry.citekey,
                    "type": typeMap[entry.type] ?? "document",
                    "title": entry.title,
                ]
                if !entry.authors.isEmpty {
                    item["author"] = entry.authors.map { author -> [String: Any] in
                        let display: String
                        switch author {
                        case .key(let k): display = peopleByKey[k]?.names.first ?? k
                        case .literal(let s): display = s
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
                return item
            }
        let data = try JSONSerialization.data(
            withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
