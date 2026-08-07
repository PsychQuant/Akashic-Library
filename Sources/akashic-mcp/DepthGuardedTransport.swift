import Foundation
import Logging
import MCP

/// 入站訊息的巢狀深度預檢（#152）。
///
/// SDK 的 `Value` 是遞迴 Codable——約 200–700 層巢狀的 JSON-RPC 訊息在
/// JSONDecoder 解 `Value` 時炸掉遞迴堆疊，**整個 server 進程無聲死亡**（stdout
/// 關閉、stderr 空、無回應），與 tool 名稱、schema、值有沒有被讀到無關——crash
/// 在所有 handler 的上游（#148 verify R2 的定位矩陣：unknown tool＋深巢狀照樣死）。
/// SDK transport 自己的 parse 守衛約 800 層才擋，**比它保護的程式碼還鬆**，留下
/// 撞毀窗口。
///
/// 修法：在 **raw bytes 層**數 nesting 深度（引號感知、不 parse），超限的訊息不
/// 交給 server，改回 JSON-RPC error——服務層的深度上限（#148 的 64）是第二道
/// defence in depth，這裡是第一道。
actor DepthGuardedTransport: Transport {
    nonisolated let logger: Logger

    /// 128：SDK 撞毀窗口的下緣約 200，合法 MCP 訊息（tool schema + fields）
    /// 深度個位數——128 給足餘裕又遠離窗口。
    static let maxDepth = 128

    private let inner: StdioTransport

    init(wrapping inner: StdioTransport,
         logger: Logger = Logger(label: "akashic-mcp.depth-guard")) {
        self.inner = inner
        self.logger = logger
    }

    func connect() async throws { try await inner.connect() }
    func disconnect() async { await inner.disconnect() }
    func send(_ data: Data) async throws { try await inner.send(data) }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let inner = self.inner
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in await inner.receive() {
                        if Self.nestingDepth(of: data, cap: Self.maxDepth + 1) > Self.maxDepth {
                            // 超限：不往下送（下游會炸），直接回 error。id 盡力而為地
                            // 淺層抽取——抽不到就 null（JSON-RPC 對無法可靠讀出 id 的
                            // 無效請求允許 id: null）。
                            let id = Self.shallowRequestID(of: data) ?? "null"
                            let reply = #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32600,"message":"request nesting depth exceeds \#(Self.maxDepth) — no valid tool call has this shape"}}"#
                            try? await self.send(Data(reply.utf8))
                            continue
                        }
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 位元組層的最大巢狀深度（`[`／`{`）。**引號感知**：字串字面量內的括號不算
    /// （`"a[["` 不增加深度），backslash escape 正確跳過。`cap` 讓超長攻擊訊息
    /// 提早返回，不必掃完。
    static func nestingDepth(of data: Data, cap: Int = Int.max) -> Int {
        var depth = 0, maxDepth = 0
        var inString = false, escaped = false
        for byte in data {
            if escaped { escaped = false; continue }
            switch byte {
            case UInt8(ascii: "\\") where inString: escaped = true
            case UInt8(ascii: "\""): inString.toggle()
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                if !inString {
                    depth += 1
                    if depth > maxDepth {
                        maxDepth = depth
                        if maxDepth >= cap { return maxDepth }
                    }
                }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                if !inString { depth -= 1 }
            default: break
            }
        }
        return maxDepth
    }

    /// 頂層 `"id"` 的抽取：**只在深度 0（不在任何 `{`/`[` 內）掃描**——攻擊訊息的
    /// `id` 若埋在巢狀裡（`params.arguments.id`）不得誤抓（#153 verify F1：regex
    /// 抓全文第一個匹配、無深度概念，會回錯 id）。回傳 JSON-RPC 合法的 id token
    /// （整數或字串字面量）；抽不到（float `1.5`、id 只在深層、或含控制字元）回 nil，
    /// 呼叫端用 `"null"`。
    ///
    /// 字串 id 內容排除控制字元（#153 verify F2，MEDIUM）：`"x\u{09}y"` 這類 id
    /// 直接內插會讓 error 回覆變成非法 JSON（RFC 8259 要求 U+0000–001F 跳脫），
    /// 守衛「回乾淨 error 而非死掉」的目的落空——含控制字元即回 nil。
    static func shallowRequestID(of data: Data) -> String? {
        let chars = Array(data)
        let q = UInt8(ascii: "\""), bs = UInt8(ascii: "\\")
        var depth = 0, inString = false, escaped = false
        var i = 0
        while i + 3 < chars.count {
            let c = chars[i]
            if escaped { escaped = false; i += 1; continue }
            if inString {
                if c == bs { escaped = true } else if c == q { inString = false }
                i += 1; continue
            }
            if c == q {
                // 頂層物件的直接成員在 `{` 之後 ＝ depth 1（不是 0）；巢狀的
                // `params.arguments.id` 在 depth ≥ 3——只認 depth 1 的 "id"
                if depth == 1,
                   chars[i+1] == UInt8(ascii: "i"), chars[i+2] == UInt8(ascii: "d"),
                   chars[i+3] == q {
                    return Self.idValue(chars, after: i + 4)
                }
                inString = true
            } else if c == UInt8(ascii: "[") || c == UInt8(ascii: "{") {
                depth += 1
            } else if c == UInt8(ascii: "]") || c == UInt8(ascii: "}") {
                depth -= 1
            }
            i += 1
        }
        return nil
    }

    /// `"id"` 之後的 value token（跳過 `:` 與空白）。整數或乾淨字串字面量；其餘 nil。
    private static func idValue(_ chars: [UInt8], after start: Int) -> String? {
        let sp = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), q = UInt8(ascii: "\"")
        var j = start
        while j < chars.count, chars[j] == sp || chars[j] == tab { j += 1 }
        guard j < chars.count, chars[j] == UInt8(ascii: ":") else { return nil }
        j += 1
        while j < chars.count, chars[j] == sp || chars[j] == tab { j += 1 }
        guard j < chars.count else { return nil }
        if chars[j] == q {
            var k = j + 1
            var buf: [UInt8] = [q]
            while k < chars.count, k < j + 1 + 64 {
                let c = chars[k]
                if c == q { buf.append(c); return String(decoding: buf, as: UTF8.self) }
                if c == UInt8(ascii: "\\") || c < 0x20 { return nil }   // escape/控制字元→放棄
                buf.append(c); k += 1
            }
            return nil
        }
        // 整數 id（含負號）；float／其他 → nil
        var k = j
        if chars[k] == UInt8(ascii: "-") { k += 1 }
        var digits: [UInt8] = []
        while k < chars.count, chars[k] >= UInt8(ascii: "0"), chars[k] <= UInt8(ascii: "9") {
            digits.append(chars[k]); k += 1
        }
        guard !digits.isEmpty else { return nil }
        if k < chars.count {
            let n = chars[k]
            let ok = n == UInt8(ascii: ",") || n == UInt8(ascii: "}") || n == sp || n == tab
                || n == UInt8(ascii: "\n") || n == UInt8(ascii: "\r")
            guard ok else { return nil }   // `1.5` 的 `.` 落此
        }
        let sign = chars[j] == UInt8(ascii: "-") ? "-" : ""
        return sign + String(decoding: digits, as: UTF8.self)
    }
}
