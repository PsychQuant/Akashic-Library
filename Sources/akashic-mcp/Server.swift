import Foundation
import MCP
import AkashicMCPKit
import AkashicStoreIO
import AkashicCore

/// akashic-mcp — Akashic-Library 的 MCP 工具面（Phase 2）。
/// 讀走 index；寫只碰衍生層（akashic namespace／人物解析／庫外 entry／import 觸發）。
actor AkashicMCPServer {
    private let server: Server
    private let transport: DepthGuardedTransport
    private let service: AkashicService

    init() throws {
        // #37：index 位置取決於 registry key，所以解析要保留 key 而不只是 root
        let resolved = try LibraryLocator.resolveDetailed(explicit: nil)
        service = AkashicService(root: resolved.root, key: resolved.key)
        server = Server(
            name: "akashic-mcp",
            version: "0.2.0",
            capabilities: .init(tools: .init()))
        // #152：深度預檢包在 SDK transport 外——撞毀在 SDK 解 Value 的遞迴，
        // 必須擋在 bytes 進 decoder 之前
        transport = DepthGuardedTransport(wrapping: StdioTransport())
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
             description: "library 健康報告：entries/people/relations 統計、index 重建、quarantine、未解析作者數、orphans、unknownFieldFiles（含較新 schema 未知欄位的檔案，v1.3 tolerant-preserve 可見性面）。",
             inputSchema: obj([:])),
        Tool(name: "akashic_files",
             description: "多檔案（#18）：list＝列出已註冊的實體庫（檔案）與 active root；use＝session 內切換到另一個檔案（互不相通——切換後所有 tool 都作用在新 universe；不寫 config，持久預設用 CLI akashic file use）。",
             inputSchema: obj([
                "action": str("list 或 use"),
                "key": str("use 時：已註冊的檔案 key"),
             ])),
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
             description: "人物解析：不帶 apply/reject 回 {candidates, candidateTotal, candidateRowsDropped, rejected, rejectedTotal, rejectedRowsDropped, pendingTotal, people, ambiguities, ambiguityTotal, ambiguityRowsDropped, truncated}（另有 verdictMalformed/verdictMalformedTotal，僅在偵測到解析不了的 verdict 時出現）——candidates 是高信心候選（alias 完全命中、不歧義，可套用），每列帶 counts{confirmed,rejected,pending}（該列證據類別的三態**計數**——刻意不報比率／機率，pendingTotal 給未處理總量）；rejected 是**已否決配對的獨立段**（排在 candidates 之後閱讀；帶 verdict:\"rejected\"、無 id，不可套用）——沉底而非隱藏；ambiguities 是同一 literal 對到 2+ person 的位置，**不可套用、需要人判斷**，每筆帶 personRefs（不透明 ref，非 person key）；區辨欄位在 people[ref] 只送一次（key/names/namesTotal/orcid/openalex/died/currentAffiliation 或 formerAffiliation+formerAffiliationEnd|formerAffiliationAttested，缺席即不出現），以便分辨「兩個同名的人」（各自歸屬）與「同一人兩筆記錄」（該合併）。帶 apply（候選 id 陣列）逐候選套用並在同一動作寫 resolution-confirmed verdict（store format < 8 時 verdict 跳過並以 verdictsSkipped 揭露）；帶 reject（候選 id 陣列）寫 resolution-rejected verdict 到該 person（entry 不動；需 store format ≥ 8），之後該配對不再被提名（同 literal 他 entry 照提）。apply 與 reject 都是顯式人為動作、**不可同一次呼叫**（相反的 verdict 各自有失敗語意），無任何自動 verdict 路徑。上限：candidates／rejected／ambiguities 各自 48 KB 位元組預算，歧義至多 50 筆／每筆至多 20 個 personRefs／people 至多 60 筆／每人至多 2 個異名（超出時給 namesTotal），candidates 與 rejected 各至多 50 筆。吃不下預算的**整列不印**並計入 *RowsDropped；**任一軸被截**都會讓 truncated=true（*Total 給各自的總數）。絕不自動合併。單筆寫入失敗記入 writeFailed／confirmWriteFailed／rejectWriteFailed 並續跑（applied/rejected 只列實際落地者）。",
             inputSchema: obj([
                "apply": strArray("要套用的候選 id（形如 citekey:authorIndex）；省略＝只列候選"),
                "reject": strArray("要否決的候選 id（同形）——寫 resolution-rejected verdict，entry 不動；省略＝不否決"),
             ])),
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
                "names": strArray("aliases（顯示名由 authorized 指定——#81 起 names 順序不帶語意）"),
                "orcid": str("ORCID（可選）"), "openalex": str("OpenAlex author ID（可選）"),
             ], required: ["key", "names"])),
        Tool(name: "akashic_update_person",
             description: "person 的部分更新（#68）：提及的欄位整個換、未提及一律不動。純量欄位（orcid/openalex/died/note）收字串或 null（null＝清除）；names/authorized 收字串陣列（全量替換）；profile 收維度 object（維度級覆寫，段形狀同 YAML：value/start/end/ended/source/note）；注意 contacts 是**一個**維度——提及它＝整個 contacts map 替換，未提及的子鍵（email/phone…）會消失。dry_run 時零寫入、回報會改什麼 + format gate 預演。",
             inputSchema: obj([
                "key": str("person key"),
                "fields": .object([
                    "type": .string("object"),
                    "description": .string("要更新的欄位（結構化 JSON，見工具描述）"),
                ]),
                "dry_run": .object(["type": .string("boolean"),
                                    "description": .string("true＝只預告不寫入（預設 false）")]),
             ], required: ["key", "fields"])),
        Tool(name: "akashic_divergences",
             description: "列出全部歧異記錄（id/question/候選/有無判斷）。list-only——消歧屬人工（CLI resolve-divergence）。",
             inputSchema: obj([:])),
        Tool(name: "akashic_record_divergence",
             description: "記下未決的同一性問題（#77）——遇到「這兩筆可能是同一個」時當場記錄而非當場判斷。記下判斷不等於消歧；消歧（合併＋刪檔）屬人工操作（CLI resolve-divergence），本面刻意不提供。",
             inputSchema: obj([
                "question": str("未決的是什麼，一句話"),
                "candidates": strArray("候選，形如 key:shape（shape 為 person / organization / work）；需要兩個以上"),
                "judgement": str("已形成的判斷（選填；給了就必須同時給 rests_on）"),
                "rests_on": strArray("判斷的依據（來源 URL 或 sha256: 摘要；選填，與 judgement 成對）"),
                "prefers": str("判斷傾向哪個候選的 key（選填，與 judgement 成對；必須是候選之一）——消歧會據以比對、不一致時拒絕，但**不代選**：倖存者仍須人工指定"),
             ], required: ["question", "candidates"])),
        Tool(name: "akashic_import_zotero",
             description: "觸發 Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）。回傳完整 import report；單筆寫入失敗記入 writeFailed 並續跑（index 照常重建）。",
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
                return CallTool.Result(content: [.text(text: "server unavailable", annotations: nil, _meta: nil)], isError: true)
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
                // #165：消毒住 `AkashicService.export()`（MCP 的輸出邊界）——
                // Server 這層不 import AkashicCore，而且那裡才看得到「這份內容
                // 是要回給 LLM」這個事實
                output = try service.export(citekeys: keys.isEmpty ? nil : keys,
                                            format: arg("format") ?? "bib")
            case "akashic_people":
                output = try service.people(query: arg("query"))
            case "akashic_doctor":
                output = try service.doctor()
            case "akashic_files":
                output = try service.files(action: arg("action") ?? "list", key: arg("key"))
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
                let rejectProvided = params.arguments?["reject"] != nil
                let reject = argList("reject")
                output = try service.resolvePeople(apply: applyProvided ? apply : nil,
                                                   reject: rejectProvided ? reject : nil)
            case "akashic_create_entry":
                output = try service.createEntry(
                    type: arg("type") ?? "", title: arg("title") ?? "",
                    authors: argList("authors"), date: arg("date"), fields: argDict("fields"))
            case "akashic_add_person":
                output = try service.addPerson(key: arg("key") ?? "", names: argList("names"),
                                               orcid: arg("orcid"), openalex: arg("openalex"))
            case "akashic_update_person":
                guard let fieldsValue = params.arguments?["fields"],
                      case .object = fieldsValue else {
                    return CallTool.Result(
                        content: [.text(text: "fields 必須是 object", annotations: nil, _meta: nil)],
                        isError: true)
                }
                let dryRun: Bool
                if case .bool(let b)? = params.arguments?["dry_run"] { dryRun = b } else { dryRun = false }
                guard let fieldsAny = valueToAny(fieldsValue) as? [String: Any] else {
                    return CallTool.Result(
                        content: [.text(text: "fields 的巢狀深度超過 64——不是任何可更新欄位的形狀",
                                        annotations: nil, _meta: nil)],
                        isError: true)
                }
                output = try service.updatePerson(
                    key: arg("key") ?? "", fields: fieldsAny, dryRun: dryRun)
            case "akashic_divergences":
                output = try service.listDivergences()
            case "akashic_record_divergence":
                output = try service.recordDivergence(
                    question: arg("question") ?? "", candidates: argList("candidates"),
                    judgement: arg("judgement"), restsOn: argList("rests_on"),
                    prefers: arg("prefers"))
            case "akashic_import_zotero":
                output = try service.importZotero(zoteroDb: arg("zotero_db"),
                                                  libraryID: argInt("library_id"))
            default:
                return CallTool.Result(content: [.text(
                    text: "Unknown tool: \(displaySafe(params.name, max: 200))",
                    annotations: nil, _meta: nil)], isError: true)
            }
            return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)], isError: false)
        } catch {
            // **MCP 的單一錯誤出口，統一消毒**（#162）。CLI 早就這樣做了，而且那是
            // 明寫的裁決：「逐條補 error 站點是假性閉合——新增的 case 又會裸奔。
            // 這裡取代合成的 main()，在唯一出口統一過 displaySafeMultiline」
            // （`Sources/akashic/CLI.swift`）。**MCP 側從來沒有拿到同樣的處置**：
            // `Main.swift` 消毒了啟動錯誤，這條 per-tool 的熱路徑沒有。
            //
            // 後果是全面的：`StoreYAMLError.invalidField` 的 `errorDescription`
            // **刻意不消毒** payload（它的策略是「由輸出端 sink 消毒」，見該型別的
            // display-safe-exempt 註解），所以每一個未消毒的 throw 站點——約 90 個，
            // 多數是折行的——都經由這裡把檔案裡的未知欄位名、YAML 鍵、值原文
            // 逐字送進 LLM context。這是 #142 明列的強威脅模型。
            //
            // 修在這裡而不是 90 個 throw 站點：那些站點的策略本來就是 sink-side，
            // 缺的是 sink。補一個 sink 勝過補 90 個站點再等下一個新增的 case。
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return CallTool.Result(content: [.text(
                text: "Error: \(displaySafeMultiline(message))",
                annotations: nil, _meta: nil)], isError: true)
        }
    }
}

/// MCP `Value` → Foundation `Any`（#68：update_person 的 fields 收任意巢狀 JSON）。
/// bool 用 NSNumber(booleanLiteral)——AkashicService 端以 CFBoolean 判定還原。
/// **深度上限 64**（#148 verify F3）：與 jsonToNode 同一理由——這條遞迴在它之前跑，
/// 兩層都要守，回 nil 讓呼叫端回真正的錯誤而不是進程死亡。
func valueToAny(_ v: Value, depth: Int = 0) -> Any? {
    guard depth <= 64 else { return nil }
    switch v {
    case .null: return NSNull()
    case .bool(let b): return NSNumber(booleanLiteral: b)
    case .int(let i): return i
    case .double(let d): return d
    case .string(let s): return s
    case .data(_, let d): return d
    case .array(let arr):
        var out: [Any] = []
        for x in arr {
            guard let a = valueToAny(x, depth: depth + 1) else { return nil }
            out.append(a)
        }
        return out
    case .object(let dict):
        var out: [String: Any] = [:]
        for (k, x) in dict {
            guard let a = valueToAny(x, depth: depth + 1) else { return nil }
            out[k] = a
        }
        return out
    }
}
