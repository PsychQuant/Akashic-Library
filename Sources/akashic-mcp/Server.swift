import Foundation
import MCP
import AkashicMCPKit
import AkashicStoreIO

/// akashic-mcp — Akashic-Library 的 MCP 工具面（Phase 2）。
/// 讀走 index；寫只碰衍生層（akashic namespace／人物解析／庫外 entry／import 觸發）。
actor AkashicMCPServer {
    private let server: Server
    private let transport: StdioTransport
    private let service: AkashicService

    init() throws {
        let root = try LibraryLocator.resolve(explicit: nil)
        service = AkashicService(root: root)
        server = Server(
            name: "akashic-mcp",
            version: "0.1.0",
            capabilities: .init(tools: .init()))
        transport = StdioTransport()
    }

    func run() async throws {
        await registerHandlers()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Schema 小工具

    private static func obj(_ props: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(props),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    private static func str(_ desc: String) -> Value {
        .object(["type": .string("string"), "description": .string(desc)])
    }

    private static func int(_ desc: String) -> Value {
        .object(["type": .string("integer"), "description": .string(desc)])
    }

    private static func strArray(_ desc: String) -> Value {
        .object(["type": .string("array"), "items": .object(["type": .string("string")]),
                 "description": .string(desc)])
    }

    // MARK: - Tools

    static let tools: [Tool] = [
        Tool(name: "akashic_search",
             description: "搜尋文獻庫（欄位篩選；全走本地 index）。回傳 citekey/type/title/year/journal/authors 的 JSON 陣列。",
             inputSchema: obj([
                "author": str("作者：person key 完全命中或姓名子字串"),
                "journal": str("期刊名（case-insensitive 完全命中）"),
                "tag": str("tag 完全命中"),
                "type": str("biblatex entry type（article/book/…）"),
                "year_from": int("起始年"),
                "year_to": int("結束年"),
                "library": str("library key 篩選（#13 membership views；省略＝全集）"),
             ])),
        Tool(name: "akashic_get_entry",
             description: "以 citekey 取完整 entry（含 akashic namespace 與 provenance）。",
             inputSchema: obj(["citekey": str("citekey")], required: ["citekey"])),
        Tool(name: "akashic_relations",
             description: "關係查詢：same-journal / same-author / cites / cited-by / related。",
             inputSchema: obj([
                "citekey": str("中心 citekey"),
                "kind": str("same-journal | same-author | cites | cited-by | related"),
             ], required: ["citekey", "kind"])),
        Tool(name: "akashic_graph",
             description: "以某篇文章為中心的關係圖（Mermaid/DOT/GraphML 文字；Mermaid 可直接渲染）。",
             inputSchema: obj([
                "focus": str("中心 citekey"),
                "depth": int("鄰域深度（預設 1）"),
                "format": str("mermaid | dot | graphml（預設 mermaid）"),
             ], required: ["focus"])),
        Tool(name: "akashic_export",
             description: "匯出 .bib 或 CSL-JSON（編譯產物；不帶 citekeys 則全庫）。",
             inputSchema: obj([
                "citekeys": strArray("要匯出的 citekeys（省略＝全庫）"),
                "format": str("bib | csl-json（預設 bib）"),
             ])),
        Tool(name: "akashic_people",
             description: "人物實體列表／查詢（key、aliases、ORCID）。",
             inputSchema: obj(["query": str("關鍵字（比對 key 與所有 alias；省略＝全部）")])),
        Tool(name: "akashic_doctor",
             description: "library 健康報告：entries/people/relations 統計、index 重建、quarantine、未解析作者數、orphans。",
             inputSchema: obj([:])),
        Tool(name: "akashic_person",
             description: "人物檢索（#14）：person key 直查聚合（人物資料＋著作＋合著者統計，可選 library 過濾）；模糊姓名回候選清單（絕不自動選定——消歧交給 caller）。",
             inputSchema: obj([
                "key": str("person key（與 name 互斥；直查聚合）"),
                "name": str("模糊姓名（與 key 互斥；回候選，上限 50）"),
                "library": str("library key 過濾（選填，僅 key 直查時生效）"),
             ])),
        Tool(name: "akashic_libraries",
             description: "具名 library（成員集合視角，#13）：list 列表含成員數；create 建 registry；add/remove 改 entry 的 akashic.libraries（衍生層）。store 是全集，library 不分割資料。",
             inputSchema: obj([
                "action": str("list | create | add | remove"),
                "key": str("library key（create/add/remove 必填；StoreKey 格式）"),
                "name": str("顯示名稱（create 必填）"),
                "description": str("描述（create 選填）"),
                "citekey": str("目標 entry（add/remove 必填）"),
             ], required: ["action"])),
        Tool(name: "akashic_set_status",
             description: "設定 entry 的 akashic.status（衍生層；如 reading / read / to-read）。不給 status 則清除。",
             inputSchema: obj([
                "citekey": str("citekey"), "status": str("狀態字串；省略＝清除"),
             ], required: ["citekey"])),
        Tool(name: "akashic_tag",
             description: "增刪 entry 的 akashic.tags（衍生層）。",
             inputSchema: obj([
                "citekey": str("citekey"),
                "add": strArray("要加的 tags"), "remove": strArray("要移除的 tags"),
             ], required: ["citekey"])),
        Tool(name: "akashic_link",
             description: "增刪 entry 的關係（akashic.relations：cites 或 related；目標可為庫外 citekey）。",
             inputSchema: obj([
                "citekey": str("來源 citekey"),
                "kind": str("cites | related"),
                "add": strArray("要加的目標 citekeys"), "remove": strArray("要移除的目標"),
             ], required: ["citekey", "kind"])),
        Tool(name: "akashic_resolve_people",
             description: "人物解析：不帶 apply 列出高信心候選（alias 完全命中、不歧義）；帶 apply（候選 id 陣列）逐候選套用。絕不自動合併。",
             inputSchema: obj(["apply": strArray("要套用的候選 id（形如 citekey:authorIndex）；省略＝只列候選")])),
        Tool(name: "akashic_create_entry",
             description: "建庫外手動文獻（無 Zotero provenance；citekey 自動生成）。",
             inputSchema: obj([
                "type": str("biblatex type（article/book/…）"),
                "title": str("標題"),
                "authors": strArray("作者顯示名（literal）"),
                "date": str("日期（YYYY[-MM[-DD]]）"),
                "fields": .object([
                    "type": .string("object"),
                    "additionalProperties": .object(["type": .string("string")]),
                    "description": .string("其餘 biblatex 欄位（journaltitle/doi/…；值必須是字串）"),
                ]),
             ], required: ["type", "title"])),
        Tool(name: "akashic_add_person",
             description: "建人物實體（people/<key>.yaml；aliases、ORCID、OpenAlex）。",
             inputSchema: obj([
                "key": str("kebab-case person key"),
                "names": strArray("aliases（第一個為顯示名）"),
                "orcid": str("ORCID（可選）"), "openalex": str("OpenAlex author ID（可選）"),
             ], required: ["key", "names"])),
        Tool(name: "akashic_import_zotero",
             description: "觸發 Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）。回傳完整 import report。",
             inputSchema: obj([
                "zotero_db": str("zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）"),
                "library_id": int("只拉此 libraryID（省略＝全部 libraries）"),
             ])),
    ]

    // MARK: - Dispatch

    private func registerHandlers() async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: AkashicMCPServer.tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text("server unavailable")], isError: true)
            }
            return await self.handleToolCall(params)
        }
    }

    private func handleToolCall(_ params: CallTool.Parameters) -> CallTool.Result {
        func arg(_ key: String) -> String? { params.arguments?[key]?.stringValue }
        func argInt(_ key: String) -> Int? { params.arguments?[key]?.intValue }
        func argList(_ key: String) -> [String] {
            guard let value = params.arguments?[key], case .array(let arr) = value else { return [] }
            return arr.compactMap(\.stringValue)
        }
        func argDict(_ key: String) -> [String: String] {
            guard let value = params.arguments?[key], case .object(let dict) = value else { return [:] }
            return dict.compactMapValues(\.stringValue)
        }

        do {
            let output: String
            switch params.name {
            case "akashic_search":
                output = try service.search(
                    author: arg("author"), journal: arg("journal"), tag: arg("tag"),
                    type: arg("type"), yearFrom: argInt("year_from"), yearTo: argInt("year_to"),
                    library: arg("library"))
            case "akashic_get_entry":
                output = try service.getEntry(citekey: arg("citekey") ?? "")
            case "akashic_relations":
                output = try service.relations(citekey: arg("citekey") ?? "", kind: arg("kind") ?? "")
            case "akashic_graph":
                output = try service.graph(focus: arg("focus") ?? "",
                                           depth: argInt("depth") ?? 1,
                                           format: arg("format") ?? "mermaid")
            case "akashic_export":
                let keys = argList("citekeys")
                output = try service.export(citekeys: keys.isEmpty ? nil : keys,
                                            format: arg("format") ?? "bib")
            case "akashic_people":
                output = try service.people(query: arg("query"))
            case "akashic_doctor":
                output = try service.doctor()
            case "akashic_person":
                output = try service.person(key: arg("key"), name: arg("name"),
                                            library: arg("library"))
            case "akashic_libraries":
                output = try service.libraries(
                    action: arg("action") ?? "", key: arg("key"), name: arg("name"),
                    description: arg("description"), citekey: arg("citekey"))
            case "akashic_set_status":
                output = try service.setStatus(citekey: arg("citekey") ?? "", status: arg("status"))
            case "akashic_tag":
                output = try service.tag(citekey: arg("citekey") ?? "",
                                         add: argList("add"), remove: argList("remove"))
            case "akashic_link":
                output = try service.link(citekey: arg("citekey") ?? "", kind: arg("kind") ?? "",
                                          add: argList("add"), remove: argList("remove"))
            case "akashic_resolve_people":
                // 「有給 apply 但空陣列」＝套用零筆（no-op），與「未給」（列候選）語意分開
                let applyProvided = params.arguments?["apply"] != nil
                let apply = argList("apply")
                output = try service.resolvePeople(apply: applyProvided ? apply : nil)
            case "akashic_create_entry":
                output = try service.createEntry(
                    type: arg("type") ?? "", title: arg("title") ?? "",
                    authors: argList("authors"), date: arg("date"), fields: argDict("fields"))
            case "akashic_add_person":
                output = try service.addPerson(key: arg("key") ?? "", names: argList("names"),
                                               orcid: arg("orcid"), openalex: arg("openalex"))
            case "akashic_import_zotero":
                output = try service.importZotero(zoteroDb: arg("zotero_db"),
                                                  libraryID: argInt("library_id"))
            default:
                return CallTool.Result(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
            return CallTool.Result(content: [.text(output)], isError: false)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return CallTool.Result(content: [.text("Error: \(message)")], isError: true)
        }
    }
}
