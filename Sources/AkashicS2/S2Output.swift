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
