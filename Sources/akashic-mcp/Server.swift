import Foundation
import MCP
import AkashicMCPKit
import AkashicStoreIO
import AkashicCore
import AkashicS2

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
            version: AkashicMCPVersion.current,   // #632：與 mcpb/manifest.json 同步，不再寫死
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

    /// `akashic_enrich` 的 items 上限（#236 的預算形：輸出進 LLM context，呼叫端無法在收到後
    /// 丟棄已付的代價）。`counts`／`written`／`writeFailed` 不受此限；要全部用 CLI。
    static let enrichItemLimit = 20

    /// `akashic_import_zotero` 的 `ambiguousSourceClaims` 上限（#684，同一個預算形）：至多 20 個來源、每個來源至多 20 個宣稱者。
    /// 完整清單在 CLI `import-zotero`（逐行全列）；截掉時回應帶 `ambiguousSourceClaimsTotal`／`ambiguousSourceClaimsTruncated`。
    static let ambiguousClaimsLimit = 20

    /// `akashic_import_zotero` 其餘 citekey 清單的上限（#696，同一個預算形）：`created`、`updated`、`authorsOverwritten`…每個至多 20 筆，
    /// 完整筆數在 `listTotals`、被截的清單名在 `truncatedLists`。一次首次匯入的 `created` 就是整個 Zotero library 的筆數。CLI `import-zotero` 不受此限。
    /// 失敗清單（`writeFailed`、`quarantineConflicts`）不截（R1 verify：沒寫進去的記錄在 store 裡沒有痕跡，截掉就拿不回來）。
    static let importListLimit = 20

    /// #705：會寫既有 work／person 的工具（13 個）都加這一句——分派層把「寫進 entities/、搬移後的 legacy 拷貝沒刪掉」的那一筆
    /// 放進回應的 `writtenWithLegacyCopy`（成功的 JSON 物件加鍵；錯誤回應放在訊息最前面，#705 R1 verify 第 5 列）。一個常數，13 份描述不會各寫各的。
    /// #705 R2 verify 第 13 列：至多列 `writtenWithLegacyCopyLimit` 筆，另給 `writtenWithLegacyCopyTotal`／`…Truncated`——說明只寫「前 N 筆與總數」，
    /// 13 份描述共用這一句，每多一個字就是十三份（tools/list 的位元組預算，#578）。
    static let legacyCopyNote = "已寫入而 legacy 拷貝未刪的列在 writtenWithLegacyCopy（前 \(AkashicService.writtenWithLegacyCopyLimit) 筆與總數；之後的寫入沒套用的完整筆數在 writtenWithLegacyCopyNotApplied；錯誤時列在訊息前）。"

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
        // #664：Semantic Scholar。與 CLI `akashic s2` 共用 AkashicS2；契約細節在 `akashic s2 --help`。
        Tool(name: "akashic_s2",
             description: "查 Semantic Scholar（金鑰在 keychain、全機每秒至多 1 次、不寫 store）。回傳 {endpoint,total,returned,truncated,offset,nextOffset,data}，上限 48 KiB、只放完整筆數；truncated 時以 nextOffset 續查。endpoint=status 回 {keychain,throttle,host}。缺金鑰時的設定見 akashic s2 --help",
             inputSchema: obj([
                "endpoint": .object(["type": .string("string"),
                                     "enum": .array(S2Tool.endpointNames.map { .string($0) })]),
                "id": str("論文（DOI:…、CorpusId:…；裸 DOI 自動加 DOI:）或作者識別碼"),
                "title": str("match 的標題"),
                "year": str("match 的出版年（可省略）"),
                "name": str("author_search 的姓名"),
                "ids": strArray("batch 的 id（1–500）"),
                "fields": strArray("S2 欄位名，照原樣轉給 S2"),
                "offset": int("起始筆數"),
                "limit": int("向 S2 要幾筆（分頁端點預設 100；recommend 1–500）"),
             ], required: ["endpoint"])),
        Tool(name: "akashic_search",
             description: "搜尋文獻庫（欄位篩選；全走本地 index）。回傳 citekey/type/title/year/journal/authors 的 JSON 陣列。",
             inputSchema: obj([
                "author": str("作者：person key 完全命中或姓名子字串"),
                "journal": str("期刊名（case-insensitive 完全命中）"),
                "tag": str("tag 完全命中"),
                "type": str("biblatex entry type（article/book/…）"),
                "year_from": int("起始年"),
                "year_to": int("結束年"),
                // #315：明寫它**不是** store root。CLI 的 `--library` 是那個意思，
                // 而兩者同名、鄰接、錯用不會報錯（只回一個合理的錯子集）。
                "library": str("store **內**的 membership 分類 key 篩選（省略＝全集）。**不是** store root——store 由伺服器啟動時決定，可用 akashic_files 的 use action 切換"),
             ])),
        Tool(name: "akashic_get_entry",
             description: "以 citekey 取完整 entry：回 id／citekey／type／title／authors／date／fields／venues（邊是 {key} 或 {literal}）、有才出現的 doi／pmid／isbn、akashic namespace（tags／libraries／relations／sources 副本 digest）與 provenance（附加來源在 provenance_additional）；有才出現的 unknownFields（本 binary 不認得的欄位名）。",
             inputSchema: obj(["citekey": str("citekey")], required: ["citekey"])),
        Tool(name: "akashic_relations",
             description: "關係查詢：same-journal / same-author / cites / cited-by / related。回 [{citekey, title, type, year, journal, authors}]。",
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
             description: "人物實體列表／查詢：回 [{key, names（含 aliases）, orcid, openalex, 有才出現的 unknownFields}]。",
             inputSchema: obj(["query": str("關鍵字（比對 key 與所有 alias；省略＝全部）")])),
        Tool(name: "akashic_doctor",
             description: "library 健康報告：entries／people／relations 統計、indexRebuilt、unresolvedAuthorLiterals、divergences（歧異記錄數）、digestSources、noAuthorizedName、authorizedOnlyByCitationForm、orphaned／orphanedAdditionalSources（後者：主連結仍在、附加來源已在 Zotero 端刪除）；有事才出現：quarantined、unknownFieldFiles（含較新 schema 未知欄位的檔案）、layoutResidue、deceasedWithOpenAffiliation、sources（存檔審計；occupantProblems：位址上不是普通檔或大小與 index 不符；strayTemporaryFiles：中斷存檔的暫存檔，附 ageSeconds、possiblyInProgress——一小時內還在動的不要刪；兩者各列 20 則、總數在 *Total）、crossRecordIssues（有 error 時 index 不重建、note 說明）、recordIssues（各族與 StoreHealth 的家族存取子一一對應，含 deadVerdicts、contradictoryVerdicts、duplicateVerdictRecords、duplicateReferences；duplicateVerdictRecords 不計的那一格見 docs/store-format.md §3.5）。recordIssues.first 截 20 則、受 48 KiB 位元組預算（被截時 firstCappedByBudget 為 true）。count／errors 與各族計數都是**訊息則數**（一則可能是一筆記錄、一個配對或一組重複）；cappedRecords（以記錄計）> 0 時都是下限：組合式的六族（清單見 CLI `akashic validate --help`）每筆記錄至多 20 則、其餘一句概括（CLI validate 每筆一樣至多 20 則，只是不把總則數截成 20），其餘家族無此上限。owner 給定時同 CLI `akashic validate --owner`：只回那一筆記錄的 per-record 問題、不套每筆 20 則的列出上限：回 listing（full）／total／errors／issues（每則截 1,000 字元、同一個 48 KiB 預算，被截時 truncated＝true、total 仍完整）／scope；唯讀，不重建 index、不含跨記錄檢查與 quarantine；找不到或同 kind 同 key 兩筆以上時拒絕。",
             inputSchema: obj([
                "owner": str("選填：<kind>:<key>，只看這一筆記錄；kind 是 work／person／organization／venue／divergence，必填、不猜（divergence 的 key 是 UUID）；省略＝全庫健康報告"),
             ])),
        Tool(name: "akashic_files",
             description: "多檔案：list＝回 files（已註冊的實體庫）與 active_root；use＝session 內切換到另一個檔案（互不相通——切換後所有 tool 都作用在新 universe；不寫 config，持久預設用 CLI akashic file use）。",
             inputSchema: obj([
                "action": str("list 或 use"),
                "key": str("use 時：已註冊的檔案 key"),
             ])),
        Tool(name: "akashic_person",
             description: "人物檢索：person key 直查回 {person, publications, co_authors}（person 帶 key／names／affiliations／verdicts，有才出現 orcid／unknownFields；著作＋合著者統計，可選 library 過濾）；模糊姓名回 {candidates}（絕不自動選定——消歧交給 caller）。",
             inputSchema: obj([
                "key": str("person key（與 name 互斥；直查聚合）"),
                "name": str("模糊姓名（與 key 互斥；回候選，上限 50）"),
                // #315：同上——這是 store 內的分類，不是 store root。
                "library": str("store **內**的 membership 分類 key 過濾（選填，僅 key 直查時生效）。**不是** store root"),
             ])),
        Tool(name: "akashic_libraries",
             description: "具名 library（成員集合視角）：list 回 [{key, name, description, kind 與規則, members（成員數）, nonconforming}]；create 建 registry（kind 必填；回 created、membership）；set-kind 標性質與規則（整值替換，回 previous、previousBasis、nonconforming；換掉既有規則要求 registry 檔已 commit）；check 回 members、nonconforming（不符規則的成員）、total、truncated 與 basisProblem；add／remove 改 entry 的 akashic.libraries，指名的 work 無法唯一定位時整批拒絕、零寫入。kind：topic 照寫；rule 以 venue 界定；document 以文件的 cites 界定。add 不符規則的不寫（回 written:false、skipped 原因、basis），未標性質的 library 拒絕 add。細節見 akashic library --help。" + legacyCopyNote,
             inputSchema: obj([
                "action": str("list | create | add | remove | set-kind | check"),
                "key": str("library key（list 以外必填）"),
                "name": str("顯示名稱（create 必填）"),
                "description": str("描述（create 選填）"),
                "citekey": str("目標 entry（add/remove 必填）"),
                "kind": str("topic | rule | document（create／set-kind 必填）"),
                "venue": str("rule：venue key"),
                "types": strArray("rule：限定的 entry type（選填）"),
                "excluded": strArray("rule：不收的 citekey（選填；須在庫）"),
                "document": str("document：文件 citekey"),
                "source": str("rule：來歷，只記不查（選填）"),
             ], required: ["action"])),
        Tool(name: "akashic_set_status",
             description: "設定／清除 entry 的 akashic.status（衍生層；如 reading / read / to-read）。"
                        + "給 status 設定；清除要顯式 clear:true。省略 status 不是清除——會被拒絕。" + legacyCopyNote,
             inputSchema: obj([
                "citekey": str("citekey"), "status": str("狀態字串（與 clear 互斥）"),
                "clear": .object(["type": .string("boolean"),
                                  "description": .string("true＝清除既有狀態（與 status 互斥）")]),
             ], required: ["citekey"])),
        Tool(name: "akashic_tag",
             description: "增刪 entry 的 akashic.tags（衍生層）。" + legacyCopyNote,
             inputSchema: obj([
                "citekey": str("citekey"),
                "add": strArray("要加的 tags"), "remove": strArray("要移除的 tags"),
             ], required: ["citekey"])),
        Tool(name: "akashic_link",
             description: "增刪 entry 的關係（akashic.relations：cites 或 related；目標可為庫外 citekey）。" + legacyCopyNote,
             inputSchema: obj([
                "citekey": str("來源 citekey"),
                "kind": str("cites | related"),
                "add": strArray("要加的目標 citekeys"), "remove": strArray("要移除的目標"),
             ], required: ["citekey", "kind"])),
        Tool(name: "akashic_resolve_people",
             description: "人物解析（literal → person；完整契約見 CLI `akashic resolve-people --help` 與 docs/store-format.md §3.5）。不帶寫入腿時回 {candidates, candidateTotal, candidateRowsDropped, rejected, rejectedTotal, rejectedRowsDropped, pendingTotal, undecidedTotal, people, ambiguities, ambiguityTotal, ambiguityRowsDropped, truncated}（verdictMalformed／verdictMalformedTotal 僅在有解析不了的 verdict 時出現）。candidates 是可套用的提名、信心降冪，每列帶 tier（exact＝alias 完全命中／confirmed-elsewhere＝同 literal 已於他處 confirmed／reorder＝token 重排／initials＝姓＋首字母；**initials 的 apply 前必查證**）、counts{confirmed,rejected,undecided,pending}（四態計數）、eliminatedPairings（>0＝淘汰而得、沒人判定過；兩段 id 被拒）、undecidedChecks（查過未決的次數，歧義條目也帶；以 id 點名的 apply 照寫）、unlocatableCitekey／unlocatablePersonKey（work／person 無法唯一定位，原因見 akashic validate；寫入腿遇到時整批拒絕或該筆略過並具名）。rejected 是已否決的配對（verdict:\"rejected\"、無 id、不可套用）。ambiguities 是同一 literal 在同一提名層對到 2+ person（帶 tier），**不可套用、需要判斷**；personRefs 是不透明 ref，區辨欄位（key/names/namesTotal/orcid/openalex/died/currentAffiliation、formerAffiliation+formerAffiliationEnd（已結束）、observedAffiliation+observedAffiliationAt（只被觀測到，非曾隸屬），缺席即不出現）在 people[ref] 只送一次。各段有筆數與位元組上限（異名超出給 namesTotal）；吃不下的整列不印、計入 *RowsDropped，被截即 truncated=true。apply 寫 resolution-confirmed（store format < 8 時跳過、見 verdictsSkipped）。apply＋reject 可同一次呼叫：reject 先提交、apply 以寫入後狀態重解析，回 {legs:{reject,apply}}，同列兩邊都點＝reject 贏（skippedBecauseRejected）；其他寫入腿各自單獨呼叫，組合即整批拒絕。單筆寫入失敗記入 writeFailed／confirmWriteFailed／rejectWriteFailed 並續跑；沒套用到的候選不寫 verdict，見 notApplied＋notAppliedReason。各腿回自己的清單：apply→applied（另 entriesRewritten）、reject→rejected（另 personsRewritten）、refute→refuted、split_author→split、un_split→unsplit、drop_author→dropped、attribute_org→attributed（後四者逐筆報告，count 是筆數）。絕不自動合併。" + legacyCopyNote,
             inputSchema: obj([
                "apply": strArray("要套用的候選 id（citekey:authorIndex:personKey，提名改指時拒絕；兩段 legacy 形只在該位置提名唯一且非淘汰而得時等價）；省略＝只列候選"),
                "reject": strArray("要否決的候選 id（同 apply 的三段形）——寫 resolution-rejected verdict 到該 person（rule 依候選的 tier 導出；需 store format ≥ 8），entry 不動，之後該配對不再被提名"),
                "confirm_tiers": strArray("顯式承認要套用的寬鬆提名層（reorder／initials／confirmed-elsewhere，可多個）——apply 集含寬鬆層候選而該層未列於此＝整批拒絕零寫入；exact 免承認"),
                "refute": strArray("逐篇**否決**：citekey:authorIndex:personKey=否決理由（必填、≤ 4,096 位元組，超過整批拒絕、不截斷，#648）。歧義列也適用；entry 不動，只寫 resolution-rejected verdict，已有 reject 的配對寫一筆並存的。輸入錯整批拒絕零寫入；store 狀態不符（含作者位目前就歸給這個人）該筆略過並具名"),
                "split_author": strArray("把一個作者位拆成多個（一個 literal 裝了兩個人）：citekey:authorIndex:分隔符=理由。收分隔符（不收拆好的名字）；切出空段即拒絕；只作用於未歸戶的位置；拆出來的仍是 .literal"),
                "un_split": strArray("split_author 的逆操作：citekey:原literal（以值定位）。還原後刪掉那筆拆分記錄。整批拒絕零寫入：任一段已升格（屬 demote）、各段不連續同序、同 value 多筆記錄、那些 work 檔不在 git 或有未提交修改"),
                "drop_author": strArray("移除不是作者的作者位（例如 PsycInfo 的 `No authorship indicated`）：citekey:literal=理由（必填）。以值定位；只作用於未歸戶的 .literal；同一筆 work 出現多次即拒絕。移除記錄（field: authors）與作者位改寫同一次寫入，需 store format ≥ 17；沒有具名逆操作"),
                "undecided": strArray("記下查過未決：citekey:authorIndex:personKey=查了什麼、為何判不出來（需 store format ≥ 19）。寫一筆 resolution-undecided 到該 person，作者位不動。已判定的配對、已歸戶的作者位、無法唯一定位的 work 或 person 該筆略過並在 skipped（具名）；相同記錄已在＝alreadyRecorded。整批拒絕零寫入：格式錯、重複 id、說明空白、person 不存在、digest 不合、rests_on 單獨出現、一次超過 200 個 id／20 個 digest／單句說明 4,096 位元組（不截斷）"),
                "rests_on": strArray("未決記錄的證據 digest（sha256:64hex，0 byte 內容的 digest 拒收，先用 akashic_store_source 存檔），套用到這次呼叫的每一筆 undecided；只伴隨 undecided"),
                "attribute_org": strArray("把作者位歸給團體作者（.literal → .organization）：citekey:authorIndex:orgKey=判定理由（必填）。org 需已存在（絕不自動建）；已歸戶的位置拒絕；整批驗證通過才寫。理由存不進去時照常歸戶、該列帶 verdictNotRecorded（含原因）"),
                "judge": strArray("逐篇判定（#386）：citekey:authorIndex:personKey=判定理由（以第一個 = 切；必填、≤ 4,096 位元組，超過整批拒絕、不截斷，#648），理由逐字寫進 verdict，回 judged；**歧義列也適用**。輸入錯（含同一作者位判給兩個人）整批拒絕零寫入；store 狀態不符（位置已歸戶、無法唯一定位、找不到原 literal 等）該筆略過並在 skipped 具名。已歸給同一個人：同一句理由＝no-op（alreadyJudged），不同則略過；由 apply 歸戶的寫一筆並存判定（coexistsWith:\"nominated\"，需 format ≥ 19）；理由存不進去時照常歸戶（verdictNotRecorded）。任一筆寫出後超過 8 MiB 讀取上限即整批零寫入。需 store format ≥ 8"),
             ])),
        Tool(name: "akashic_create_entry",
             description: "建庫外手動文獻（無 Zotero provenance；citekey 自動生成；回 citekey 與 id）。DOI 已在庫時照常建（erratum 會與原文共用 DOI），回應的 doiHits 列出命中的 citekey；建檔前可用 akashic_enrich 乾跑（proposal 帶 doi）查。",
             inputSchema: obj([
                "type": str("biblatex type（article/book/…）"),
                "title": str("標題"),
                "authors": strArray("作者顯示名（literal）"),
                "date": str("日期（YYYY[-MM[-DD]]）"),
                "fields": .object([
                    "type": .string("object"),
                    "additionalProperties": .object(["type": .string("string")]),
                    "description": .string("其餘 biblatex 欄位（journaltitle/…；值必須是字串）"),
                ]),
                "doi": strArray("DOI（結構化欄位，非 fields；不合法即整個呼叫拒絕、零寫入）"),
                "pmid": strArray("PMID（同上）"),
                "isbn": strArray("ISBN（同上；ISBN-13 與 ISBN-10 可並存）"),
             ], required: ["type", "title"])),
        Tool(name: "akashic_update_entry",
             description: "work 的部分更新（CLI `akashic update-entry --help`）。**dry_run 預設 true**，false 才寫。"
                 + "remove_fields 移除 fields 的值——判定：理由必填、只回在 fieldRemovals、不寫進 store；實寫要求該 work 檔已在 git 裡 commit、乾淨。"
                 + "指向被移除鍵的 fields.<鍵> reference 一併刪除（referencesRemoved）；由被移除值推導的 venue 邊不動、列在 venueEdgesFromRemovedValues（literal）／"
                 + "venueKeyEdgesFromRemovedValues（已歸戶，venue 上的 verdict 也留著）；reintroductionNote 說明 import-wos 回填、enrich、Zotero pull 會把值補回；"
                 + "移除 APA7 必要欄位時附 apa7RequiredNowMissing。add_sources 把已存進 sources/ 的內容宣告為這篇的副本（akashic.sources）：add-only、冪等（sourcesAlreadyPresent），"
                 + "sourcesAdded 帶 index 的取得記錄（origin／retrieved／mediaType／acquisition／note；至多 20 筆，sourcesAddedTotal／truncated 揭露；CLI 全列），sourcesTotal 是宣告後的副本總數。"
                 + "remove_zotero_sources 移除這筆記下的 Zotero 來源（主來源或附加來源；判定：理由必填、只回在 zoteroSourceRemovals；實寫要求 work 檔已 commit、乾淨）："
                 + "主來源移除後附加來源不升格（primaryRemovedNote），zoteroLinkState 回連結狀態前後，zoteroSourcesRemaining／zoteroSourcesRemainingTotal 是剩下的與總數。"
                 + "remove_sources 收回一條副本宣告（判定：理由必填、只回在 sourcesRemoved；只移除宣告，sources/ 的內容與取得記錄不動；實寫要求 work 檔已 commit、乾淨）。"
                 + "四條腿兩兩不組合。work 無法唯一定位時拒絕。" + legacyCopyNote,
             inputSchema: obj([
                "citekey": str("目標 work 的 citekey"),
                "remove_fields": strArray("<鍵>=理由（鍵與 fields 現有的鍵逐字相符；理由 ≤ 4,096 位元組）。鍵不存在、同鍵兩次、理由空白或過長、超過 200 個 → 整批拒絕零寫入"),
                "add_sources": strArray("digest（sha256: 加 64 個小寫十六進位，0 byte 內容的 digest 拒收；先用 akashic_store_source 存）。本機 sources/ 沒有、index 沒有取得記錄、空內容的 digest、重複、超過 200 個 → 整批拒絕零寫入"),
                "remove_zotero_sources": strArray("<library_id>:<zotero_key>=理由（沒記 library_id 的來源用 ?:<zotero_key>；理由 ≤ 4,096 位元組）。這筆沒有的來源、同來源兩次、形狀錯、理由空白或過長、超過 200 個 → 整批拒絕零寫入"),
                "remove_sources": strArray("<digest>=理由（digest 要在該 work 的 akashic.sources 上；理由 ≤ 4,096 位元組）。不在清單上、digest 形狀不對、理由空白或過長、同一 digest 兩次、超過 200 個 → 整批拒絕零寫入"),
                "dry_run": .object(["type": .string("boolean"), "description": .string("預設 true（只回計畫）；false 才寫")]),
             ], required: ["citekey"])),
        Tool(name: "akashic_venue",
             description: "看一個發表載體：記錄（key／type）＋刊名沿革（names 時間軸）＋通用 references（issn／names 等來源記錄，至多 25 筆，referencesTotal／referencesTruncated 揭露）＋文章編年 list（works，依年升冪）。零篇是合法答案（workCount: 0），與查無此 venue（notFound）分開；store 有 quarantined 檔且查無時回「無法判定」。有才出現的 unknownFields（不認得的欄位名）。",
             inputSchema: obj([
                "key": str("venue key（kebab-case）"),
             ], required: ["key"])),
        Tool(name: "akashic_venues",
             description: "列出全部 venue：回 {count, venues:[{key, type, name, workCount}]}。",
             inputSchema: obj([:])),
        Tool(name: "akashic_add_venue",
             description: "建發表載體實體（venue:）。type 的值域是 \(VenueType.domainDescription)；names 全進沿革時間軸（無時間段），authorized 留空。需 store format ≥ 11。",
             inputSchema: obj([
                "key": str("kebab-case venue key"),
                "names": strArray("名稱變體（正式刊名、縮寫、WoS 大寫形）。檢查同 akashic_update_venue 的 add_names；空白項略過、近重複只留一筆，全部空白＝沒有名字 → 整個呼叫拒絕零寫入。回報：names（存入的拼法）、namesFolded、namesDropped"),
                "type": str(VenueType.domainDescription),
                "note": str("備註（選填）"),
                "issn": strArray("ISSN（可多個：print 與 electronic 是兩個真的號；相等看正規形）；角色寫法同 akashic_update_venue 的 add_issn。任一不合法即整個呼叫拒絕、零寫入。回報 issnMediumRecorded、issnDropped"),
             ], required: ["key", "names", "type"])),
        Tool(name: "akashic_update_venue",
             description: "venue 的部分更新（CLI 對應 `akashic update-venue --help`；名字的不變式見 docs/store-format.md §5.7）。add_names／add_issn／add_variant 是 append：只附加不重複的值，不提供整組替換；authorize 是同書寫系統替換；paginated／clear_paginated 是判定；remove_issn／remove_reference 是移除（判定；remove_reference 單獨呼叫）；edit_name_segment 改或刪名字段（判定）；note／type 替換（選填）。resolve_venues 對沿革各段都配對。各 *Total（namesTotal／issnTotal／variantTotal／authorizedTotal／referencesTotal）是寫後總數；authorizedAdded／variantAdded 是新指定／新標的名字。需 store format ≥ 11。",
             inputSchema: obj([
                "key": str("既有 venue key"),
                "add_names": strArray("要附加的名稱變體（相等看 canonical，以 canonical 形入庫）。回報：namesAdded（新加入）、namesAlreadyPresent（本來就在，不論位元組）、namesFolded（折成 canonical 才存，或同批位元組相同的重複）、namesDropped（空白或近重複，沒進）。含不合法字元（規則見 §5.7）或沒有任何字母或數字的名字 → 整批拒絕零寫入（其他參數也不寫）"),
                "note": str("備註（替換；選填）"),
                "type": str("\(VenueType.domainDescription)（替換；選填）"),
                "add_issn": strArray("要附加的 ISSN（相等看正規形，0003-066x＝0003-066X）。可緊跟角色：\"NNNN-NNNN (print)\"（print／electronic／linking）；已在而無角色的號補上，已記的角色不同即拒。號或角色不合法 → 整個呼叫拒絕零寫入。回報 issnAdded／issnAlreadyPresent／issnMediumRecorded／issnDropped"),
                "add_variant": strArray("要標成異寫法的名字（append；名字檢查同 add_names）。不在 names 裡的一併加進 names。整項空白的不寫，回報在 variantDropped；已是異寫的（寫確認）列在 variantConfirmed"),
                "authorize": strArray("指定為對外形的名字。**不是 append**：每個書寫系統（han／latn／other）至多一個，同書寫系統原本的指定移出 authorized、留在 names、不標 variant（authorizedRemoved）；同一次呼叫兩個同書寫系統的名字整批拒絕。不在 names 的一併加進 names。其他回報：liftedFromVariant、alreadyAuthorized、authorizedRewritten、authorizeDropped"),
                "unauthorize": strArray("撤回對外形：須是現有 authorized，移出後留在 names、不標 variant；authorize 可指定回來但接在 authorized 尾端（位置與預設顯示名可能不同）。非成員、同時在 authorize、被 reference 指著 → 整批拒絕。回報 authorizedWithdrawn（每列 name、呼叫前的 index）、unauthorizeDropped；預設顯示名因此改變時多 displayNameChanged"),
                "clear_paginated": ["type": "boolean", "description": "撤回 paginated 判定、回到未判定狀態：同樣要 judgement，並在 references 留一筆 value=nil 的記錄。與 paginated 不得同時給"],
                "paginated": .object(["type": .string("boolean"),
                    "description": .string("「本刊是否使用頁碼」的判定：true＝傳統頁碼刊、false＝article-number 制。必附 judgement 與 rests_on；省略＝不動既有值（nil 是未判定狀態，floor 檢查對它照報）")]),
                "judgement": str("判定理由：paginated／clear_paginated、add_variant／authorize／unauthorize 必填（後者寫判定記錄、回報 judgementsRecorded、需 format ≥ 22、一次至多 200 個名字；理由要有字母或數字、開頭不得是組合字元），兩類不同呼叫"),
                "rests_on": strArray("判定所依據的證據 digest（sha256:64hex，0 byte 內容拒收；paginated 至少一個、名字分類可省略——先用 akashic_store_source 存證據拿 digest）"),
                "remove_issn": strArray("移除 ISSN：<issn>=理由（必填，只回在 issnRemoved、不寫進 store）；指向該號的 field: issn provenance 一併刪除（issnRemoved[].referencesRemoved）。venue 檔要已在 git 裡 commit、無未提交修改。號不合法、這本刊沒有、重複、或同時在 add_issn → 整批拒絕零寫入"),
                "remove_reference": .object(["type": .string("array"), "items": .object(["type": .string("object")]),
                    "description": .string("移除 references（單獨呼叫）：物件 {field: names|authorized|issn|note, value, reason（必填，只回在 referencesRemoved、不寫進 store）, 選填縮小鍵 kind／url／…（同 references）}；位元組相等定位。venue 檔要已 commit、乾淨。定位不到或多筆、verdict／paginated 欄位、field: variant、只命中名字分類記錄、理由缺、超過 200 筆 → 整批拒絕零寫入")]),
                "edit_name_segment": .object(["type": .string("array"), "items": .object(["type": .string("object")]),
                    "description": .string("改或刪名字段（單獨呼叫）：物件 {name, match?, set 或 remove:true, reason（必填，只回在報告）}；match／set 的鍵 start／end／ended／attested／source／note，null 在 match＝要求缺席、在 set＝清除。git 閘（venue 檔要已 commit）與拒絕類別見 CLI help。刪名字的最後一段時，它的名字分類記錄最後一筆要是撤回（記錄一起刪，judgementRecordsRemoved）。回報 nameSegments（action／before／after）、written（false 時 writeNote）、displayNameChanged（before／after）；超過 20 項 detailsTruncated／detailsListed")]),
                "references": .object(["type": .string("array"), "items": .object(["type": .string("object")]),
                    "description": .string("append-only 的 provenance，與 akashic_update_person 的 references 同一個解析與契約。field 只收 issn／names、帶 value，值要在記錄上（同一次呼叫加的也算）；authorized、note、verdict、paginated 拒收。位元組相同的略過；任一筆不合或空陣列，整個呼叫拒絕零寫入。回報 referencesAdded／referencesAlreadyPresent")]),
             ], required: ["key"])),
        Tool(name: "akashic_resolve_venues",
             description: "venue 解析（literal → venue；完整契約見 CLI `akashic resolve-venues --help` 與 docs/store-format.md §3.5）。不帶寫入腿回 {candidates, ambiguities, suppressed, suppressedTotal, truncated}：candidates 是與 venue name 完全命中（正規化含 lowercase）且不歧義的 literal；ambiguities 是對到 2+ venue、需要判斷的；兩者帶 undecidedChecks；work 或 venue 無法唯一定位（原因見 akashic validate）時該列帶 unlocatableCitekey:true／unlocatableVenueKey:true。suppressed 是被同一 work 同一 venue 另一個拼法的 reject／demote 以正規化配對壓掉的候選（抑制不變；不是可 apply 的候選，沒有 id）：每列 citekey、venueIndex、literal、venueKey、rejectedLiterals（壓住它的拼法，至多 5 個，超過時另有 rejectedLiteralsTotal）；逐字相等的否決是普通已否決、不列。MCP 截 20 筆並受位元組預算（吃不下的整列不印），suppressedTotal 永遠是全數、truncated 說被截；沒有候選被壓時是空陣列與 0。apply（citekey:venueIndex）升格 literal 並寫 resolution-confirmed 到該 venue；reject 寫 resolution-rejected（entry 不動）；apply＋reject 可同一次呼叫（reject 先提交，被它以正規化配對壓掉的 apply id 列在 skippedBecauseRejected）；repoint／demote／undecided／drop_venue 各自單獨呼叫。apply 逐筆略過、其餘照寫的三類：skippedUnlocatable、skippedDuplicateVenueEdge（會造成同一 work 兩條邊指同一 venue；既有的重複邊不擋）、skippedConflictingConfirmedLiteral（目的 venue 已對該 work 持有另一個 confirmed literal，比位元組）。reject／repoint／demote 遇到無法唯一定位的 work 或 venue（repoint 兩端都算）整批拒絕；repoint／demote 另在該 venue 對這筆 work 有 ≥2 個不同 confirmed literal、或配對由多條邊實例化時整批拒絕零寫入。repoint／demote 會刪掉同 holder 上同一配對的相反判定，所以那些 venue 檔要已在 git 裡 commit、無未提交修改（否則整批拒絕）；刪掉的逐字列在 verdictsRetired（截 20 筆，verdictsRetiredTotal／truncated）。各腿回 applied／repointed／demoted（id 清單）與改寫檔數 entriesRewritten／venuesRewritten；apply＋reject 同一次呼叫時各腿收在 legs。需 store format ≥ 11。絕不自動配對。" + legacyCopyNote,
             inputSchema: obj([
                "apply": strArray("要套用的候選 id（citekey:venueIndex）；省略＝只列候選"),
                "reject": strArray("要否決的候選 id（同形）"),
                "repoint": strArray("改指已歸戶的邊（citekey:venueIndex:newKey）：新 venue 寫 confirmed、舊的寫 rejected，並退役兩側的相反判定。整批拒絕零寫入：改指後本 work 兩條邊指同一 venue、目的 venue 會對該 work 持有第二個 confirmed literal（比位元組）、同一條邊指定兩次、同一批同一 work 的兩個 move 帶同一個 literal 且觸及同一 venue（既有的重複邊與 venue 集合不相交的 move 不擋）。改指到自己是 no-op"),
                "demote": strArray("把誤升的邊退回 literal（citekey:venueIndex）：原字串從該 venue 的 confirmed verdict 逐字取回（取不到就拒絕），退役那筆 confirmed、留 rejected"),
                "undecided": strArray("記下查過未決：citekey:venueIndex:venueKey=查了什麼、為何判不出來（需 store format ≥ 19）。寫一筆 resolution-undecided 到該 venue，邊不動。已判定的配對、已歸戶的邊、無法唯一定位的 work、key 重複的 venue 該筆略過並在 skipped（具名）；相同記錄已在＝alreadyRecorded。整批拒絕零寫入：格式錯、重複 id、說明空白、venue 不存在、digest 不合、rests_on 單獨出現、一次超過 200 個 id／20 個 digest／單句說明 4,096 位元組"),
                "rests_on": strArray("未決記錄的證據 digest（sha256:64hex，0 byte 內容的 digest 拒收，先用 akashic_store_source 存檔），套用到這次呼叫的每一筆 undecided；只伴隨 undecided"),
                "drop_venue": strArray("移除 venue 邊：citekey:venueIndex=理由（index 是原始位置）。key 邊只在刪完後本 work 仍有另一條 key 邊指同一 venue 時可刪（否則先 demote）；literal 邊一律可刪。理由必填、只進報告（venueEdgesRemoved）、不寫進 store；那些 work 檔要已在 git 裡 commit、乾淨。整批拒絕零寫入：格式錯、理由空白或超過 4,096 位元組、同一條邊兩次、越界、citekey 無法唯一定位、一次超過 200 條。刪光一筆 work 的 venue 邊時列在 emptied"),
             ])),
        Tool(name: "akashic_add_organization",
             description: "建機構實體（organization:）。parent 以既有 org key 指涉（選填；literal parent 屬 bootstrap 面）。",
             inputSchema: obj([
                "key": str("kebab-case organization key"),
                "names": strArray("名稱變體（中文名、英文名、縮寫）"),
                "parent_key": str("上級機構的 key（選填，需已存在）"),
                "note": str("備註（選填）"),
                "ror": str("ROR ID（選填；純量——一個機構只有一個 ROR。不合法即整個呼叫拒絕、零寫入）"),
             ], required: ["key", "names"])),
        // #557：organization 的 authorized 寫入面；CLI 對應 update-organization，兩面同一個 AkashicService.updateOrganization
        Tool(name: "akashic_update_organization",
             description: "organization 的 authorized（CLI update-organization）。authorize 同 akashic_update_venue 的同名參數，必附 judgement（寫判定記錄）；key 重複、沒給／空陣列／只有空白項、一次超過 200 個名字整批拒絕；都已是對外名稱而同一句理由已是最後一筆記錄＝不寫檔。沒有 unauthorize（給了即拒絕，待裁）。回報 namesAdded、authorizedAdded、authorizedRemoved、alreadyAuthorized、authorizedRewritten、authorizeDropped、authorizedTotal、judgementsRecorded；有事才出現：authorizedNotCurrent（指定的名字沒有開放段、而機構另有現行名稱）、indexRebuilt:false／indexRebuildError／indexNote（已寫檔、index 沒重建）",
             inputSchema: obj([
                "key": str("既有 organization key"),
                "authorize": strArray("對外名稱（同書寫系統替換）"),
                "judgement": str("authorize 的理由（必填）"),
                "rests_on": strArray("證據 digest（可省略）"),
                "remove_names": strArray("刪已撤回的名字（單獨呼叫）：<名字>=理由（只回在 namesRemoved）。最後一筆名字分類記錄要是撤回，名字的每一段連同記錄一起刪；回報 namesTotal；檔要已 commit。沒有記錄、不是撤回、仍是對外名稱 → 整批拒絕"),
             ], required: ["key"])),
        Tool(name: "akashic_resolve_organizations",
             description: "org 解析（literal → organization；完整契約見 CLI `akashic resolve-organizations --help`）。不帶寫入腿回 {candidates, ambiguities}：candidates 是 person affiliations／org parents 的 literal 與某 org name 完全命中且不歧義者。候選列與歧義條目都帶 id 與 undecidedChecks（候選列是整數；歧義條目是 orgKey → 次數、只列非零）；頂層 undecidedTotal（候選配對中查過未決、尚未判定的數目）與 ambiguityUndecidedTotal（歧義條目逐個 org 數）。work、person 或 organization 無法唯一定位（原因見 akashic validate）時該列帶 unlocatableCitekey:true／unlocatablePersonKey:true／unlocatableOrganizationKey:true：這種 id 的 apply／reject 整批拒絕、judge／undecided 該筆略過。apply（候選 id，holderKey::literal）歸戶並寫 confirmed verdict；reject 寫 rejected verdict；需 store format ≥ 8。各寫入腿回自己的清單（applied／rejected／judged／undecided）與改寫檔數 peopleRewritten／organizationsRewritten／entriesRewritten。undecided、judge 各自單獨呼叫。" + legacyCopyNote,
             inputSchema: obj([
                "apply": strArray("要套用的候選 id（holderKey::literal）；省略＝只列候選"),
                "reject": strArray("要否決的候選 id（同形）。那個 org 已確認過同一配對（含拼法變體）時該筆略過、列在 skippedConfirmed"),
                "undecided": strArray("記下查過未決：<列表的 id>@<orgKey>=查了什麼、為何判不出來（需 store format ≥ 19）。id 逐字取自這次列表的候選列或歧義條目（work 作者位是 citekey[i]::literal）；在每個 @<orgKey>= 處試切，恰一處的前綴與列表 id 位元組相同才收；orgKey 須是那一列提名的 org。寫一筆 resolution-undecided 到該 org（work 層級、不帶作者位），holder 不動。已判定的配對、無法唯一定位的 work 或 person 該筆略過並在 skipped（具名）；相同記錄已在＝alreadyRecorded。整批拒絕零寫入：id 解析不出唯一位置或點到 person 與 organization 同 key 的兩列、id 重複、說明空白、org 不存在或不屬於那一列、digest 不合、rests_on 單獨出現、超過上限（200 個 id、20 個 digest、單句 4,096 位元組、單筆 id 長度，見 CLI help）"),
                "rests_on": strArray("未決記錄的證據：sha256:<64 hex> digest（0 byte 內容的 digest 拒收），套用到這次呼叫的每一筆 undecided；只伴隨 undecided（空陣列與省略同義）"),
                "judge": strArray("逐篇判定：<列表的 id>@<orgKey>=理由（id 解析同 undecided，歧義條目也收）；歸戶到 orgKey 並寫 org-judged 層級的 confirmed verdict（理由必填、≤ 4,096 位元組）。輸入錯整批拒絕；citekey 重複、上級機構判給自己或會成環、判給歧義條目裡已否決過這個配對的 org、列表過期，該筆略過並具名。理由存不進去時 judged 列帶 verdictNotRecorded（含原因）。寫入集合先驗，任一筆不過零寫入"),
             ])),
        Tool(name: "akashic_store_source",
             description: "存一份 source 的位元組進 sources/（內容定址）。收**檔案路徑**、不收 base64。"
                 + "回 digest；冪等：同 digest 不重複建 index 條目（indexEntryCreated:false），但這次交來卻**沒被寫入**的敘述以 discardedProvenance 回報；"
                 + "bytesWritten:false＝位址上早有大小相同的一份。位址被目錄、symlink 或大小不同的檔佔住時具名拒絕、不寫 index。"
                 + "retrieved 必填，是「你何時取得這份內容」、不是存入時間。exclusionVerified=false 時拒絕（sources/ 不得進版控 remote）。"
                 + "單檔上限 256 MiB：超過即拒絕、不截斷、零寫入。",
             inputSchema: obj([
                "path": str("要存入的檔案路徑（本機）"),
                "media_type": str("內容的 media type，如 application/pdf"),
                "retrieved": str("**你何時取得**這份內容（ISO 8601），非存入時間"),
                "origin": str("來源（URL 或可辨識的出處敘述）"),
                "acquisition": str("取得方式，如 browser-download / api / scan"),
                "note": str("補充敘述（可選）"),
             ], required: ["path", "media_type", "retrieved", "origin", "acquisition"])),
        Tool(name: "akashic_add_person",
             description: "建人物實體（people/<key>.yaml；aliases、ORCID、OpenAlex）。",
             inputSchema: obj([
                "key": str("kebab-case person key"),
                "names": strArray("aliases——全部進 variant 分割（對外名字之後由 names.authorized 指定，建檔不偽造指定）"),
                "orcid": str("ORCID（可選）"), "openalex": str("OpenAlex author ID（可選）"),
             ], required: ["key", "names"])),
        Tool(name: "akashic_update_person",
             description: "person 的部分更新：提及的欄位整個換、未提及不動；回 key 與 updated（實跑）／wouldChange（dry_run），值是欄位名。純量欄位（orcid/openalex/died/note）收字串或 null（null＝清除）；names 收 {authorized:[…], variant:[…]} object（全量替換；平坦陣列拒收，頂層 authorized 鍵不存在）；profile 收維度 object（維度級覆寫，段形狀同 YAML：value/start/end/ended/source/note）——contacts 是**一個**維度，提及它＝整個 contacts map 替換；references 收 object 陣列，**append-only**（每項 {field, value?, kind: retrieval{url,retrieved,status,media_type,content}|judgement{statement,rests_on}}，比位元組去重——只差 NFC／NFD 的兩筆都會進 store），與 akashic_update_venue 的 references 同一個解析：status 必填（不預設 200）、不認得的鍵拒收、url 只收 http／https 且不含帳密、retrieved 是 ISO 8601、一次至多 200 筆（statement 4,096 位元組、rests_on 20 個）、空陣列拒絕；verdict 欄位對拒收（只能經 resolve 流程寫），名字分類記錄也拒收。names 讓名字進出 authorized 時 judgement 必填，寫指定／確認／撤回記錄（format ≥ 22；回報 judgementsRecorded，dry_run 是 judgementsToRecord）；拿掉有記錄的名字、或對外形整個離開 names 整批拒絕（先移到 variant，再 remove_names）。" + legacyCopyNote,
             inputSchema: obj([
                "key": str("person key"),
                "fields": .object([
                    "type": .string("object"),
                    "description": .string("要更新的欄位（結構化 JSON，見工具描述）；只用 remove_names 時省略"),
                ]),
                "dry_run": .object(["type": .string("boolean"),
                                    "description": .string("true＝只回報會改什麼並預演 format gate、零寫入（預設 false）")]),
                "judgement": str("fields.names 的理由（動到 authorized 時必填；仍是對外形的寫確認）"),
                "rests_on": strArray("judgement 的證據 digest（可省略）"),
                "remove_names": strArray("刪已撤回的名字（單獨呼叫）：<名字>=理由（只回在 namesRemoved）。最後一筆名字分類記錄要是撤回的 variant 名字，連同記錄一起刪；回報 namesTotal；檔要已 commit（dry_run 不查）"),
             ], required: ["key"])),
        Tool(name: "akashic_divergences",
             description: "列出全部歧異記錄：回 {count, divergences:[{id, question, candidates, hasJudgement}]}。list-only——消歧屬人工（CLI resolve-divergence）。",
             inputSchema: obj([:])),
        Tool(name: "akashic_record_divergence",
             description: "記下未決的同一性問題——遇到「這兩筆可能是同一個」時當場記錄而非當場判斷，回新記錄的 id／hasJudgement。消歧（合併＋刪檔）只有 CLI resolve-divergence。同一組候選已有帶判斷的記錄時，無判斷的重錄拒絕；id 只由候選 key 決定，同 id 但候選不同（改名過、或別種形狀）的記錄不覆寫、整個拒絕，要先處置它（resolve-divergence 或 dismiss-divergence）。",
             inputSchema: obj([
                "question": str("未決的是什麼，一句話"),
                "candidates": strArray("候選，形如 key:shape（shape 為 person／organization／work／venue）；需要兩個以上"),
                "judgement": str("已形成的判斷（選填；給了就必須同時給 rests_on）"),
                "rests_on": strArray("判斷依據的存檔 digest（sha256:64hex，0 byte 內容的 digest 拒收；URL 不是合法值——先用 akashic_store_source 存證據拿 digest；選填，與 judgement 成對）"),
                "prefers": str("判斷傾向哪個候選的 key（選填，與 judgement 成對；必須是候選之一）——消歧時不一致即拒絕，但不代選倖存者"),
             ], required: ["question", "candidates"])),
        Tool(name: "akashic_dismiss_divergence",
             description: "放棄一筆歧異記錄：只刪那筆記錄，候選實體與參照不動（問題不成立、候選記錯、或 shape 沒有合併管線時用）。理由必填、只進報告（不寫進 store）；刪除前要求記錄檔已在 git 裡 commit、乾淨，否則拒絕零寫入。dry_run 只回報要刪哪一筆；實跑回 dismissed:true。與 CLI dismiss-divergence 同契約；合併只有 CLI resolve-divergence。",
             inputSchema: obj([
                "id": str("歧異記錄的 id（UUID；先用 akashic_divergences 列出）"),
                "reason": str("為什麼這個問題不成立或不再延後判定（必填，至多 4,096 位元組）"),
                "dry_run": .object(["type": .string("boolean"), "description": .string("true＝只回報、不動檔案（預設 false，與 CLI 同）")]),
             ], required: ["id", "reason"])),
        Tool(name: "akashic_import_zotero",
             description: "觸發 Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）。回傳 import report：created／updated／orphaned／orphanCleared（citekeys；後兩者＝Zotero 端整筆已刪／恢復）、updatedHashOnly（主來源 hash 不同、Zotero 已同步且 version 沒變；照常改寫，不宣稱原因）、secondarySourceChanged／secondarySourceOrphaned／secondarySourceRestored（附加來源變動，entry 與主來源不動）、secondarySourceHashOnly（附加來源，同一判準）、unchanged（筆數）、residualFields（這次讀到的條目中未映射的欄位→條目數）、unnormalizedDates、skippedLinkedAttachments；單筆寫入失敗記入 writeFailed 並續跑（該步未寫入；index 照常重建）。pull 整份替換 fields、覆寫未歸戶作者（updatedHashOnly 也是）：authorsOverwritten（citekeys）、fieldsRemovedByPull（被拿掉的欄位→次數），非空才出現。citekey 清單至多 20 筆：listTotals＝各清單完整筆數，truncatedLists＝被截的清單；writeFailed、quarantineConflicts 不截（CLI 都不截）。同一個來源被多筆 entry 宣稱（含兩筆以上沒記 library_id 的舊檔同裸 key）的條目本趟不更新書目欄位、不新建（歸屬沒有爭議時 orphan 標記照清），列在 ambiguousSourceClaims（來源鍵→citekeys，只在非空時出現；至多 20 個來源、每個至多 20 個 citekey，ambiguousSourceClaimsTotal＝來源總數、ambiguousSourceClaimsTruncated＝有沒有截，CLI 全列；跨記錄警告見 akashic_doctor）。新建的條目與另一筆 work 共用 DOI 時照建，並記一筆沒有判斷的歧異提名（DOI 相等只是提名，判定走 resolve-divergence）：doiNominations 每列 created／other／dois／status（recorded／alreadyRecorded／unlocatable／failed／groupTooLarge）／divergence／error／groupSize，只在非空時出現；在 store 裡的（recorded／alreadyRecorded）與沒記下來的（其餘三種）各受同一個上限。一個 DOI 被超過 10 筆 work 共用時一對都不記、只回一列 groupTooLarge（不帶 other，groupSize＝共用的 work 數）。doiNominationsUnrecorded＝沒記下來的列數（非零才出現）：那幾對重新匯入不會再提名，要記就用 akashic_record_divergence 手記。index rebuild 失敗時錯誤訊息帶同一份報告。" + legacyCopyNote,
             inputSchema: obj([
                "zotero_db": str("zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）"),
                "library_id": int("只拉此 libraryID（省略＝全部 libraries）"),
             ])),
        Tool(name: "akashic_enrich_from_zotero",
             description: "逐筆從 Zotero 補**缺著的**書目欄位。與 akashic_import_zotero 的 pull 語意不同："
                        + "只加原本不存在的鍵，既有值不動；type／title／authors／venues／attachments 不碰。"
                        + "補得到的在 additions（每筆 citekey＋addedFields…）、實寫另回 written／writeFailed。沒補到的都回報：unchanged＝上游也沒有、noProvenance、zoteroMissing、notInStore、unlocatable＝無法唯一定位（原因見 akashic validate）、refusedOnly＝給了識別碼但刻意不收且沒有別的可補（與 unchanged 不同）。"
                        + "建議先 dry_run:true 看計畫。zotero_db 是 server 本機路徑。" + legacyCopyNote,
             inputSchema: obj([
                "citekeys": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("要補值的 citekeys（必填——本 tool 刻意不提供「全部」）"),
                ]),
                "zotero_db": str("zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）"),
                "library_id": int("只讀此 libraryID（省略＝全部）"),
                "dry_run": .object(["type": .string("boolean"),
                                    "description": .string("true＝只回計畫不寫入")]),
             ])),
        Tool(name: "akashic_enrich",
             description: "generic add-only 補值（CLI `akashic enrich --help`；與 akashic_enrich_from_zotero 同一份政策）。"
                        + "每筆提案以 citekey 或 doi（恰一個）指名一筆 work，**只補 fields 裡不存在的鍵**，既有值不動；doi／pmid／isbn 走結構化欄位（部分解析時原字串留在 fields，該筆帶 partial）、"
                        + "issn 一律拒、date 空才補、authors 完全為空且 include_absent_authors 才補 literal；type／title／venues／attachments 不碰。"
                        + "來源四欄（sourceDigest／sourceURL／sourceRetrieved／sourceStatus）齊備時，每個補進去的欄位（fields 的鍵、doi／pmid／isbn、date）同一次寫入一筆 retrieval reference（冪等比位元組）；"
                        + "不齊時（例如只給 sourceDigest）不寫，缺哪些列在 provenanceSkipped；形狀（見 sourceURL／sourceRetrieved／sourceStatus）與 akashic_update_person 的 references 同一份檢查，不合整批拒絕。item 的 provenance 狀態至多一個鍵：provenancePlanned（dry_run）／provenanceWritten／provenanceNotWritten（寫入失敗）；"
                        + "值補了而 reference 刻意不寫的欄位在 provenanceOmitted（欄位 → 理由）：authors 一律不寫；date 需 store format ≥ \(StoreVersion.workDateReferenceFormat)、"
                        + "fields.<鍵> 需 ≥ \(StoreVersion.workFieldReferenceFormat)，低於時值照補、reference 不寫。"
                        + "**dry_run 預設 true**；false 才寫（written 列出寫入的、indexRebuilt 說 index 有沒有重建），I/O 失敗逐筆記 writeFailed、其餘照寫。"
                        + "輸入錯整批拒絕零寫入（錯誤訊息具名是哪一類）；"
                        + "ambiguous（DOI 命中 ≥2 筆，matches 列全部 citekey；或 work 無法唯一定位；該筆零寫入）／notFound／rejected／skipped 逐筆具名在 category；index（提案序）、citekey、additions 補了什麼、alreadyPresent 已有沒補、refused 被拒的值。"
                        + "items 至多 \(enrichItemLimit) 筆（counts／written／writeFailed 永遠完整，itemsTotal／truncated 揭露）；要全部用 CLI `akashic enrich --from … --json`。" + legacyCopyNote,
             inputSchema: obj([
                "proposals": .object([
                    "type": .string("array"),
                    "description": .string("補值提案陣列（每筆 citekey 或 doi 恰一個）"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "citekey": str("目標 citekey（與 doi 二擇一）"),
                            "doi": str("目標 DOI（與 citekey 二擇一；正規形比對 canonical DOI；命中恰一筆才寫）"),
                            "fields": .object([
                                "type": .string("object"),
                                "additionalProperties": .object(["type": .string("string")]),
                                "description": .string("要補的 biblatex 欄位（只補不存在的鍵；第二個摘要用 abstract-<lang>／abstract-2，落地為 abstract_es／abstract_2）"),
                            ]),
                            "date": str("date（entry 的 date 為空時才補）"),
                            "authors": strArray("literal 作者名（authors 完全為空且 include_absent_authors:true 時才補）"),
                            "sourceDigest": str("來源存檔 digest（sha256: 加 64 個小寫十六進位，0 byte 內容的 digest 拒收；不合法整批拒絕）"),
                            "sourceURL": str("這次取得的 URL（http／https；不含帳密，整串不含控制或零寬字元與空白——以百分比編碼送；port 只收數字）"),
                            "sourceRetrieved": str("取得日期（ISO 8601：2026-09-09，或接 THH:MM 與 Z／+08:00）"),
                            "sourceMediaType": str("取得內容的 media type（選填，例如 application/json；不可只有空白，前後無空白、無控制字元）"),
                            "sourceStatus": .object(["type": .string("integer"),
                                                     "description": .string("HTTP 狀態碼 100–599；給了 sourceURL／sourceRetrieved／sourceMediaType 就必填、不預設 200（離線來源只給 sourceDigest）")]),
                        ]),
                    ]),
                ]),
                "dry_run": .object(["type": .string("boolean"),
                                    "description": .string("預設 true（只回計畫）；false 才寫")]),
                "include_absent_authors": .object(["type": .string("boolean"),
                                                   "description": .string("預設 false")]),
             ], required: ["proposals"])),
        Tool(name: "akashic_import_wos",
             description: "匯入 Web of Science 匯出檔（tab-delimited；csv:true 改逗號分隔）。"
                        + "無損匯入：12 具名欄對映＋其餘欄位原樣入 fields；idempotent（citekey＋內容）、既有記錄只補缺欄（enriched）、內容分歧不覆寫（conflicts）。"
                        + "回傳完整 report（created/unchanged/enriched/conflicts/aliasGroups/skippedRows/droppedColumns）。"
                        + "path 是 server 本機路徑。建議先 dry_run:true 看報告；清單層 QA 見 akashic-import-wos skill。" + legacyCopyNote,
             inputSchema: obj([
                "path": str("WoS 匯出檔路徑（server 本機；~ 可用）"),
                "csv": .object(["type": .string("boolean"),
                                "description": .string("true＝來源是逗號分隔（預設 tab）")]),
                "dry_run": .object(["type": .string("boolean"),
                                    "description": .string("true＝只回報會做什麼，不寫檔（預設 false）")]),
             ], required: ["path"])),
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
            // #664：S2 需要網路、必須 async——另走一條路；其他工具照舊走同步的 handleToolCall。
            if params.name == "akashic_s2" { return await AkashicMCPServer.callS2(params) }
            return await self.handleToolCall(params)
        }
    }

    /// `akashic_s2` 的參數解析：與 `handleToolCall` 同一條規則——鍵不在＝沒給；給了而型別不對（null 也算）整個呼叫拒絕。
    static func callS2(_ params: CallTool.Parameters) async -> CallTool.Result {
        func refuse(_ key: String, _ expected: String) -> CallTool.Result {
            CallTool.Result(content: [.text(
                text: "Error: \(displaySafeInvisible(key, max: 60)) 必須是\(expected)——收到別的型別（null 也算）；要省略就不要給這個鍵。拒絕整個呼叫",   // display-safe-exempt: expected 是本檔的編譯期字面
                annotations: nil, _meta: nil)], isError: true)
        }
        let a = params.arguments ?? [:]
        var parsed = S2ToolArguments(endpoint: "")
        for key in ["endpoint", "id", "title", "year", "name"] {
            guard let v = a[key] else { continue }
            guard let s = v.stringValue else { return refuse(key, "字串") }
            switch key {
            case "endpoint": parsed.endpoint = s
            case "id": parsed.id = s
            case "title": parsed.title = s
            case "year": parsed.year = s
            default: parsed.name = s
            }
        }
        for key in ["ids", "fields"] {
            guard let v = a[key] else { continue }
            guard case .array(let arr) = v else { return refuse(key, "字串陣列") }
            let strs = arr.compactMap(\.stringValue)
            guard strs.count == arr.count else { return refuse(key, "字串陣列") }
            if key == "ids" { parsed.ids = strs } else { parsed.fields = strs }
        }
        for key in ["offset", "limit"] {
            guard let v = a[key] else { continue }
            guard case .int(let n) = v else { return refuse(key, "整數") }
            if key == "offset" { parsed.offset = n } else { parsed.limit = n }
        }
        let outcome = await S2Tool.run(parsed)
        return CallTool.Result(content: [.text(text: outcome.text, annotations: nil, _meta: nil)], isError: outcome.isError)
    }

    /// #705：每一次工具呼叫都在一個收集範圍裡跑。範圍內「寫進 entities/、搬移後的 legacy 拷貝沒刪掉」的那一筆寫入照常回傳
    /// （它寫了），結束後放進回應的 `writtenWithLegacyCopy`——成功的 JSON 物件加鍵，錯誤回應附上同一份報告
    /// （`AkashicService.reportingWrittenWithLegacyCopy`）。各工具自己的失敗清單因此不會含它（使用者 2026-09-30 裁決 (a)）。
    /// 放在分派這一層而不是逐工具：新的寫入工具不必記得接它。`akashic_s2` 不寫 store，不經這裡。
    private func handleToolCall(_ params: CallTool.Parameters) -> CallTool.Result {
        let (result, written) = LegacyCopyLedger.collecting { dispatchToolCall(params) }
        // dispatchToolCall 不擲錯（它自己的 catch 是本檔唯一的 Error → 文字出口）；`.failure` 這一格只為了型別完整——收到的照樣帶上
        // （#705 R1 verify 第 36 列：分派是最外層，這裡丟掉就沒有別處報）
        guard case .success(let outcome) = result else {
            return CallTool.Result(content: [.text(text: AkashicService.reportingWrittenWithLegacyCopy("Error: 工具分派失敗", written, isError: true),
                                                   annotations: nil, _meta: nil)], isError: true)
        }
        guard !written.isEmpty else { return outcome }
        let text = outcome.content.compactMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }.joined(separator: "\n")
        let isError = outcome.isError ?? false
        return CallTool.Result(content: [.text(text: AkashicService.reportingWrittenWithLegacyCopy(text, written, isError: isError),
                                               annotations: nil, _meta: nil)], isError: outcome.isError)
    }

    private func dispatchToolCall(_ params: CallTool.Parameters) -> CallTool.Result {
        // **本檔所有具型別的讀取器同一條規則**（#561；R1 verify 起涵蓋 arg／argInt／argFlag／argList／argDict）：
        // 鍵不在＝沒給；**給了而型別不對——JSON null 也算——整個呼叫拒絕、零寫入**，不靜默當成沒給。
        // null 歸「型別不對」而不是「沒給」，理由與 `argFlag` 的既有立場相同：`dry_run: null` 若被當成沒給、折成預設 false，
        // 呼叫端要的乾跑就變成寫入。代價是送 null 表示「省略」的 client 會被拒——錯誤訊息點名是哪個鍵，拿掉那個鍵即可。
        func wrongType(_ key: String, _ expected: String) -> ServiceError {
            .invalid("\(displaySafeInvisible(key, max: 60)) 必須是\(expected)——收到別的型別（null 也算）；要省略就不要給這個鍵。拒絕整個呼叫，零寫入")   // display-safe-exempt: expected 是本檔的編譯期字面
        }
        func arg(_ key: String) throws -> String? {
            guard let value = params.arguments?[key] else { return nil }
            guard let s = value.stringValue else { throw wrongType(key, "字串") }
            return s
        }
        func argInt(_ key: String) throws -> Int? {
            guard let value = params.arguments?[key] else { return nil }
            guard case .int(let n) = value else { throw wrongType(key, "整數") }
            return n
        }
        /// **沒給鍵回 []；給了而形狀不對整個呼叫拒絕、零寫入**（#561）。先前非陣列回 []、非字串元素被
        /// `compactMap` 丟掉：`authorize: "Psychometrika"`（少一層括號）變成 `[]`、零寫入、回報成功；
        /// `["名A", 42]` 變成 `["名A"]`，繞過「同書寫系統兩個名字整批拒絕」那道閘。
        /// 空陣列照舊合法——對用 `argList` 讀的參數，「送了零個」與「沒送」得到同一個結果；有些參數要分辨兩者，
        /// 那些用 `argStrictList` 或在呼叫端先看鍵在不在（例如 `update_venue` 的 `add_names`）。
        func argList(_ key: String) throws -> [String] {
            try argStrictList(key, allowEmpty: true) ?? []
        }
        /// **有給就必須是非空的字串陣列**（change `resolution-verdict-states`，R1 verify security）：當時的 `argList` 對非陣列、
        /// 非字串元素、null 都靜默回 []（#561 起它也拒絕這些，差別只剩空陣列）——未決腿若照用，`rests_on` 給成單一字串時證據被丟掉而回報成功，`undecided: []`
        /// 會落到列表模式、看起來像寫了。沒給鍵回 nil；給了而形狀不對整個呼叫拒絕、零寫入。
        /// `allowEmpty`：選填的證據清單（`rests_on`）收空陣列——零個 digest 是合法的未決記錄，省略與 [] 同義
        /// （R3 verify Codex）；代表寫入動作的鍵（`undecided`）仍拒絕空陣列。
        func argStrictList(_ key: String, allowEmpty: Bool = false) throws -> [String]? {
            guard let value = params.arguments?[key] else { return nil }
            guard case .array(let arr) = value else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 必須是字串陣列——收到別的型別；拒絕整個呼叫，零寫入")
            }
            let strs = arr.compactMap(\.stringValue)
            guard strs.count == arr.count else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 的每個元素都必須是字串；拒絕整個呼叫，零寫入")
            }
            guard allowEmpty || !strs.isEmpty else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 是空陣列——沒有要送的東西就不要給這個鍵")
            }
            return strs
        }
        /// 物件陣列（#587 `update_venue.references`）：沒給鍵回 nil；非陣列、或任一元素不是物件，整個呼叫拒絕（#561 的同形——
        /// 不靜默當未提供）。空陣列原樣交給服務（服務對它有自己的一句話）。元素轉成 `[String: Any]`，型別由服務逐鍵驗。
        func argObjectList(_ key: String) throws -> [Any]? {
            guard let value = params.arguments?[key] else { return nil }
            guard case .array(let arr) = value else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 必須是物件陣列——收到別的型別；拒絕整個呼叫，零寫入")
            }
            return try arr.map { item in
                guard case .object = item, let obj = valueToAny(item) as? [String: Any] else {
                    throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 的每個元素都必須是物件（且巢狀深度不超過 64）；拒絕整個呼叫，零寫入")
                }
                return obj
            }
        }
        /// 同 `argList`（#561 的同形）：`create_entry` 的 `fields: {"year": 2020}` 先前被 `compactMapValues`
        /// 靜默丟掉那個欄位——`lossless-intake` 說的「靜默是最糟的形式」。現在非物件、或任何非字串的值都整個呼叫拒絕。
        func argDict(_ key: String) throws -> [String: String] {
            guard let value = params.arguments?[key] else { return [:] }
            guard case .object(let dict) = value else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 必須是物件（字串對字串）——收到別的型別；拒絕整個呼叫，零寫入")
            }
            let strs = dict.compactMapValues(\.stringValue)
            guard strs.count == dict.count else {
                let badKeys = dict.keys.filter { strs[$0] == nil }.sorted()
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 的值都必須是字串（數字請寫成字串）；拒絕整個呼叫，零寫入。"
                    + "共 \(badKeys.count) 個鍵不是字串："   // display-safe-exempt: Int
                    + badKeys.prefix(10).map { displaySafeInvisible($0, max: 60) }.joined(separator: "、"))
            }
            return strs
        }
        /// **必填的字串**：缺少或全空白整個呼叫拒絕、零寫入（b11c R1 verify 第 42 列）。`arg(k) ?? ""` 讓缺 citekey 的呼叫走到服務裡才回
        /// 「找不到：citekey「」」——那句話像是資料的問題，其實是呼叫端漏了參數。
        func argRequired(_ key: String) throws -> String {
            guard let v = try arg(key), !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.invalid("\(displaySafeInvisible(key, max: 60)) 是必填參數——缺少或只有空白；拒絕整個呼叫，零寫入")   // display-safe-exempt: key 是本檔的編譯期字面
            }
            return v
        }
        /// **畸形 boolean 顯式拒絕，不靜默當未提供**（#406 R1 verify 的同一條理由）：
        /// `"false"`（字串）／null／數字被折成預設值的話，呼叫端以為的乾跑會變成寫入。
        func argFlag(_ key: String, default d: Bool) throws -> Bool {
            guard let raw = params.arguments?[key] else { return d }
            guard case .bool(let b) = raw else {
                throw ServiceError.invalid(
                    "\(displaySafeInvisible(key, max: 60)) 必須是 boolean（true／false）——收到別的型別。"   // key 是本檔的編譯期字面；包起來零代價、守衛不必認得它（R29）
                    + "字串 \"false\" 不是 false；拒絕整個呼叫，零寫入")
            }
            return b
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
                let keys = try argList("citekeys")
                // #165：消毒住 `AkashicService.export()`（MCP 的輸出邊界）——
                // Server 這層不 import AkashicCore，而且那裡才看得到「這份內容
                // 是要回給 LLM」這個事實
                output = try service.export(citekeys: keys.isEmpty ? nil : keys,
                                            format: arg("format") ?? "bib")
            case "akashic_people":
                output = try service.people(query: arg("query"))
            case "akashic_doctor":
                // #581：帶 owner＝單筆記錄的完整明細（唯讀）；不帶＝全庫健康報告（含 index 重建）
                if let owner = try arg("owner") {
                    output = try service.recordIssueDetail(owner: owner)
                } else {
                    output = try service.doctor()
                }
            case "akashic_files":
                output = try service.files(action: arg("action") ?? "list", key: arg("key"))
            case "akashic_person":
                output = try service.person(key: arg("key"), name: arg("name"),
                                            library: arg("library"))
            case "akashic_libraries":
                output = try service.libraries(
                    action: arg("action") ?? "", key: arg("key"), name: arg("name"),
                    description: arg("description"), citekey: arg("citekey"),
                    membership: .init(kind: arg("kind"), venue: arg("venue"), types: argList("types"),
                                      excluded: argList("excluded"), document: arg("document"),
                                      source: arg("source")))
            case "akashic_set_status":
                let clearFlag = try argFlag("clear", default: false)
                output = try service.setStatus(citekey: arg("citekey") ?? "",
                                               status: arg("status"), clear: clearFlag)
            case "akashic_tag":
                output = try service.tag(citekey: arg("citekey") ?? "",
                                         add: argList("add"), remove: argList("remove"))
            case "akashic_link":
                output = try service.link(citekey: arg("citekey") ?? "", kind: arg("kind") ?? "",
                                          add: argList("add"), remove: argList("remove"))
            case "akashic_resolve_people":
                // 「有給 apply 但空陣列」＝套用零筆（no-op），與「未給」（列候選）語意分開
                let applyProvided = params.arguments?["apply"] != nil
                let apply = try argList("apply")
                let rejectProvided = params.arguments?["reject"] != nil
                let reject = try argList("reject")
                let confirmProvided = params.arguments?["confirm_tiers"] != nil
                let confirmTiers = try argList("confirm_tiers")
                let judgeProvided = params.arguments?["judge"] != nil
                let judge = try argList("judge")
                let refuteProvided = params.arguments?["refute"] != nil
                let refute = try argList("refute")
                let undecidedProvided = params.arguments?["undecided"] != nil
                let restsOnProvided = params.arguments?["rests_on"] != nil
                // **兩個結構修正腿各自單獨呼叫，顯式拒絕組合**（R1 verify）：先前靠
                // 分支順序隱含達成，其餘腿被**靜默忽略**——呼叫端（LLM）會以為兩腿都
                // 跑了。同檔 resolve_venues 對同型契約是顯式 throw（#418），對齊。
                // split 改作者位的**數量**（其他腿的 index 意義改變）、attribute_org
                // 升格到另一個值域（「哪些寫了」難以判讀）。
                //
                // 空陣列也拒（`argList` 對它回 []；JSON null 自 #561 起在 `argList` 就被拒）：
                // 「給了鍵但沒有內容」不構成一次呼叫，靜默 no-op 會讓呼叫端以為別的腿跑了。
                let splitProvided = params.arguments?["split_author"] != nil
                let attrOrgProvided = params.arguments?["attribute_org"] != nil
                let unSplitProvided = params.arguments?["un_split"] != nil
                let dropProvided = params.arguments?["drop_author"] != nil
                if splitProvided || attrOrgProvided || unSplitProvided || dropProvided {
                    let otherLegs = applyProvided || rejectProvided || confirmProvided
                        || judgeProvided || refuteProvided || undecidedProvided || restsOnProvided
                    let structural = [splitProvided, attrOrgProvided, unSplitProvided,
                                      dropProvided].filter { $0 }.count
                    if structural > 1 || otherLegs {
                        throw ServiceError.invalid(
                            "split_author／attribute_org／un_split／drop_author 各自單獨呼叫"
                            + "（不得與其他腿或彼此組合）"
                            + "——它們改作者位的數量或值域，混在一批裡會讓其他腿的意義改變")
                    }
                    if dropProvided {
                        let specs = try argList("drop_author")
                        guard !specs.isEmpty else {
                            throw ServiceError.invalid(
                                "drop_author 是空陣列——沒有要移除的東西就不要給這個鍵")
                        }
                        output = try service.dropAuthors(specs)
                    } else if unSplitProvided {
                        let specs = try argList("un_split")
                        guard !specs.isEmpty else {
                            throw ServiceError.invalid(
                                "un_split 是空陣列——沒有要合回的東西就不要給這個鍵")
                        }
                        output = try service.unsplitAuthors(specs)
                    } else if splitProvided {
                        let specs = try argList("split_author")
                        guard !specs.isEmpty else {
                            throw ServiceError.invalid(
                                "split_author 是空陣列——沒有要拆的東西就不要給這個鍵")
                        }
                        output = try service.splitAuthors(specs)
                    } else {
                        let specs = try argList("attribute_org")
                        guard !specs.isEmpty else {
                            throw ServiceError.invalid(
                                "attribute_org 是空陣列——沒有要歸的東西就不要給這個鍵")
                        }
                        output = try service.attributeToOrganizations(specs)
                    }
                    break
                }
                output = try service.resolvePeople(apply: applyProvided ? apply : nil,
                                                   reject: rejectProvided ? reject : nil,
                                                   confirmTiers: confirmProvided ? confirmTiers : nil,
                                                   judge: judgeProvided ? judge : nil,
                                                   refute: refuteProvided ? refute : nil,
                                                   undecided: try argStrictList("undecided"),
                                                   restsOn: try argStrictList("rests_on", allowEmpty: true))
            case "akashic_create_entry":
                output = try service.createEntry(
                    type: arg("type") ?? "", title: arg("title") ?? "",
                    authors: argList("authors"), date: arg("date"), fields: argDict("fields"),
                    doi: params.arguments?["doi"] != nil ? argList("doi") : nil,
                    pmid: params.arguments?["pmid"] != nil ? argList("pmid") : nil,
                    isbn: params.arguments?["isbn"] != nil ? argList("isbn") : nil)
            case "akashic_update_entry":
                output = try service.updateEntry(citekey: argRequired("citekey"),
                                                 removeFields: try argStrictList("remove_fields"),
                                                 addSources: try argStrictList("add_sources"),
                                                 removeZoteroSources: try argStrictList("remove_zotero_sources"),
                                                 removeSources: try argStrictList("remove_sources"),
                                                 dryRun: try argFlag("dry_run", default: true))
            case "akashic_venue":
                output = try service.venue(key: arg("key") ?? "")
            case "akashic_venues":
                output = try service.venues()
            case "akashic_add_venue":
                output = try service.addVenue(
                    key: arg("key") ?? "", names: argList("names"),
                    type: arg("type") ?? "", note: arg("note"),
                    issn: params.arguments?["issn"] != nil ? argList("issn") : nil)
            case "akashic_update_venue":
                let addNamesProvided = params.arguments?["add_names"] != nil
                // **畸形 boolean 顯式拒絕，不靜默當未提供**（#406 R1 verify）：
                // `"false"`（字串）／null／數字被折成 nil 的話，同呼叫的 add_names
                // 照樣寫入、單獨給時回 stale 值——呼叫端以為判定寫了。MCP 的 input
                // schema 不能取代 server-side 驗證。
                let paginatedFlag: Bool?
                if let raw = params.arguments?["paginated"] {
                    guard case .bool(let b) = raw else {
                        throw ServiceError.invalid(
                            "paginated 必須是 boolean（true／false）——收到別的型別。"
                            + "字串 \"false\" 不是 false；拒絕整個呼叫，零寫入")
                    }
                    paginatedFlag = b
                } else { paginatedFlag = nil }
                output = try service.updateVenue(
                    key: arg("key") ?? "",
                    addNames: addNamesProvided ? argList("add_names") : nil,
                    note: arg("note"), type: arg("type"),
                    addISSN: params.arguments?["add_issn"] != nil ? argList("add_issn") : nil,
                    addVariant: params.arguments?["add_variant"] != nil ? argList("add_variant") : nil,
                    authorize: params.arguments?["authorize"] != nil ? argList("authorize") : nil,
                    unauthorize: params.arguments?["unauthorize"] != nil ? argList("unauthorize") : nil,
                    paginated: paginatedFlag,
                    clearPaginated: try argFlag("clear_paginated", default: false),
                    judgement: arg("judgement"),
                    restsOn: params.arguments?["rests_on"] != nil ? argList("rests_on") : nil,
                    removeISSN: try argStrictList("remove_issn"),
                    references: try argObjectList("references"),
                    removeReference: try argObjectList("remove_reference"),
                    editNameSegment: try argObjectList("edit_name_segment"))
            case "akashic_resolve_venues":
                let vApplyProvided = params.arguments?["apply"] != nil
                let vRejectProvided = params.arguments?["reject"] != nil
                let vRepointProvided = params.arguments?["repoint"] != nil
                let vDemoteProvided = params.arguments?["demote"] != nil
                // **修正類的兩個各自單獨呼叫**（兩面同契約，#418）：它們修的是已歸戶的邊，
                // 與升格／否決不同階段；混在一次呼叫裡會讓「哪一批寫了」難以判讀。
                if (vRepointProvided || vDemoteProvided),
                   vApplyProvided || vRejectProvided || (vRepointProvided && vDemoteProvided) {
                    throw ServiceError.invalid("repoint／demote 各自單獨呼叫（不得與 apply／reject 或彼此同時給）")
                }
                output = try service.resolveVenues(
                    apply: vApplyProvided ? argList("apply") : nil,
                    reject: vRejectProvided ? argList("reject") : nil,
                    repoint: vRepointProvided ? argList("repoint") : nil,
                    demote: vDemoteProvided ? argList("demote") : nil,
                    undecided: try argStrictList("undecided"),
                    restsOn: try argStrictList("rests_on", allowEmpty: true),
                    drop: try argStrictList("drop_venue"))
            case "akashic_add_organization":
                output = try service.addOrganization(
                    key: arg("key") ?? "", names: argList("names"),
                    parentKey: arg("parent_key"), note: arg("note"),
                    ror: arg("ror"))
            case "akashic_update_organization":
                // #557 R2 verify（b26 F1 第 3／6／9／21 列）：`unauthorize` 曾在這個工具上（7de07935，同日推上 main）、R1 之後拿掉。server
                // 對多餘的鍵一律忽略，於是照舊說明送 `authorize`＋`unauthorize` 的呼叫端拿到成功、撤回卻被安靜丟掉；CLI 面是未知旗標、exit 64。
                // 對這一個鍵具名拒絕，兩面一致。
                if params.arguments?["unauthorize"] != nil {
                    throw ServiceError.invalid(
                        "akashic_update_organization 沒有 unauthorize——organization 沒有撤回腿（#557：organization 的 names 只增不減，"
                        + "撤回之後剛加進 names 的名字會成為 fallback 顯示名；要不要有、怎麼做待使用者裁決）。要換對外名稱用 authorize"
                        + "（同書寫系統替換，被換下的名字留在 names、寫一筆撤回記錄）；整批拒絕、零寫入")
                }
                output = try service.updateOrganization(
                    key: arg("key") ?? "",
                    authorize: argList("authorize"),
                    judgement: arg("judgement"),
                    restsOn: params.arguments?["rests_on"] != nil ? argList("rests_on") : nil,
                    removeNames: try argStrictList("remove_names"))
            case "akashic_resolve_organizations":
                let oApplyProvided = params.arguments?["apply"] != nil
                let oRejectProvided = params.arguments?["reject"] != nil
                output = try service.resolveOrganizations(
                    apply: oApplyProvided ? argList("apply") : nil,
                    reject: oRejectProvided ? argList("reject") : nil,
                    undecided: try argStrictList("undecided"),
                    restsOn: try argStrictList("rests_on", allowEmpty: true),
                    judge: try argStrictList("judge"))
            case "akashic_store_source":
                output = try service.storeSource(
                    path: arg("path") ?? "", mediaType: arg("media_type") ?? "",
                    retrieved: arg("retrieved") ?? "", origin: arg("origin") ?? "",
                    acquisition: arg("acquisition") ?? "", note: arg("note"))
            case "akashic_add_person":
                output = try service.addPerson(key: arg("key") ?? "", names: argList("names"),
                                               orcid: arg("orcid"), openalex: arg("openalex"))
            case "akashic_update_person":
                let dryRun = try argFlag("dry_run", default: false)
                // #564 第 2 點：remove_names 是單獨呼叫，那時不給 fields；給了 fields 就照舊要它是 object
                let removeNames = try argStrictList("remove_names")
                var fieldsAny: [String: Any] = [:]
                let fieldsGiven = params.arguments?["fields"] != nil
                if fieldsGiven || removeNames == nil {
                    guard let fieldsValue = params.arguments?["fields"],
                          case .object = fieldsValue else {
                        return CallTool.Result(
                            content: [.text(text: "fields 必須是 object（刪名字的 remove_names 單獨呼叫時才可省略）", annotations: nil, _meta: nil)],
                            isError: true)
                    }
                    guard let any = valueToAny(fieldsValue) as? [String: Any] else {
                        return CallTool.Result(
                            content: [.text(text: "fields 的巢狀深度超過 64——不是任何可更新欄位的形狀",
                                            annotations: nil, _meta: nil)],
                            isError: true)
                    }
                    fieldsAny = any
                }
                output = try service.updatePerson(
                    key: arg("key") ?? "", fields: fieldsAny, dryRun: dryRun, fieldsGiven: fieldsGiven,
                    judgement: arg("judgement"),
                    restsOn: params.arguments?["rests_on"] != nil ? argList("rests_on") : nil,
                    removeNames: removeNames)
            case "akashic_divergences":
                output = try service.listDivergences()
            case "akashic_record_divergence":
                output = try service.recordDivergence(
                    question: arg("question") ?? "", candidates: argList("candidates"),
                    judgement: arg("judgement"), restsOn: argList("rests_on"),
                    prefers: arg("prefers"))
            case "akashic_dismiss_divergence":
                output = try service.dismissDivergence(id: arg("id") ?? "", reason: arg("reason") ?? "",
                                                       dryRun: try argFlag("dry_run", default: false))
            case "akashic_import_zotero":
                output = try service.importZotero(zoteroDb: arg("zotero_db"),
                                                  libraryID: argInt("library_id"),
                                                  claimLimit: AkashicMCPServer.ambiguousClaimsLimit,
                                                  listLimit: AkashicMCPServer.importListLimit)
            case "akashic_enrich_from_zotero":
                let enrichKeys = try argList("citekeys")
                let enrichDryRun = try argFlag("dry_run", default: false)
                output = try service.enrichFromZotero(citekeys: enrichKeys,
                                                      zoteroDb: arg("zotero_db"),
                                                      libraryID: argInt("library_id"),
                                                      dryRun: enrichDryRun)
            case "akashic_enrich":
                guard let rawProposals = params.arguments?["proposals"] else {
                    throw ServiceError.invalid("proposals 必填（object 陣列；每筆 citekey 或 doi 恰一個，要補的欄位放 fields）")
                }
                // **同一個 JSON 解析器**：`Value` 是 Codable，先編回 JSON 再用 `Proposal` 的 Decodable 解
                // ——CLI `--from` 讀檔走的是同一個 `init(from:)`，兩面對「什麼是合法的提案」不會分岔。
                let proposals: [AddOnlyEnrichment.Proposal]
                do {
                    proposals = try AddOnlyEnrichment.decodeProposals(from: try JSONEncoder().encode(rawProposals))
                } catch let e as AddOnlyEnrichment.InputError {
                    // 訊息含呼叫端給的鍵名＝未信任字串
                    throw ServiceError.invalid(displaySafeError(e, max: 400))   // InputError 不自帶消毒（描述含呼叫端鍵名），這裡逃一次（R29 D81）
                }
                output = try service.enrich(proposals: proposals,
                                            dryRun: try argFlag("dry_run", default: true),
                                            includeAbsentAuthors: try argFlag("include_absent_authors", default: false),
                                            itemLimit: AkashicMCPServer.enrichItemLimit)
            case "akashic_import_wos":
                let csvFlag = try argFlag("csv", default: false)
                let dryRunFlag = try argFlag("dry_run", default: false)
                output = try service.importWoS(path: arg("path") ?? "",
                                               csv: csvFlag, dryRun: dryRunFlag)
            default:
                return CallTool.Result(content: [.text(
                    text: "Unknown tool: \(displaySafe(params.name, max: 200))",
                    annotations: nil, _meta: nil)], isError: true)
            }
            return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)], isError: false)
        } catch {
            // **MCP 的單一錯誤出口**（#162）——它與 CLI 的頂層 sink（`CLI.swift`）是同一條邊界的兩個面。
            // **這裡自 #554 R29（D81）起只做分流，不再自己逃脫**：R28 把 `StoreYAMLError` 的 127 個擲出站點、`invalidInput` 的兩個
            // 參數、`ServiceError` 的 140 個建構點全部改成在擲出端逃脫（#162 時代那段「約 90 個站點刻意不消毒、靠 sink 兜底」的
            // 描述自 R28 起為假），於是這一行的 `displaySafeMultiline(message)` 對每一則已消毒的訊息**再逃一次**——
            // `Ga\u{005C}u{200B}mma`、`\u{005C}A[a-z0-9]…\u{005C}z`：一句修法指示被改寫成不存在的正則（R28 verify 第 1／7／10／17 列，
            // 真 binary 兩面實測不同字串）。`displaySafeErrorMultiline` 對自帶消毒的錯誤（`SanitizedErrorDescription`）只截、其餘
            // （Yams／I/O）逐行逃一次；`SanitizationBoundaryTests` 掃全樹釘住「Error → 文字只走這個入口」。
            // 前綴進 `displaySafeErrorMultiline` 再截（R30；R29 verify 第 9 列：先截再加 `Error: ` 讓兩面對被截的訊息差 7 個字元）。
            return CallTool.Result(content: [.text(
                text: displaySafeErrorMultiline(error, prefix: "Error: "),
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
