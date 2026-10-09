import Foundation

/// 刻意不寫進工具說明的回應鍵——**逐鍵具名、逐鍵寫理由**（`common-spec-prose-enumeration`：能列舉的就列舉，不寫萬用豁免）。
///
/// 三種理由（封閉列舉；新的理由要在這裡加一種並說明，不得從既有的類推）：
/// - `echo`：回顯呼叫端自己給的值，名稱就是意思，呼叫端手上已經有它。
/// - `advisory`：給人讀的固定說明句，內容隨情境變動、呼叫端不需要依它分支。
/// - `standard`：該格式的公開標準欄位（CSL-JSON），契約是那份標準，不是本工具。
///
/// 巢狀路徑表（`ToolPayloadNestedPaths`，#700）上的鍵以全名列（`items[].reason`）；說明比對的是最後那一段鍵名。
///
/// 豁免不是永久的許可：`testEveryExemptionIsLive` 要求每個豁免的鍵**真的出現在** payload、且**真的沒被說明提到**——
/// 說明一旦寫了它、或 payload 不再有它，豁免就紅，逼人把這一列刪掉。
enum ToolPayloadKeyExemptions {
    enum Category: String { case echo, advisory, standard }

    struct Exemption {
        let category: Category
        let why: String
        init(_ category: Category, _ why: String) { self.category = category; self.why = why }
    }

    /// 工具 → 鍵 → 豁免。
    static let keys: [String: [String: Exemption]] = [
        "akashic_add_organization": [
            "names": echo("回顯剛存入的 names——呼叫端剛給的值"),
            "ror": echo("回顯剛存入的 ROR（正規形）——呼叫端剛給的值"),
        ],
        "akashic_add_venue": [
            "issn": echo("回顯剛存入的 ISSN（正規形）；沒存進去的與角色由 issnDropped／issnMediumRecorded 說，參數說明已寫"),
        ],
        "akashic_dismiss_divergence": [
            "candidates": echo("被放棄的那筆記錄的候選——呼叫端剛用 id 指名它"),
            "question": echo("被放棄的那筆記錄的問題——同上"),
            "reason": echo("回顯呼叫端給的理由（全文，理由只進報告）"),
            "dryRun": echo("回顯 dry_run"),
            "note": advisory("乾跑時的固定說明句（不動任何檔案）"),
            "reasonNote": advisory("提醒理由只在報告裡、要留在 git 得寫進 commit message"),
        ],
        "akashic_enrich": [
            "dryRun": echo("回顯 dry_run"),
            "proposals": echo("收到的提案筆數"),
            // #700：巢狀路徑以全名列（`ToolPayloadNestedPaths`）
            "items[].reason": advisory("給人讀的一句話，說明這筆為什麼落在它的 category（citekey 不在、DOI 不合、命中多筆……）；呼叫端依 category 分支"),
        ],
        "akashic_enrich_from_zotero": ["dryRun": echo("回顯 dry_run")],
        "akashic_import_wos": [
            "dryRun": echo("回顯 dry_run"),
            "gitignoreWarning": advisory("讀不懂或 git 不讀的 .gitignore 沒加上 sources 區塊時的說明（原因、匯入不因此中止、要自己加的那段；#700）；匯入不因此中止，呼叫端不依它分支。說明不為它加字（#578 預算），同 mcp-cli-parity 那一格「MCP 說明不寫」"),
        ],
        "akashic_import_zotero": [
            "gitignoreWarning": advisory("同 akashic_import_wos 的 gitignoreWarning（#700）"),
        ],
        "akashic_update_person": [
            "dryRun": echo("回顯 dry_run"),
            "reasonNote": advisory("remove_names 的報告：提醒理由只在報告裡、要留在 git 得寫進 commit message"),
        ],
        "akashic_update_organization": [
            "reasonNote": advisory("remove_names 的報告：提醒理由只在報告裡、要留在 git 得寫進 commit message"),
        ],
        "akashic_set_status": ["status": echo("回顯剛設定的 status（清除時 null）——呼叫端剛給的值。b26 F6：先前只靠 `akashic.status` 這個 store 欄位路徑過關，守衛改成不認別的名字的一段之後現形；說明不為它加字（#578 預算），改具名豁免")],
        "akashic_record_divergence": [
            "candidates": echo("回顯剛記下的候選 key"),
            "prefers": echo("回顯剛記下的傾向（沒給時是 null）"),
            "note": advisory("固定說明句：記下判斷不等於消歧，合併要人工跑 CLI"),
        ],
        "akashic_resolve_organizations": [
            "note": advisory("列表模式的用法提示句（apply／reject／undecided 各帶什麼 id）"),
        ],
        "akashic_resolve_venues": [
            "note": advisory("列表模式的用法提示句（apply／reject 各帶什麼 id）"),
            "emptiedNote": advisory("提醒被刪光 venue 邊的 work 會被 migrate-venues 與 Zotero pull 重新推導"),
            "reasonNote": advisory("提醒理由只在報告裡、要留在 git 得寫進 commit message"),
        ],
        "akashic_update_entry": [
            "dryRun": echo("回顯 dry_run"),
            "dryRunNote": advisory("乾跑時的固定說明句（實跑要 dry_run:false 且檔已 commit）"),
            "reasonNote": advisory("提醒理由只在報告裡、要留在 git 得寫進 commit message"),
            "blobNote": advisory("提醒 remove_sources 只收回宣告、sources/ 的內容不動"),
            "reimportNote": advisory("給人讀的一句話：被移除的來源下一次 import-zotero 會怎樣；結構化的是各筆 zoteroSourceRemovals 的 reimportEffect"),
        ],
        "akashic_update_venue": [
            "reasonNote": advisory("提醒理由只在報告裡、要留在 git 得寫進 commit message"),
            "valueNote": advisory("提醒 remove_reference 只移除 reference、它指的號或名字仍在記錄上"),
        ],
        "akashic_export": [
            "abstract": standard("CSL-JSON 標準欄位"), "author": standard("CSL-JSON 標準欄位"),
            "container-title": standard("CSL-JSON 標準欄位"), "id": standard("CSL-JSON 標準欄位"),
            "issued": standard("CSL-JSON 標準欄位"), "title": standard("CSL-JSON 標準欄位"),
            "type": standard("CSL-JSON 標準欄位"),
        ],
    ]

    private static func echo(_ why: String) -> Exemption { Exemption(.echo, why) }
    private static func advisory(_ why: String) -> Exemption { Exemption(.advisory, why) }
    private static func standard(_ why: String) -> Exemption { Exemption(.standard, why) }

    /// 整個工具的回應不是結構化 JSON（沒有鍵可守）：工具 → 理由。守衛仍要求它有情境並確認它真的回純文字。
    static let textOnlyTools: [String: String] = [
        "akashic_graph": "回傳 Mermaid／DOT／GraphML 文字，不是 JSON",
    ]
}
