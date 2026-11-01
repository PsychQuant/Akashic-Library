import Foundation
import ArgumentParser
import AkashicCore
import AkashicSkillTools

struct CitedByCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cited-by",
        abstract: "OpenAlex 被引搜尋的離線中間運算；不連網、不建檔、不連結",
        subcommands: [CitedByQueryCmd.self, CitedByReadCmd.self, CitedBySelectCmd.self])
}

private func citedByLoad<T: Decodable>(_ type: T.Type, path: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

/// Preserve JSON values for replay, while escaping the shared unsafe-scalar set.
/// Unlike displaySafe(string), JSON Unicode escapes round-trip without changing IDs/cursors.
private func citedByEmit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(value), as: UTF8.self)
    print(UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: json)) // display-safe-exempt: shared lossless JSON scalar escaping

}

struct CitedByQueryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "query",
        abstract: "產生可重播的查詢；未指定篩選或排序時只計數（per_page=1）")
    @Option(name: .long, help: "已核對身分的 OpenAlex W ID，可重複") var seed: [String] = []
    @Option(name: .long, help: "intersection（預設）或 union") var mode = "intersection"
    @Option(name: .long, help: "出版起年，含該年") var fromYear: Int?
    @Option(name: .long, help: "出版迄年，含該年") var toYear: Int?
    @Option(name: .long, help: "使用者選定的 OpenAlex S ID，可重複；來源之間為 OR") var source: [String] = []
    @Option(name: .long, help: "最低被引次數（含端點）") var minCitations: Int?
    @Option(name: .long, help: "OpenAlex search 查詢；與引用、年份條件為 AND") var search: String?
    @Option(name: .long, help: "cited_by_count:desc 或 publication_date:desc；明確指定即允許候選清單") var sort: String?
    @Option(name: .long, help: "page（預設，最多一萬筆）或 cursor（後續頁需 API key）") var paging = "page"
    @Option(name: .long, help: "每頁 1–100 筆，預設 50") var pageSize = 50
    @Option(name: .long, help: "最多讀 1–100 頁，預設 5") var maxPages = 5
    @Option(name: .long, help: "候選預算 1–10000 筆，預設 200") var maxCandidates = 200
    func run() throws {
        let query = try OpenAlexCitedBy.Query(seeds: seed, mode: mode, fromYear: fromYear, toYear: toYear,
            sourceIDs: source, minCitations: minCitations, search: search, sort: sort,
            pageSize: pageSize, maxPages: maxPages, maxCandidates: maxCandidates, paging: paging)
        try citedByEmit(CitedByPlan(query: query, firstURL: query.url()))
    }
}

struct CitedByPlan: Codable {
    var contract = OpenAlexCitedBy.contract
    let query: OpenAlexCitedBy.Query
    let firstURL: String
    func validate() throws {
        guard contract == OpenAlexCitedBy.contract, firstURL == (try query.url()) else {
            throw ValidationError("查詢契約或網址不一致；請用同一版 CLI 重建 query")
        }
    }
}

struct CitedByReadCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "read",
        abstract: "驗證一頁 OpenAlex JSON 並合併候選；nextURL 為下一頁，非空不代表已取得",
        discussion: "只接受瀏覽器取得且 HTTP 200 的原始 JSON。--observed-at 是該回應實際取得的 ISO 8601 時間。" +
            "--previous 必須是同一查詢上一頁的輸出；預算用完就停止。count 是各頁當下觀測值，不是固定母體。" +
            "有候選時必須給 --library 的絕對路徑，與 MCP active_root 綁定，不使用預設 store。" +
            "庫內 DOI 命中只供檢查；missing DOI 或 title-only 同篇仍須 bootstrap 判定。沒有任何 store 寫入。")
    @OptionGroup var options: LibraryOptions
    @Option(name: .long, help: "query 的 JSON 輸出") var query: String
    @Option(name: .long, help: "共用取得程序使用的 URL 檔；實際網址必須與計畫相同，不含 key") var requestedURLFile: String
    @Option(name: .long, help: "這一頁的原始 OpenAlex JSON") var response: String
    @Option(name: .long, help: "實際取得時間（含時區的 ISO 8601）") var observedAt: String
    @Option(name: .long, help: "上一頁 read 的輸出；第一頁不給") var previous: String?
    func run() throws {
        let plan = try citedByLoad(CitedByPlan.self, path: query)
        try plan.validate()
        let prior = try previous.map { try citedByLoad(OpenAlexCitedBy.Report.self, path: $0) }
        var requestedURL = try String(contentsOfFile: requestedURLFile, encoding: .utf8)
        if requestedURL.hasSuffix("\n") { requestedURL.removeLast() }
        var report = try OpenAlexCitedBy.read(query: plan.query, requestedURL: requestedURL,
            data: Data(contentsOf: URL(fileURLWithPath: response)), observedAt: observedAt, previous: prior)
        // Reuse canonical DOI and title nomination logic from references; never load a store for count-only.
        if !report.candidates.isEmpty {
            guard let root = options.library, root.hasPrefix("/") else {
                throw ValidationError("候選庫內檢查必須明確提供 --library 絕對路徑，並與 MCP active_root 相同；不使用預設 store")
            }
            let resolvedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            guard prior?.storeRoot == nil || prior?.storeRoot == resolvedRoot else {
                throw ValidationError("分頁期間 store root 改變；請在同一個 store 重新開始查詢")
            }
            report.storeRoot = resolvedRoot
            var reader = ReferencesNominateCmd(); reader.options = options
            let snapshot = try reader.storeSnapshot()
            for i in report.candidates.indices {
                let normalized = report.candidates[i].doi.flatMap { DOI($0)?.normalized }
                report.candidates[i].doi = normalized
                let matches = normalized.flatMap { snapshot.doiIndex[$0] } ?? []
                let titleMatches = ReferenceNominator.storeMatches(title: report.candidates[i].title,
                    year: report.candidates[i].year, in: snapshot.records).map(\.citekey)
                report.candidates[i].inStore = Array(Set(matches + titleMatches)).sorted()
                if snapshot.quarantined > 0 { report.candidates[i].storeStatus = "incomplete-store-scan" }
                else if matches.count > 1 { report.candidates[i].storeStatus = "doi-conflict" }
                else if matches.count == 1 { report.candidates[i].storeStatus = "doi-match-review-identity" }
                else if !titleMatches.isEmpty { report.candidates[i].storeStatus = "possible-title-match" }
                else { report.candidates[i].storeStatus = "not-found-not-proof-of-absence" }
            }
            if snapshot.quarantined > 0 && !report.warnings.contains("store-quarantined") { report.warnings.append("store-quarantined") }
        }
        try citedByEmit(report)
    }
}

struct CitedBySelectCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select",
        abstract: "只輸出明確指定候選 ID 的交接提案；不代表使用者同意、不執行匯入",
        discussion: "僅在使用者看過候選清單並明確指定 ID 後呼叫。這個命令不建立 work、library 或 cites。" +
            "交接仍須 akashic-bootstrap 重新驗證身分與庫內重複；不得擴展未選候選。")
    @Option(name: .long, help: "read 的報告") var report: String
    @Option(name: .long, help: "使用者明確選取的 W ID，可重複旗標；沒有 --all") var id: [String] = []
    func run() throws {
        let input = try citedByLoad(OpenAlexCitedBy.Report.self, path: report)
        try citedByEmit(OpenAlexCitedBy.select(report: input, ids: id))
    }
}
