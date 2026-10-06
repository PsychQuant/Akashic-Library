import AkashicCore
import Foundation

/// MCP 工具 `akashic_s2` 的參數（由 server 依型別規則從 MCP 的值轉來）。
public struct S2ToolArguments: Sendable, Equatable {
    public var endpoint: String
    public var id: String?
    public var title: String?
    public var year: String?
    public var name: String?
    public var ids: [String]?
    public var fields: [String]?
    public var offset: Int?
    public var limit: Int?

    public init(endpoint: String, id: String? = nil, title: String? = nil, year: String? = nil, name: String? = nil,
                ids: [String]? = nil, fields: [String]? = nil, offset: Int? = nil, limit: Int? = nil) {
        self.endpoint = endpoint; self.id = id; self.title = title; self.year = year; self.name = name
        self.ids = ids; self.fields = fields; self.offset = offset; self.limit = limit
    }
}

public struct S2ToolOutcome: Sendable, Equatable {
    public let text: String
    public let isError: Bool
}

/// MCP 面（design〈MCP 面的 async 路徑〉）：與 CLI 共用 `AkashicS2`，不經 `AkashicService`、不開 store。
/// 成功回 `S2Output.mcpPage` 的 JSON；錯誤回與 CLI 同一個函式產出的文字（`displaySafeErrorMultiline`）。
public enum S2Tool {
    public static let endpointNames = ["paper", "match", "batch", "references", "citations", "recommend",
                                       "author_search", "author_papers", "status"]
    /// 分頁端點在 MCP 預設一次向 S2 要的筆數——一個呼叫不拉回上千筆，其餘以 nextOffset 續查。
    public static let defaultPageLimit = 100

    public static func run(_ args: S2ToolArguments,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           session: URLSession = S2Client.defaultSession,
                           budget: Int = S2Output.mcpByteBudget) async -> S2ToolOutcome {
        do {
            guard endpointNames.contains(args.endpoint) else {
                throw S2ArgumentError.unknownEndpoint(displaySafeInvisible(args.endpoint))
            }
            let settings = try S2Settings.resolve(environment: environment)
            if args.endpoint == "status" {
                let probe = settings.readsKeychain ? S2KeychainKeyProvider(settings: settings).probe() : nil
                return S2ToolOutcome(text: S2Output.statusJSON(settings: settings, probe: probe), isError: false)
            }
            let client = S2Client(settings: settings, keyProvider: S2KeychainKeyProvider(settings: settings),
                                  throttle: S2FileThrottle(stateDirectory: settings.stateDirectory), session: session)
            let result = try await call(S2Endpoints(client: client), args)
            let page = S2Output.mcpPage(result, budget: budget)
            if page.returned == 0 && page.truncated {
                throw S2OutputError.recordExceedsBudget(endpoint: displaySafeInvisible(args.endpoint), kib: budget / 1024)   // display-safe-exempt: budget / 1024 是 Int
            }
            return S2ToolOutcome(text: page.text, isError: false)
        } catch {
            return S2ToolOutcome(text: displaySafeErrorMultiline(error, prefix: "Error: "), isError: true)
        }
    }

    static func call(_ e: S2Endpoints, _ a: S2ToolArguments) async throws -> S2Result {
        func need(_ v: String?, _ name: String) throws -> String {
            guard let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw S2ArgumentError.missingArgument(endpoint: displaySafeInvisible(a.endpoint), name: displaySafeInvisible(name))
            }
            return v
        }
        let paperFields = a.fields ?? S2Endpoints.defaultPaperFields
        let offset = a.offset ?? 0
        let limit = a.limit ?? defaultPageLimit
        // 分頁端點的 limit 上限是 S2 的一頁（1000）：一個呼叫要的**筆數**有界。**請求數**則不保證只有一兩個：S2 照常回滿頁時是一個翻頁請求，references／citations／author_papers 另加一個取 total 的請求（author_search 的 total 取自第一頁，沒有另外的請求）；
        // 若 S2 一頁只回一筆，`paginate` 照 `next` 一路翻，最壞約 1000 個請求（全機每秒 1 次，約 17 分鐘）。有界，但不是「不會好幾分鐘」。
        if ["references", "citations", "author_search", "author_papers"].contains(a.endpoint),
           !(1...S2Endpoints.pageSize).contains(limit) {
            throw S2ArgumentError.limitOutOfRange(endpoint: displaySafeInvisible(a.endpoint), limit: limit, min: 1, max: S2Endpoints.pageSize)   // display-safe-exempt: limit 是 Int；S2Endpoints.pageSize 是 Int 常量
        }
        switch a.endpoint {
        case "paper": return try await e.paper(id: need(a.id, "id"), fields: paperFields)
        case "match": return try await e.match(title: need(a.title, "title"), year: a.year, fields: paperFields)
        case "batch": return try await e.batch(ids: a.ids ?? [], fields: paperFields)
        case "references": return try await e.references(id: need(a.id, "id"), fields: paperFields, limit: limit, offset: offset)
        case "citations": return try await e.citations(id: need(a.id, "id"), fields: paperFields, limit: limit, offset: offset)
        case "recommend": return try await e.recommend(id: need(a.id, "id"), limit: limit, fields: paperFields)
        case "author_search":
            return try await e.authorSearch(name: need(a.name, "name"), fields: a.fields ?? S2Endpoints.defaultAuthorFields,
                                            limit: limit, offset: offset)
        case "author_papers": return try await e.authorPapers(id: need(a.id, "id"), fields: paperFields, limit: limit, offset: offset)
        default: throw S2ArgumentError.unknownEndpoint(displaySafeInvisible(a.endpoint))
        }
    }
}
