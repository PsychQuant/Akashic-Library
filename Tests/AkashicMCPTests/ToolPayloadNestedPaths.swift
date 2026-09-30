import Foundation

/// 工具描述守衛往下一層檢查的巢狀路徑——**封閉列舉**（#700，使用者 2026-09-30 裁決 (a)）。
///
/// `ToolPayloadKeyGuardTests` 對每個回應取頂層鍵（整個回應是陣列時取元素鍵）；**只有這張表列出的路徑**，它才往下
/// 恰好一層（`NestedPayloadPath` 的三種形狀）取鍵，要求每個鍵以識別字邊界出現在該工具的說明裡，或在
/// `ToolPayloadKeyExemptions` 以全名（`items[].reason`）具名豁免。**表外的巢狀物件與陣列一律不往下看**，列入的路徑
/// 也不看第二層（例如 `items[].provenanceOmitted` 的值是欄位 → 理由的字典，鍵是資料，不往下）。
///
/// 為什麼不對所有巢狀物件遞迴：`tools/list` 有位元組預算（#578，`StdioE2ETests.toolsListByteBudget`），把所有巢狀鍵
/// 都寫進說明，預算放不下。所以預算只花在這裡列出的路徑上，**每一列寫明為什麼那一層的鍵要說明**。
///
/// **新增一列＝顯式裁決**，不得依性質相似類推（「這也是一個物件陣列」不是理由）。加列的前提是有情境產生那條路徑的
/// payload：`testEveryNestedPathIsLive` 要求每一列在至少一個情境的回應裡以宣稱的形狀出現、且取得到鍵——
/// 空掃描不是通過。
enum ToolPayloadNestedPaths {
    struct Row {
        let tool: String
        let path: NestedPayloadPath
        let why: String
    }

    static let rows: [Row] = [
        Row(tool: "akashic_enrich", path: .array("items"),
            why: "每筆提案的結果只在這一層：補了什麼、來源 reference 寫了沒（provenancePlanned／Written／NotWritten／Omitted／Skipped）、"
                + "哪些值被拒。呼叫端判斷這次補值落地了沒，讀的就是這些鍵（#672 點名的 provenance 鍵住在這裡）"),
        Row(tool: "akashic_resolve_people", path: .map("people"),
            why: "歧義條目的 personRefs 是不透明 ref，區辨一個人的欄位（機構、ORCID、卒年）只在這一層送一次。"
                + "呼叫端判斷 ref 指的是誰，讀的就是這些鍵"),
        Row(tool: "akashic_update_entry", path: .array("sourcesAdded"),
            why: "add_sources 宣告的每份副本的取得記錄（來源、取得時間、media type、取得方式）只在這一層；"
                + "呼叫端核對宣告的是不是它要的那份內容，讀的就是這些鍵"),
        Row(tool: "akashic_update_venue", path: .array("nameSegments"),
            why: "edit_name_segment 是判定型寫入，每一段做了什麼（action、改前、改後）只在這一層回報；"
                + "呼叫端核對寫進去的是不是它要的，讀的就是這些鍵"),
        Row(tool: "akashic_update_venue", path: .object("displayNameChanged"),
            why: "沒有 authorized 的 venue 改名字段會連帶換掉對外顯示的名字；換之前、換之後的值只在這一層"),
        Row(tool: "akashic_import_zotero", path: .array("doiNominations"),
            why: "每一對 DOI 提名的結果只在這一層：哪兩筆、共用哪些 DOI、記下了沒（status）、記在哪一筆歧異記錄（divergence）、"
                + "沒記的原因（error）。呼叫端要接著跑 resolve-divergence，讀的就是這些鍵（#611）"),
        Row(tool: "akashic_person", path: .object("person"),
            why: "person key 直查時人物本身的資料（names、affiliations、verdicts）都在這一層；頂層只有 person／publications／"
                + "co_authors 三個容器鍵，不往下看等於整筆人物資料沒有守衛"),
    ]
}
