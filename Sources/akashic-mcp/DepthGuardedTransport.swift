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

    /// 淺層 id 抽取：頂層 `"id"` 鍵後的 scalar（數字或字串），只在深度 1 找——
    /// 攻擊訊息的 id 通常在頂層，抽得到就回給正確的請求。抽不到回 nil。
    static func shallowRequestID(of data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // 只信頂層形狀 `"id":<space>*<number 或 "string">`——夠淺、夠保守
        let pattern = #""id"\s*:\s*(-?\d+|"[^"\\]{0,64}")"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        let m = String(text[r])
        guard let colon = m.firstIndex(of: ":") else { return nil }
        return String(m[m.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
}
