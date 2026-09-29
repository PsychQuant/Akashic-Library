import AkashicCore
import Foundation

/// S2 回應的 JSON 值。整數與小數分開存，原樣輸出時 `1000` 不會變成 `1000.0`。
public indirect enum S2JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([S2JSON])
    case object([String: S2JSON])
}

public struct S2Result: Sendable, Equatable {
    public let endpoint: String
    public let request: [String: S2JSON]
    public let total: Int?
    public let offset: Int
    public let data: S2JSON
}

public enum S2ArgumentError: Error, Equatable, CustomStringConvertible {
    case emptyIdentifier(endpoint: String)
    case batchSize(Int)
    case limitOutOfRange(endpoint: String, limit: Int, range: ClosedRange<Int>)
    case negativeOffset(Int)
    case invalidIdentifier(endpoint: String, identifier: String)

    public var description: String {
        switch self {
        case .emptyIdentifier(let e): return "\(e) 需要非空的識別碼"
        case .batchSize(let n): return "batch 一次要 1 到 500 個 id；收到 \(n) 個"
        case .limitOutOfRange(let e, let l, let r):
            return r.upperBound == Int.max ? "\(e) 的 --limit 至少 \(r.lowerBound)；收到 \(l)"
                                          : "\(e) 的 --limit 要在 \(r.lowerBound) 到 \(r.upperBound) 之間；收到 \(l)"
        case .negativeOffset(let o): return "--offset 不得為負；收到 \(o)"
        case .invalidIdentifier(let e, let id): return "\(e) 的識別碼「\(displaySafe(id))」含 . 或 .. 路徑片段，不接受"
        }
    }
}

extension S2JSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([S2JSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: S2JSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> S2JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded() && abs(d) < 9e15: return Int(d)
        default: return nil
        }
    }

    public var arrayValue: [S2JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

/// 八個端點的請求組裝與分頁。回傳的 `data` 是 S2 的資料，字串的顯示清理在 `S2Output`。
public struct S2Endpoints: Sendable {
    static let graph = "/graph/v1"
    static let recommendations = "/recommendations/v1"
    /// S2 單頁的上限；分頁端點一律用它向 S2 要，S2 回得比較少時照 `next` 繼續翻。
    static let pageSize = 1000
    static let batchRange = 1...500
    static let recommendRange = 1...500
    /// `author-search` 未指定 `--limit` 時的筆數。
    public static let defaultSearchLimit = 100

    let client: S2Client
    public init(client: S2Client) { self.client = client }

    public func paper(id: String, fields: [String]) async throws -> S2Result {
        let pid = Self.normalizePaperID(id)
        let data = try await get("paper", "\(Self.graph)/paper/\(try Self.segment(pid, endpoint: "paper"))",
                                 fields: fields, subject: pid)
        return S2Result(endpoint: "paper", request: ["id": .string(pid), "fields": Self.list(fields)],
                        total: nil, offset: 0, data: data)
    }

    public func match(title: String, year: String?, fields: [String]) async throws -> S2Result {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw S2ArgumentError.emptyIdentifier(endpoint: "match") }
        var extra = [URLQueryItem(name: "query", value: t)]
        if let year, !year.isEmpty { extra.append(URLQueryItem(name: "year", value: year)) }
        let page = try await get("match", "\(Self.graph)/paper/search/match", fields: fields, extra: extra, subject: t)
        var request: [String: S2JSON] = ["title": .string(t), "fields": Self.list(fields)]
        if let year, !year.isEmpty { request["year"] = .string(year) }
        return S2Result(endpoint: "match", request: request, total: nil, offset: 0,
                        data: page["data"] ?? .array([]))
    }

    public func batch(ids: [String], fields: [String]) async throws -> S2Result {
        guard Self.batchRange.contains(ids.count) else { throw S2ArgumentError.batchSize(ids.count) }
        let normalized = ids.map(Self.normalizePaperID)
        let body = try JSONEncoder().encode(["ids": normalized])
        let request = S2Request(endpoint: "batch", method: .post, path: "\(Self.graph)/paper/batch",
                                query: Self.fieldsQuery(fields), body: body, subject: nil)
        let data = try Self.decode(try await client.send(request), endpoint: "batch")
        return S2Result(endpoint: "batch",
                        request: ["ids": .array(normalized.map(S2JSON.string)), "fields": Self.list(fields)],
                        total: data.arrayValue?.count, offset: 0, data: data)
    }

    public func references(id: String, fields: [String], limit: Int?, offset: Int) async throws -> S2Result {
        try await paperList("references", countField: "referenceCount", id: id, fields: fields, limit: limit, offset: offset)
    }

    public func citations(id: String, fields: [String], limit: Int?, offset: Int) async throws -> S2Result {
        try await paperList("citations", countField: "citationCount", id: id, fields: fields, limit: limit, offset: offset)
    }

    public func recommend(id: String, limit: Int, fields: [String]) async throws -> S2Result {
        guard Self.recommendRange.contains(limit) else {
            throw S2ArgumentError.limitOutOfRange(endpoint: "recommend", limit: limit, range: Self.recommendRange)
        }
        let pid = Self.normalizePaperID(id)
        let page = try await get("recommend",
                                 "\(Self.recommendations)/papers/forpaper/\(try Self.segment(pid, endpoint: "recommend"))",
                                 fields: fields, extra: [URLQueryItem(name: "limit", value: "\(limit)")], subject: pid)
        let records = page["recommendedPapers"] ?? .array([])
        return S2Result(endpoint: "recommend",
                        request: ["id": .string(pid), "limit": .int(limit), "fields": Self.list(fields)],
                        total: records.arrayValue?.count, offset: 0, data: records)
    }

    public func authorSearch(name: String, fields: [String], limit: Int?, offset: Int) async throws -> S2Result {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw S2ArgumentError.emptyIdentifier(endpoint: "author-search") }
        let cap = limit ?? Self.defaultSearchLimit
        let (records, first) = try await paginate("author-search", path: "\(Self.graph)/author/search",
                                                  query: [URLQueryItem(name: "query", value: n)] + Self.fieldsQuery(fields),
                                                  limit: cap, offset: offset, subject: n)
        return S2Result(endpoint: "author-search",
                        request: ["name": .string(n), "limit": .int(cap), "offset": .int(offset), "fields": Self.list(fields)],
                        total: first?["total"]?.intValue, offset: offset, data: .array(records))
    }

    public func authorPapers(id: String, fields: [String], limit: Int?, offset: Int) async throws -> S2Result {
        let aid = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let seg = try Self.segment(aid, endpoint: "author-papers")
        let (records, _) = try await paginate("author-papers", path: "\(Self.graph)/author/\(seg)/papers",
                                              query: Self.fieldsQuery(fields), limit: limit, offset: offset, subject: aid)
        let total = try? await get("author-papers", "\(Self.graph)/author/\(seg)",
                                   fields: ["paperCount"], subject: aid)["paperCount"]?.intValue
        return S2Result(endpoint: "author-papers",
                        request: ["id": .string(aid), "limit": limit.map(S2JSON.int) ?? .null,
                                  "offset": .int(offset), "fields": Self.list(fields)],
                        total: total ?? nil, offset: offset, data: .array(records))
    }

    // MARK: - 內部

    private func paperList(_ endpoint: String, countField: String, id: String, fields: [String],
                           limit: Int?, offset: Int) async throws -> S2Result {
        let pid = Self.normalizePaperID(id)
        let seg = try Self.segment(pid, endpoint: endpoint)
        let (records, _) = try await paginate(endpoint, path: "\(Self.graph)/paper/\(seg)/\(endpoint)",
                                              query: Self.fieldsQuery(fields), limit: limit, offset: offset, subject: pid)
        // total 多花一次請求；失敗時回 nil，資料照回（design〈Implementation Contract〉）。
        let total = try? await get(endpoint, "\(Self.graph)/paper/\(seg)", fields: [countField], subject: pid)[countField]?.intValue
        return S2Result(endpoint: endpoint,
                        request: ["id": .string(pid), "limit": limit.map(S2JSON.int) ?? .null,
                                  "offset": .int(offset), "fields": Self.list(fields)],
                        total: total ?? nil, offset: offset, data: .array(records))
    }

    /// 照 `next` 翻頁，直到結果或 `limit` 用盡；`next` 沒有前進時停下，不會無限迴圈。
    private func paginate(_ endpoint: String, path: String, query: [URLQueryItem], limit: Int?, offset: Int,
                          subject: String) async throws -> ([S2JSON], S2JSON?) {
        guard offset >= 0 else { throw S2ArgumentError.negativeOffset(offset) }
        if let limit, limit < 1 {
            throw S2ArgumentError.limitOutOfRange(endpoint: endpoint, limit: limit, range: 1...Int.max)
        }
        var records: [S2JSON] = []
        var cursor = offset
        var first: S2JSON?
        while true {
            let want = limit.map { Swift.min(Self.pageSize, $0 - records.count) } ?? Self.pageSize
            guard want > 0 else { break }
            let q = query + [URLQueryItem(name: "offset", value: "\(cursor)"),
                             URLQueryItem(name: "limit", value: "\(want)")]
            let page = try Self.decode(try await client.send(
                S2Request(endpoint: endpoint, path: path, query: q, subject: subject)), endpoint: endpoint)
            if first == nil { first = page }
            let items = page["data"]?.arrayValue ?? []
            records.append(contentsOf: items.prefix(want))
            guard let next = page["next"]?.intValue, next > cursor, !items.isEmpty else { break }
            cursor = next
        }
        return (records, first)
    }

    private func get(_ endpoint: String, _ path: String, fields: [String], extra: [URLQueryItem] = [],
                     subject: String?) async throws -> S2JSON {
        let request = S2Request(endpoint: endpoint, path: path, query: extra + Self.fieldsQuery(fields), subject: subject)
        return try Self.decode(try await client.send(request), endpoint: endpoint)
    }

    static func decode(_ data: Data, endpoint: String) throws -> S2JSON {
        do { return try JSONDecoder().decode(S2JSON.self, from: data) } catch {
            throw S2Error.invalidResponse(endpoint: endpoint)
        }
    }

    static func fieldsQuery(_ fields: [String]) -> [URLQueryItem] {
        let f = fields.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return f.isEmpty ? [] : [URLQueryItem(name: "fields", value: f.joined(separator: ","))]
    }

    static func list(_ fields: [String]) -> S2JSON { .array(fields.map(S2JSON.string)) }

    /// 以 `10.` 開頭的裸 DOI 補上 `DOI:`。
    static func normalizePaperID(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("10.") ? "DOI:" + t : t
    }

    /// 識別碼的路徑編碼：保留 `/` 與 `:`（S2 官方範例的 DOI 路徑不編碼 `/`），`?`、`#`、`%`、
    /// 空白等一律編碼。含 `.` 或 `..` 路徑片段的識別碼拒絕——正規化後可能指到別的端點。
    static func segment(_ raw: String, endpoint: String) throws -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw S2ArgumentError.emptyIdentifier(endpoint: endpoint) }
        if t.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) {
            throw S2ArgumentError.invalidIdentifier(endpoint: endpoint, identifier: raw)
        }
        // `urlPathAllowed` 不含 `:`，但 S2 的識別碼語法（`DOI:…`、`CorpusId:…`）需要它原樣出現。
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: ":"))
        guard let encoded = t.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw S2ArgumentError.invalidIdentifier(endpoint: endpoint, identifier: raw)
        }
        return encoded
    }
}
