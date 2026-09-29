import AkashicCore
import Foundation

/// MCP 面的一頁結果。`text` 就是要交給 MCP 呼叫端的 JSON。
public struct S2MCPPage: Sendable, Equatable {
    public let text: String
    public let returned: Int
    public let truncated: Bool
    public let nextOffset: Int?
}

/// S2 回應的輸出處理：外部字串清理與 MCP 的位元組上限（design〈兩個面都做，MCP 面有位元組上限〉）。
public enum S2Output {
    /// 與 `akashic_doctor` 的 `candidateByteBudget` 同值（48 KiB）。
    public static let mcpByteBudget = 48 * 1024
    /// 單一字串的清理上限。S2 的摘要可以很長，不沿用 `displaySafe` 預設的 200。
    public static let stringLimit = 100_000

    /// 遞迴清理 S2 回應中的每個字串（含物件的 key）。控制字元、方向覆寫、不可見字元與
    /// 反斜線都換成字面的 `\u{…}`——與 CLI 其他輸出同一個 `displaySafe`。
    public static func sanitized(_ json: S2JSON) -> S2JSON {
        switch json {
        case .string(let s):
            return .string(displaySafe(s, max: stringLimit))
        case .array(let a):
            return .array(a.map(sanitized))
        case .object(let o):
            var out: [String: S2JSON] = [:]
            for (k, v) in o { out[displaySafe(k, max: stringLimit)] = sanitized(v) }
            return .object(out)
        case .null, .bool, .int, .double:
            return json
        }
    }

    public static func sanitized(_ result: S2Result) -> S2Result {
        S2Result(endpoint: result.endpoint, request: result.request.mapValues(sanitized),
                 total: result.total, offset: result.offset, data: sanitized(result.data))
    }

    /// 所有 S2 輸出共用的 JSON 格式：鍵排序、不跳脫斜線、不縮排。
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// MCP 回傳的外框。欄位依 spec：`endpoint`、`total`、`returned`、`truncated`、`offset`、
    /// `nextOffset`、`data`；沒有值的欄位明確寫出 `null`。
    struct MCPEnvelope: Encodable {
        let data: [S2JSON]
        let endpoint: String
        let nextOffset: Int?
        let offset: Int
        let returned: Int
        let total: Int?
        let truncated: Bool

        enum CodingKeys: String, CodingKey { case data, endpoint, nextOffset, offset, returned, total, truncated }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(data, forKey: .data)
            try c.encode(endpoint, forKey: .endpoint)
            try c.encode(nextOffset, forKey: .nextOffset)
            try c.encode(offset, forKey: .offset)
            try c.encode(returned, forKey: .returned)
            try c.encode(total, forKey: .total)
            try c.encode(truncated, forKey: .truncated)
        }
    }

    /// 只放完整的筆數：逐筆加入，每加一筆就算整份輸出的實際位元組數，會超過 `budget` 就停在前一筆。
    /// 單篇查詢（`data` 是物件）視為一筆。
    public static func mcpPage(_ result: S2Result, budget: Int = mcpByteBudget) -> S2MCPPage {
        let clean = sanitized(result)
        let records: [S2JSON]
        if case .array(let a) = clean.data { records = a } else { records = [clean.data] }
        let enc = encoder()
        let sizes = records.map { (try? enc.encode($0).count) ?? Int.max / 4 }

        func nextOffset(_ n: Int) -> Int? {
            if n < records.count { return clean.offset + n }
            if let total = clean.total, total > clean.offset + n { return clean.offset + n }
            return nil
        }
        func envelope(_ kept: [S2JSON], _ n: Int) -> MCPEnvelope {
            MCPEnvelope(data: kept, endpoint: clean.endpoint, nextOffset: nextOffset(n), offset: clean.offset,
                        returned: n, total: clean.total, truncated: n < records.count)
        }
        // 外框在 `data` 為空時的大小；放入 n 筆後的大小 = 外框 + 各筆大小 + (n − 1) 個逗號。
        func emptyEnvelopeSize(_ n: Int) -> Int { (try? enc.encode(envelope([], n)).count) ?? Int.max / 4 }

        var n = 0
        var dataBytes = 0
        while n < records.count {
            let add = sizes[n] + (n > 0 ? 1 : 0)
            if emptyEnvelopeSize(n + 1) + dataBytes + add > budget { break }
            dataBytes += add
            n += 1
        }
        let final = envelope(Array(records.prefix(n)), n)
        let text = (try? enc.encode(final)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return S2MCPPage(text: text, returned: n, truncated: final.truncated, nextOffset: final.nextOffset)
    }
}

// MARK: - CLI 面（任務 5.1）

extension S2Output {
    /// ISO 8601，帶本機時區 offset（例：`2026-09-29T09:30:00+08:00`）。
    public static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: date)
    }

    struct CLIEnvelope: Encodable {
        let data: S2JSON
        let endpoint: String
        let fetchedAt: String
        let request: [String: S2JSON]
        let source = "semantic-scholar"
        let total: Int?

        enum CodingKeys: String, CodingKey { case data, endpoint, fetchedAt, request, source, total }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(data, forKey: .data)
            try c.encode(endpoint, forKey: .endpoint)
            try c.encode(fetchedAt, forKey: .fetchedAt)
            try c.encode(request, forKey: .request)
            try c.encode(source, forKey: .source)
            try c.encode(total, forKey: .total)
        }
    }

    /// `--json` 的輸出。傳入的 `result` 須已經過 `sanitized`。
    public static func cliJSON(_ result: S2Result, fetchedAt: Date) -> String {
        let env = CLIEnvelope(data: result.data, endpoint: result.endpoint, fetchedAt: timestamp(fetchedAt),
                              request: result.request, total: result.total)
        return (try? encoder().encode(env)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// 人可讀的輸出，與 `--json` 出自同一份（已清理的）結果：標頭一行，之後一筆一行。
    public static func humanReadable(_ result: S2Result) -> String {
        var lines: [String] = []
        let records: [S2JSON]
        if case .array(let a) = result.data { records = a } else { records = [result.data] }
        var header = "\(result.endpoint)：\(records.count) 筆"
        if let total = result.total { header += "（S2 共 \(total) 筆）" }
        lines.append(header)
        for record in records {
            switch result.endpoint {
            case "references": lines.append(paperLine(record["citedPaper"] ?? record))
            case "citations": lines.append(paperLine(record["citingPaper"] ?? record))
            case "author-search": lines.append(authorLine(record))
            default: lines.append(paperLine(record))
            }
        }
        if result.endpoint == "paper", case .object(let o) = result.data {
            for key in o.keys.sorted() where !["paperId", "title", "year", "authors"].contains(key) {
                let value = (try? encoder().encode(o[key]!)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                lines.append("  \(key): \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func string(_ j: S2JSON?) -> String? {
        if case .string(let s)? = j { return s }
        return nil
    }

    /// `年份  標題 — 第一作者 等  [paperId]`。缺的部分省略；null（batch 查不到的 id）印成「(查無此篇)」。
    static func paperLine(_ p: S2JSON) -> String {
        if p == .null { return "(查無此篇)" }
        let year = p["year"]?.intValue.map(String.init) ?? "----"
        var line = "\(year)  \(string(p["title"]) ?? "(無標題)")"
        if let authors = p["authors"]?.arrayValue, let first = string(authors.first?["name"]) {
            line += " — \(first)" + (authors.count > 1 ? " 等" : "")
        }
        if let id = string(p["paperId"]) { line += "  [\(id)]" }
        return line
    }

    /// `姓名  [authorId]  papers=N`。
    static func authorLine(_ a: S2JSON) -> String {
        var line = string(a["name"]) ?? "(無姓名)"
        if let id = string(a["authorId"]) { line += "  [\(id)]" }
        if let n = a["paperCount"]?.intValue { line += "  papers=\(n)" }
        return line
    }
}
