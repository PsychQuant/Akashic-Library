import AkashicCore
import Foundation

/// 字串 payload 在擲出端逃脫一次，描述原樣組句（#554）。
public enum S2OutputError: Error, Equatable, CustomStringConvertible, SanitizedErrorDescription {
    /// 第一筆就放不進 MCP 的位元組上限：不能回「成功、0 筆」——那會讓續查永遠原地踏步。
    case recordExceedsBudget(endpoint: String, kib: Int)

    public var description: String {
        switch self {
        case .recordExceedsBudget(let endpoint, let kib):
            return "\(endpoint) 的第一筆就超過 MCP 結果的 \(kib) KiB 上限：請用 fields 減少欄位（例如拿掉 abstract、authors），或改用 CLI（akashic s2 …）"   // display-safe-exempt: endpoint 擲出端已 displaySafeInvisible；kib 是 Int
        }
    }
}

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
                 total: result.total, offset: result.offset, data: sanitized(result.data), hasMore: result.hasMore)
    }

    /// JSON 面（CLI `--json`、MCP、`status --json`）的字串處理：只截斷長度，**不改寫任何字元**——逃脫在序列化之後、
    /// 對整份 JSON 文字做（`jsonText`）。終端機用的 `displaySafe` 把反斜線改成字面的 `\u{005C}`、連不換行空格與軟連字號
    /// 也改掉；`displaySafeClipOnly` 仍把殘留的控制／方向字元改成字面的 `\u{…}`。兩者在 JSON 面都解不回來，而反斜線、
    /// 不換行空格、軟連字號都是書目標題的正當內容（#664 verify R1）。
    public static func clipped(_ json: S2JSON) -> S2JSON {
        switch json {
        case .string(let s):
            return .string(clip(s))
        case .array(let a):
            return .array(a.map(clipped))
        case .object(let o):
            var out: [String: S2JSON] = [:]
            for (k, v) in o { out[clip(k)] = clipped(v) }
            return .object(out)
        case .null, .bool, .int, .double:
            return json
        }
    }

    /// 超過 `stringLimit` 個 scalar 就截斷並附上標記；不動其他任何字元。
    static func clip(_ s: String) -> String {
        guard s.unicodeScalars.count > stringLimit else { return s }
        return String(String.UnicodeScalarView(s.unicodeScalars.prefix(stringLimit))) + "…（已截斷）"
    }

    public static func clipped(_ result: S2Result) -> S2Result {
        S2Result(endpoint: result.endpoint, request: result.request.mapValues(clipped),
                 total: result.total, offset: result.offset, data: clipped(result.data), hasMore: result.hasMore)
    }

    /// 編碼後把字串字面值內的危險 scalar 改寫成 JSON 自己的 `\uXXXX`（`documentSafeJSON`，與 CSL-JSON 出口同一個函式）。
    /// 無損：解碼後就是原字元；輸出文字裡不會出現方向覆寫、控制字元等原樣的危險 scalar。
    static func jsonText<T: Encodable>(_ value: T) -> String? {
        (try? encoder().encode(value)).map { documentSafeJSON(String(decoding: $0, as: UTF8.self)) }
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
        let clean = clipped(result)
        let records: [S2JSON]
        if case .array(let a) = clean.data { records = a } else { records = [clean.data] }
        // 量的是**實際輸出**的位元組數：`\uXXXX` 改寫會讓文字變長，不能拿改寫前的大小去算。
        let sizes = records.map { jsonText($0)?.utf8.count ?? Int.max / 4 }

        // 續查的訊號：有 `nextOffset` 就用它當下一次的 `offset`，null 就是沒有下一頁。
        // - 不分頁的端點（`hasMore` 為 nil）永遠 null：它們不接 `offset`，給了也會被忽略、讓呼叫者拿到同一頁。
        // - 空的一頁永遠 null：`nextOffset == offset` 是定點。
        // - 被位元組上限截斷：從沒放進去的那一筆接著；否則看 S2 自己有沒有下一頁，**不看 `total`**（#664 verify R1）。
        func nextOffset(_ n: Int) -> Int? {
            guard let hasMore = clean.hasMore, n > 0 else { return nil }
            if n < records.count { return clean.offset + n }
            return hasMore ? clean.offset + n : nil
        }
        func envelope(_ kept: [S2JSON], _ n: Int) -> MCPEnvelope {
            MCPEnvelope(data: kept, endpoint: clean.endpoint, nextOffset: nextOffset(n), offset: clean.offset,
                        returned: n, total: clean.total, truncated: n < records.count)
        }
        // 外框在 `data` 為空時的大小；放入 n 筆後的大小 = 外框 + 各筆大小 + (n − 1) 個逗號。
        func emptyEnvelopeSize(_ n: Int) -> Int { jsonText(envelope([], n))?.utf8.count ?? Int.max / 4 }

        var n = 0
        var dataBytes = 0
        while n < records.count {
            let add = sizes[n] + (n > 0 ? 1 : 0)
            if emptyEnvelopeSize(n + 1) + dataBytes + add > budget { break }
            dataBytes += add
            n += 1
        }
        let final = envelope(Array(records.prefix(n)), n)
        let text = jsonText(final) ?? "{}"
        return S2MCPPage(text: text, returned: n, truncated: final.truncated, nextOffset: final.nextOffset)
    }
}

// MARK: - CLI 面（任務 5.1）

extension S2Output {
    /// `status` 的 JSON（CLI `--json` 與 MCP 共用）。不連網；**不含金鑰，也不含它的長度**。
    /// 請求不送 S2 主機時（base URL 覆寫）不讀 keychain，`present`／`readable` 為 null。
    public static func statusJSON(settings: S2Settings, probe: S2KeyProbe?) -> String {
        let throttle = S2FileThrottle(stateDirectory: settings.stateDirectory)
        let keychain: S2JSON = .object([
            "service": .string(settings.keychainService), "account": .string(settings.keychainAccount),   // display-safe-exempt: string(settings.keychainService／keychainAccount) 是常量或已驗證的 akashic-test- 名稱，整份輸出再經 clipped＋jsonText（documentSafeJSON）
            "present": probe.map { .bool($0.present) } ?? .null,
            "readable": probe.map { .bool($0.readable) } ?? .null,
        ])
        let out: S2JSON = .object([
            "keychain": keychain,
            "throttle": .object(["stateFile": .string(throttle.stateFile.path),
                                 "nextAllowedAt": throttle.peekNextAllowedAt().map { .string(timestamp($0)) } ?? .null]),
            "host": .string(settings.baseURL.host ?? ""),
        ])
        return jsonText(clipped(out)) ?? "{}"
    }

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

    /// `--json` 的輸出。傳入**原始**的結果：JSON 面不用 `sanitized`（那是終端機用的），清理在這裡做（`clipped`＋`jsonText`）。
    public static func cliJSON(_ result: S2Result, fetchedAt: Date) -> String {
        let clean = clipped(result)
        let env = CLIEnvelope(data: clean.data, endpoint: clean.endpoint, fetchedAt: timestamp(fetchedAt),
                              request: clean.request, total: clean.total)
        return jsonText(env) ?? "{}"
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
