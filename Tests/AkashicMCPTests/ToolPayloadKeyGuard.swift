import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// **工具描述必須跟得上 payload——全部工具，不只 `akashic_resolve_people`**（#672）。
///
/// MCP 呼叫端（LLM）讀不到 CLI `--help`：`tools/list` 的說明文字是它決定「回應要讀哪些鍵」的唯一依據。
/// #578 把描述精簡之後，多數工具的回應鍵只剩一句「見 CLI help」；描述與實際 payload 分岔時，
/// 先前只有 `resolve_people` 一個工具有守衛（`ServiceTests` 那條只掃它，而且只看原始碼裡宣告後的前 3,000 字元）。
///
/// 做法（`ToolPayloadKeyGuardTests`）：
/// 1. **說明文字取自真 binary 的 `tools/list`**，不讀原始碼——字串插值與 `+` 串接在原始碼裡不是呼叫端看到的樣子。
/// 2. **payload 取自真實呼叫**：每個工具在 fixture store 上走各條主要的腿（`ToolPayloadScenarios`），
///    回應 JSON 的頂層鍵（物件）或元素鍵（陣列）取聯集。
/// 3. 每個鍵必須以**識別字邊界**出現在該工具的說明文字裡——子字串比對會讓 `key`、`total` 這類短鍵被別的字滿足。
/// 4. 刻意不寫進說明的鍵，在 `ToolPayloadKeyExemptions` 逐一具名並寫理由；豁免本身也有守衛（豁免的鍵必須真的出現在
///    payload、且真的沒被說明提到，否則紅——不留下過期的豁免）。
///
/// **「說明文字」的範圍**：該工具在 `tools/list` 的全部說明——`description` 加上各參數的 `description`（`Tool.searchable`）。
/// 呼叫端讀得到的就是這兩處；只認 `description` 會逼參數說明裡已經寫著的回報鍵（例如 `add_names` 說「回報 namesAdded…」）
/// 在描述裡再寫一遍，而 #578 的位元組預算裝不下重複。要改成只認 `description`，改 `searchable` 一處即可。
struct ToolManifest {
    struct Tool {
        let name: String
        /// 工具的 `description` 全文。
        let text: String
        /// 所有參數（含巢狀）的 `description`。
        let parameterText: String
        /// 守衛比對的對象：呼叫端在 `tools/list` 讀得到的、關於這個工具的全部說明。
        var searchable: String { text + "\n" + parameterText }
    }

    /// 真 binary 的 `tools/list`。空清單不是通過——找不到 binary 或讀不到回應一律丟錯。
    static func load() throws -> [String: Tool] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("akashic-manifest-\(UUID().uuidString)")
        let library = dir.appendingPathComponent("library")
        try fm.createDirectory(at: dir.appendingPathComponent("home"), withIntermediateDirectories: true)
        try LibraryStore(root: library).ensureLayout()
        defer { try? fm.removeItem(at: dir) }

        var products: URL?
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            products = bundle.bundleURL.deletingLastPathComponent()
            break
        }
        guard let products else { throw ManifestError.noProductsDirectory }
        let binary = products.appendingPathComponent("akashic-mcp")
        guard fm.isExecutableFile(atPath: binary.path) else { throw ManifestError.noBinary(binary.path) }

        let process = Process()
        process.executableURL = binary
        process.environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("AKASHIC_") }   // 不與開發機 registry 耦合（同 StdioE2ETests，#105）
            .merging(["AKASHIC_LIBRARY": library.path, "AKASHIC_HOME": dir.appendingPathComponent("home").path]) { _, new in new }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        defer { process.terminate() }

        let fd = stdout.fileHandleForReading.fileDescriptor
        StdioE2ETests.setNonBlocking(fd)
        var pending = Data()
        func send(_ obj: [String: Any]) throws {
            stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: obj))
            stdin.fileHandleForWriting.write(Data("\n".utf8))
        }
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "payload-key-guard", "version": "0"]]])
        _ = try StdioE2ETests.readLine(fd: fd, pending: &pending, timeout: 10)
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let line = try StdioE2ETests.readLine(fd: fd, pending: &pending, timeout: 10)
        let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        guard obj?["id"] as? Int == 2,
              let tools = (obj?["result"] as? [String: Any])?["tools"] as? [[String: Any]], !tools.isEmpty
        else { throw ManifestError.badResponse }

        var out: [String: Tool] = [:]
        for t in tools {
            guard let name = t["name"] as? String else { continue }
            out[name] = Tool(name: name, text: t["description"] as? String ?? "",
                             parameterText: descriptions(in: t["inputSchema"]).joined(separator: "\n"))
        }
        return out
    }

    enum ManifestError: Error, CustomStringConvertible {
        case noProductsDirectory, noBinary(String), badResponse
        var description: String {
            switch self {
            case .noProductsDirectory: return "找不到 xctest 的 products directory"
            case .noBinary(let p): return "找不到 akashic-mcp（\(p)）——先 swift build"
            case .badResponse: return "tools/list 的回應不是預期的形狀，或工具清單是空的（空掃描不是通過）"
            }
        }
    }

    /// inputSchema 裡每一個字串型的 `description`（遞迴）。
    private static func descriptions(in node: Any?) -> [String] {
        if let dict = node as? [String: Any] {
            var out: [String] = []
            for (k, v) in dict {
                if k == "description", let s = v as? String { out.append(s) } else { out += descriptions(in: v) }
            }
            return out
        }
        if let arr = node as? [Any] { return arr.flatMap { descriptions(in: $0) } }
        return []
    }
}

/// 鍵是否以**識別字**出現在文字裡：前後都不能是 ASCII 字母、數字、底線。
/// 子字串比對會讓 `key` 被 `keys`、`total` 被 `itemsTotal`、`id` 被 `provided` 滿足——而那正是這個守衛要擋的失敗。
func mentionsIdentifier(_ text: String, _ key: String) -> Bool {
    guard !key.isEmpty else { return false }
    func isIdent(_ c: Character) -> Bool { c == "_" || (c.isASCII && (c.isLetter || c.isNumber)) }
    var search = text.startIndex..<text.endIndex
    while let r = text.range(of: key, options: .literal, range: search) {
        let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
        let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
        if !(before.map(isIdent) ?? false) && !(after.map(isIdent) ?? false) { return true }
        search = r.upperBound..<text.endIndex
    }
    return false
}

/// 一次真實呼叫的結果：頂層鍵（物件）或元素鍵（陣列），或非結構化文字。
enum PayloadShape: Equatable {
    case object(keys: Set<String>)
    case array(elementKeys: Set<String>)
    case text

    static func of(_ raw: String) -> PayloadShape {
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else { return .text }
        if let dict = any as? [String: Any] { return .object(keys: Set(dict.keys)) }
        if let arr = any as? [[String: Any]] { return .array(elementKeys: arr.reduce(into: Set<String>()) { $0.formUnion($1.keys) }) }
        return .text
    }

    var scenarioKind: PayloadScenario.Kind {
        switch self {
        case .object: return .object
        case .array: return .array
        case .text: return .text
        }
    }

    var keys: Set<String> {
        switch self {
        case .object(let k): return k
        case .array(let k): return k
        case .text: return []
        }
    }
}
