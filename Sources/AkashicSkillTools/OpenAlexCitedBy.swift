import Foundation

/// #620: deterministic, offline discovery. No store access and no import operation.
public enum OpenAlexCitedBy {
    public static let contract = 1
    public enum Failure: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }
    public struct Query: Codable, Equatable {
        public let seeds: [String]
        public let mode: String
        public let fromYear: Int?
        public let toYear: Int?
        public let sourceIDs: [String]
        public let minCitations: Int?
        public let search: String?
        public let sort: String?
        public let pageSize: Int
        public let paging: String
        public let maxPages: Int
        public let maxCandidates: Int
        public var countOnly: Bool {
            fromYear == nil && toYear == nil && sourceIDs.isEmpty && minCitations == nil && search == nil && sort == nil
        }
        public init(seeds: [String], mode: String = "intersection", fromYear: Int? = nil,
                    toYear: Int? = nil, sourceIDs: [String] = [], minCitations: Int? = nil,
                    search: String? = nil, sort: String? = nil, pageSize: Int = 50,
                    maxPages: Int = 5, maxCandidates: Int = 200, paging: String = "page") throws {
            self.seeds = try Array(Set(seeds.map { try entityID($0, prefix: "W") })).sorted()
            self.mode = mode; self.fromYear = fromYear; self.toYear = toYear
            self.sourceIDs = try Array(Set(sourceIDs.map { try entityID($0, prefix: "S") })).sorted()
            self.minCitations = minCitations
            let text = search?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.search = text?.isEmpty == true ? nil : text
            self.paging = paging
            self.sort = sort; self.pageSize = pageSize; self.maxPages = maxPages; self.maxCandidates = maxCandidates
            try validate()
        }
        public func validate() throws {
            guard !seeds.isEmpty, seeds.count <= 50, Set(seeds).count == seeds.count,
                  ["intersection", "union"].contains(mode), ["page", "cursor"].contains(paging), (1...100).contains(pageSize),
                  (1...100).contains(maxPages), (1...10000).contains(maxCandidates), sourceIDs.count <= 100,
                  fromYear.map({ (1000...9999).contains($0) }) ?? true,
                  toYear.map({ (1000...9999).contains($0) }) ?? true,
                  (fromYear ?? 1000) <= (toYear ?? 9999), minCitations.map({ $0 >= 0 }) ?? true,
                  sort.map({ ["cited_by_count:desc", "publication_date:desc"].contains($0) }) ?? true,
                  search.map({ !$0.isEmpty && $0.utf8.count <= 1000 }) ?? true else {
                throw Failure.invalid("Invalid cited-by query limits, mode, sort or year range")
            }
            for seed in seeds { guard try entityID(seed, prefix: "W") == seed else { throw Failure.invalid("Use canonical seed IDs") } }
            for source in sourceIDs { guard try entityID(source, prefix: "S") == source else { throw Failure.invalid("Use canonical source IDs") } }
        }
        public func url(cursor: String = "*") throws -> String {
            try validate()
            guard !cursor.isEmpty, cursor.utf8.count <= 8192 else { throw Failure.invalid("Invalid cursor") }
            var filters = mode == "intersection" ? seeds.map { "cites:" + $0 } : ["cites:" + seeds.joined(separator: "|")]
            if let y = fromYear { filters.append("from_publication_date:\(y)-01-01") }
            if let y = toYear { filters.append("to_publication_date:\(y)-12-31") }
            if !sourceIDs.isEmpty { filters.append("primary_location.source.id:" + sourceIDs.joined(separator: "|")) }
            // OpenAlex range lower endpoint is inclusive; avoid >N's off-by-one.
            if let n = minCitations { filters.append("cited_by_count:\(n)-") }
            var items = [URLQueryItem(name: "filter", value: filters.joined(separator: ",")),
                         URLQueryItem(name: "per_page", value: String(countOnly ? 1 : pageSize)),
                         URLQueryItem(name: "select", value: "id,doi,title,publication_year,publication_date,primary_location,cited_by_count,referenced_works,abstract_inverted_index")]
            if let search { items.append(.init(name: "search", value: search)) }
            if !countOnly {
                items.append(.init(name: "sort", value: sort ?? "cited_by_count:desc"))
                if paging == "cursor" { items.append(.init(name: "cursor", value: cursor)) }
                else {
                    let page = cursor == "*" ? 1 : Int(cursor) ?? 0
                    guard (1...maxPages).contains(page), page * pageSize <= 10000 else { throw Failure.invalid("Invalid page number") }
                    items.append(.init(name: "page", value: String(page)))
                }
            }
            var url = URLComponents(string: "https://api.openalex.org/works")!
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            url.percentEncodedQuery = items.map { item in
                item.name + "=" + (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed)!
            }.joined(separator: "&")
            guard let result = url.url?.absoluteString else { throw Failure.invalid("Could not encode query URL") }
            return result
        }
    }
    public struct Signal: Codable, Equatable {
        public let category: String
        public let field: String
        public let evidence: String
    }
    public struct Candidate: Codable, Equatable {
        public let id: String
        public var doi: String?
        public var title: String
        public let year: Int?
        public let publicationDate: String?
        public var journal: String?
        public let citedByCount: Int?
        public let citedSeeds: [String]
        public let hasAbstract: Bool
        public var signals: [Signal]
        public var inStore: [String] = []
        public var storeStatus: String = "unchecked"
    }
    public struct Observation: Codable {
        public let requestedURL: String
        public let retrievedAt: String
        public let count: Int
        public let returned: Int
        public let nextCursor: String?
    }
    public struct Report: Codable {
        public var contract: Int = OpenAlexCitedBy.contract
        public let query: Query
        public var observations: [Observation] = []
        public var candidates: [Candidate] = []
        public var storeRoot: String?
        public var duplicateCount: Int = 0
        public var omittedCount: Int = 0
        public var warnings: [String] = []
        public var nextURL: String?
        public var stopReason: String = "more-pages"
        public var complete: Bool = false
    }
    private struct Response: Decodable {
        struct Meta: Decodable { let count: Int; let next_cursor: String? }
        struct Work: Decodable {
            struct Location: Decodable {
                struct Source: Decodable { let id: String?; let display_name: String? }
                let source: Source?
            }
            let id: String
            let doi: String?
            let title: String?
            let publication_year: Int?
            let publication_date: String?
            let primary_location: Location?
            let cited_by_count: Int?
            let referenced_works: [String]
            let abstract_inverted_index: [String: [Int]]?
        }
        let meta: Meta
        let results: [Work]
    }
    public static func entityID(_ raw: String, prefix: String) throws -> String {
        let value = raw.hasPrefix("https://openalex.org/") ? String(raw.dropFirst(21)) : raw
        guard value.range(of: "^" + prefix + "[0-9]+$", options: .regularExpression) != nil,
              value.utf8.count <= 32 else { throw Failure.invalid("Invalid OpenAlex entity ID") }
        return value
    }
    private static func timestamp(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: raw) { return d }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: raw)
    }
    public static func read(query: Query, requestedURL: String, data: Data, observedAt: String, previous: Report? = nil) throws -> Report {
        try query.validate()
        guard let observed = timestamp(observedAt), data.count <= 20_000_000 else { throw Failure.invalid("Invalid observation time or oversized response") }
        var r = previous ?? Report(query: query)
        guard r.contract == contract, r.query == query, r.observations.count < query.maxPages,
              previous == nil || (r.nextURL != nil && r.stopReason == "more-pages"),
              r.candidates.count < query.maxCandidates else { throw Failure.invalid("Stopped, incompatible or over-budget report; start a new query") }
        let cursor = query.paging == "page" ? String(r.observations.count + 1) : (r.observations.last?.nextCursor ?? "*")
        let expectedURL = try query.url(cursor: cursor)
        guard requestedURL == expectedURL else { throw Failure.invalid("Response request URL does not match the next planned request") }
        if let p = previous {
            guard p.nextURL == requestedURL,
                  p.observations.last.flatMap({ timestamp($0.retrievedAt) }).map({ observed >= $0 }) == true else {
                throw Failure.invalid("Report cursor or observation chronology mismatch")
            }
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw Failure.invalid("Not a valid OpenAlex works response; stop without importing") }
        guard response.meta.count >= response.results.count,
              response.results.count <= (query.countOnly ? 1 : query.pageSize) else { throw Failure.invalid("Invalid meta.count or page size") }
        let next = response.meta.next_cursor
        if query.paging == "cursor", let next {
            guard !next.isEmpty, next.utf8.count <= 8192, next != "*", next != cursor,
                  !r.observations.contains(where: { $0.nextCursor == next }) else { throw Failure.invalid("Repeated or invalid cursor") }
        }
        var seen = Set(r.candidates.map(\.id))
        var pageIDs = Set<String>()
        var added = 0
        for work in response.results {
            guard work.publication_year.map({ (0...9999).contains($0) }) ?? true,
                  (work.title?.utf8.count ?? 0) <= 10000, (work.doi?.utf8.count ?? 0) <= 2000,
                  (work.primary_location?.source?.display_name?.utf8.count ?? 0) <= 2000 else { throw Failure.invalid("Invalid year or oversized metadata") }
            let id = try entityID(work.id, prefix: "W")
            guard pageIDs.insert(id).inserted else { throw Failure.invalid("Duplicate work within a page") }
            let referenced = try Set(work.referenced_works.map { try entityID($0, prefix: "W") })
            let matched = query.seeds.filter { referenced.contains($0) }
            guard query.mode == "intersection" ? matched.count == query.seeds.count : !matched.isEmpty else { throw Failure.invalid("Response does not cite the requested seeds") }
            if let date = work.publication_date {
                guard validDate(date), work.publication_year.map({ String(date.prefix(4)) == String($0) }) ?? true else { throw Failure.invalid("Invalid publication date/year") }
            }
            if query.fromYear != nil || query.toYear != nil {
                guard let date = work.publication_date,
                      date >= "\(query.fromYear ?? 1000)-01-01", date <= "\(query.toYear ?? 9999)-12-31" else { throw Failure.invalid("Response is outside the publication date range") }
            }
            if !query.sourceIDs.isEmpty {
                guard let source = work.primary_location?.source?.id,
                      query.sourceIDs.contains(try entityID(source, prefix: "S")) else { throw Failure.invalid("Response is outside the selected journals") }
            }
            guard work.cited_by_count.map({ $0 >= 0 }) ?? true else { throw Failure.invalid("Negative citation count") }
            if let min = query.minCitations {
                guard let count = work.cited_by_count, count >= min else { throw Failure.invalid("Response is below the citation threshold") }
            }
            if query.countOnly { continue }
            if !seen.insert(id).inserted { r.duplicateCount += 1; continue }
            added += 1
            if r.candidates.count >= query.maxCandidates { r.omittedCount += 1; continue }
            let abstract = try reconstruct(work.abstract_inverted_index)
            let title = work.title ?? ""
            let signals = clues(title, field: "title") + clues(abstract ?? "", field: "abstract")
            r.candidates.append(Candidate(id: id, doi: work.doi, title: title, year: work.publication_year,
                                          publicationDate: work.publication_date, journal: work.primary_location?.source?.display_name,
                                          citedByCount: work.cited_by_count, citedSeeds: matched,
                                          hasAbstract: abstract != nil, signals: signals))
        }
        if !query.countOnly && !response.results.isEmpty && added == 0 { throw Failure.invalid("Page made no progress; possible stale response") }
        if r.observations.last.map({ $0.count != response.meta.count }) == true && !r.warnings.contains("count-changed") { r.warnings.append("count-changed") }
        r.observations.append(Observation(requestedURL: requestedURL, retrievedAt: observedAt,
                                          count: response.meta.count, returned: response.results.count, nextCursor: next))
        r.nextURL = nil
        if query.countOnly { r.stopReason = "count-only" }
        else if r.omittedCount > 0 { r.stopReason = "candidate-budget" }
        else if response.results.isEmpty || (query.paging == "cursor" ? next == nil : response.results.count < query.pageSize) {
            r.complete = r.omittedCount == 0 && r.candidates.count == response.meta.count && !r.warnings.contains("count-changed")
            r.stopReason = r.complete ? "exhausted" : "inconsistent-end"
        } else if r.candidates.count >= query.maxCandidates { r.stopReason = "candidate-budget" }
        else if r.observations.count >= query.maxPages { r.stopReason = "page-budget" }
        else { r.nextURL = try query.url(cursor: query.paging == "page" ? String(r.observations.count + 1) : next!); r.stopReason = "more-pages" }
        return r
    }
    private static func validDate(_ s: String) -> Bool {
        guard s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: s).map { f.string(from: $0) == s } ?? false
    }
    private static func reconstruct(_ index: [String: [Int]]?) throws -> String? {
        guard let index, !index.isEmpty else { return nil }
        var words: [Int: String] = [:]
        for (word, positions) in index {
            guard word.utf8.count <= 2000 else { throw Failure.invalid("Oversized abstract token") }
            for p in positions {
                guard (0..<50000).contains(p), words[p] == nil else { throw Failure.invalid("Invalid abstract positions") }
                words[p] = word
            }
        }
        guard let last = words.keys.max() else { return nil }
        // Preserve unknown positions; never manufacture adjacent phrases from a sparse index.
        return (0...last).map { words[$0] ?? "[missing]" }.joined(separator: " ")
    }
    private static func clues(_ text: String, field: String) -> [Signal] {
        let groups = [("critique", ["critique", "criticism", "limitations", "pitfalls", "bias", "inconsistency"]),
                      ("extension", ["extension", "generalization", "identification", "identifiability", "estimator", "robust", "improvement"]),
                      ("evaluation", ["simulation", "power analysis", "sensitivity", "comparison", "performance", "guidelines"])]
        return groups.compactMap { category, terms in
            for term in terms {
                if let range = text.range(of: "\\b" + term + "\\b", options: [.regularExpression, .caseInsensitive]) {
                    let start = text.index(range.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
                    return Signal(category: category, field: field, evidence: String(text[start..<end]))
                }
            }
            return nil
        }
    }
    /// This is an offline subset proposal, NEVER evidence that a human consented.
    public static func select(report: Report, ids: [String]) throws -> [Candidate] {
        try report.query.validate()
        guard report.contract == contract, !report.query.countOnly, !ids.isEmpty else { throw Failure.invalid("Explicit candidate IDs are required") }
        let normalized = try ids.map { try entityID($0, prefix: "W") }
        guard Set(normalized).count == normalized.count else { throw Failure.invalid("Duplicate selection IDs") }
        return try normalized.map { id in
            let matches = report.candidates.filter { $0.id == id }
            guard matches.count == 1 else { throw Failure.invalid("Selection must name a unique displayed candidate") }
            return matches[0]
        }
    }
}
