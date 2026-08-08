import ArgumentParser
import Foundation
import AkashicCore   // #28：displaySafe
import AkashicStoreIO
import AkashicIndex
import AkashicQuery
import AkashicGraph

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query", abstract: "結構化查詢（欄位篩選 + 關係查詢，走 index）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "作者（person key 完全命中或 literal 子字串）") var author: String?
    @Option(name: .long, help: "期刊（case-insensitive 完全命中）") var journal: String?
    @Option(name: .long, help: "tag") var tag: String?
    @Option(name: .customLong("in-library"), help: "library key 篩選（#13 membership views；--library 是 root 路徑）") var inLibrary: String?
    @Option(name: .long, help: "entry type") var type: String?
    @Option(name: .long, help: "起始年") var yearFrom: Int?
    @Option(name: .long, help: "結束年") var yearTo: Int?
    @Option(name: .long, help: "與此 citekey 同期刊") var sameJournalAs: String?
    @Option(name: .long, help: "與此 citekey 同作者") var sameAuthorAs: String?
    @Option(name: .long, help: "此 citekey 引用了誰") var citesOf: String?
    @Option(name: .long, help: "誰引用此 citekey") var citedBy: String?
    @Option(name: .long, help: "與此 citekey 相關（雙向）") var relatedTo: String?
    @Flag(name: .long, help: "JSON 輸出") var json = false

    func run() throws {
        let store = try options.openStore()
        // index 缺席或 schema 過舊（如 v1.1 index 撞 --in-library）→ 自動重建（#13 verify）
        _ = try LibraryIndex(store: store).ensureCurrent()
        let engine = try QueryEngine(indexPath: store.indexURL)

        let relationFlags = [sameJournalAs, sameAuthorAs, citesOf, citedBy, relatedTo]
            .compactMap { $0 }
        guard relationFlags.count <= 1 else {
            throw ValidationError("關係查詢一次一種（--same-journal-as / --same-author-as / --cites-of / --cited-by / --related-to）")
        }

        let results: [EntrySummary]
        if let key = sameJournalAs {
            results = try engine.sameJournal(as: key)
        } else if let key = sameAuthorAs {
            results = try engine.sameAuthor(as: key)
        } else if let key = citesOf {
            results = try engine.cites(of: key)
        } else if let key = citedBy {
            results = try engine.citedBy(key)
        } else if let key = relatedTo {
            results = try engine.related(to: key)
        } else {
            var filter = QueryFilter()
            filter.author = author
            filter.journal = journal
            filter.tag = tag
            filter.type = type
            filter.library = inLibrary
            filter.yearFrom = yearFrom
            filter.yearTo = yearTo
            results = try engine.find(filter)
        }

        if json {
            let payload: [[String: Any]] = results.map { summary in
                var dict: [String: Any] = [
                    "citekey": displaySafe(summary.citekey, max: 200),
                    "type": displaySafe(summary.type, max: 200),   // #164：與 MCP 側 summaryDict 對齊
                    "title": displaySafe(summary.title, max: 800),
                    "authors": summary.authors.map { displaySafe($0, max: 200) },
                ]
                if let year = summary.year { dict["year"] = year }   // display-safe-exempt: Int
                // #156 verify 156-15：同 AkashicService.summaryDict——journal 是
                // biblatex 第三方內容，與 title 同源
                if let journal = summary.journal {
                    dict["journal"] = displaySafe(journal, max: 800)
                }
                return dict
            }
            let data = try JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            guard !results.isEmpty else {
                print("（無結果）")
                return
            }
            for summary in results {
                let year = summary.year.map(String.init) ?? "----"
                let authors = summary.authors.joined(separator: "; ")
                print("\(displaySafe(summary.citekey, max: 200))\t\(year)\t\(displaySafe(authors, max: 800))\t\(displaySafe(summary.title, max: 800))")
            }
        }
    }
}

struct Graph: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "graph", abstract: "以某篇文章為中心的關係圖（Mermaid/DOT/GraphML）")

    enum Format: String, ExpressibleByArgument {
        case mermaid, dot, graphml
    }

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "中心 citekey") var focus: String
    @Option(name: .long, help: "鄰域深度（預設 1）") var depth: Int = 1
    @Option(name: .long, help: "mermaid | dot | graphml") var format: Format = .mermaid
    @Option(name: .long, help: "輸出檔（預設 stdout）") var output: String?

    func run() throws {
        let store = try options.openStore()
        _ = try LibraryIndex(store: store).ensureCurrent()   // 與 Query 對齊（DA 漏網之魚#1）
        let builder = try GraphBuilder(indexPath: store.indexURL)
        let neighborhood = try builder.neighborhood(focus: focus, depth: depth)
        let content: String
        switch format {
        case .mermaid: content = GraphRenderer.mermaid(neighborhood)
        case .dot: content = GraphRenderer.dot(neighborhood)
        case .graphml: content = GraphRenderer.graphml(neighborhood)
        }
        if let output {
            try content.write(toFile: (output as NSString).expandingTildeInPath,
                              atomically: true, encoding: .utf8)
            print("寫出 \(neighborhood.nodes.count) nodes / \(neighborhood.edges.count) edges → \(output)")
        } else {
            print(content, terminator: "")
        }
    }
}
