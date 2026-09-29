/// 一個 CLI 寫入面對目標確認閘（#298）的裁決（#658）。
///
/// **「寫 store」的意思**：建立、改寫或刪除 store root 底下的內容——記錄（`entities/`、`libraries/`）、
/// `store.yaml`、`sources/`、佈局本身。衍生的 index 不算（住在 store 之外、可由 `doctor` 重建），
/// registry（`~/.akashic/config.yaml`）也不在任何 store 裡。
enum WriteGateRuling: Equatable {
    /// 會寫 store，且過閘：未指名目標 store（`--library`／`--yes`）就拒絕。有乾跑的只在真的寫入時檢查。
    case gated
    /// 會寫 store，刻意不閘。字串是這一格的理由——**寫的是這一格自己的事實**，不是一句總括判準。
    case notGated(String)
    /// 不寫任何 store。對命令：整個命令只讀（字串說它做什麼）；對腿：這個旗標自己不觸發寫入
    /// ——列表的篩選、輸出的旋鈕、或另一條腿的參數（字串說它是什麼）。
    case readOnly(String)
    /// 只用在命令層：這個命令有多條寫入腿、各自裁決，見 `DestructiveTargetGate.legRulings`。
    case perLeg
}

/// 逐命令、逐腿的裁決表（#658，使用者 2026-09-28 裁決）。
///
/// ## 為什麼是一張表
///
/// #653 的 `## Expected` 有兩半：逐格裁決，以及「把稽核擴成會抓到新的未閘寫入命令」。
/// 在此之前稽核只認布林的 `--apply`／`--reject`（`DestructiveTargetGateTests`），預設就寫的命令與
/// 逐 id 的寫入腿長出來時它看不到；而 #580 R1 寫過「不閘的只有一類」，當場被找到六個反例——
/// 不閘的理由散在各處的 doc 與散文裡，沒有一處是完整的。
///
/// 所以裁決住在這裡，**每一格都要有**：CLI 的每一個葉命令一格（`library create` 這類巢狀命令以空白
/// 串接路徑），`resolve-people`／`resolve-venues`／`resolve-organizations` 另逐腿一格
/// （它們的每個 `@Option`／`@Flag`，`LibraryOptions` 的橫切選項除外）。
/// `WriteGateRulingsTests` 在執行期列舉 CLI 的命令樹與那三個命令的旗標（ArgumentParser 的 dump-help，
/// 不是文字掃描），與本表雙向比對：多一個命令、多一條腿、或表裡留著已退場的名字，都會紅；
/// 並逐腿跑真 binary，確認 `.gated` 的腿真的被閘擋、其餘的沒有。
///
/// **封閉列舉，不得依性質相似類推**（`common-spec-prose-enumeration`）：新命令或新腿要在這裡加一格、
/// 寫出它自己的理由，不從鄰居推導。`destructiveCommands` 由本表現算，不另維護。
///
/// ## 2026-09-28 的裁決（#658）
///
/// 使用者裁決：`resolve-people --drop-author` 與 `import-zotero` 過閘。兩者都在 #653 R1 verify 被指出
/// 「不閘的並非都可逆」：`--drop-author` 沒有具名逆操作、被移除的作者位不留位置（#457）；`import-zotero`
/// 整份替換 `fields`、覆寫未歸戶的 literal 作者（`fieldsRemovedByPull`／`authorsOverwritten`），而且沒有乾跑。
///
/// ## 誠實邊界
///
/// - **逐腿只做三個命令。** `update-venue`、`update-person`、`library` 等也有多個寫入旗標，但它們以命令為
///   單位裁決：那些命令新長一個寫入旗標時，本表的比對看不到（它只比命令名）。
/// - **理由是人寫的。** 測試只驗「每一格都有、理由非空、`.gated` 與閘的呼叫一致」，驗不了理由對不對。
/// - **不閘的格不都可逆。** #653 的裁決是「只閘使用者點名的不可逆寫入」，而「可逆」的界線沒有一句判準
///   （新增記錄沒有刪除面、`update-person` 整欄替換、`--judge` 沒有具名逆操作……）。各格的理由把自己的
///   事實寫出來，不宣稱可逆；界線待裁，記在 `changelog/2026-09-28-write-gate-rulings.md`。
extension DestructiveTargetGate {

    private static let outsideNamedFamily = "不在 #653 點名的不可逆一族（全庫改寫的合併、改名、格式遷移）"

    /// CLI 每一個葉命令的裁決。鍵是命令路徑（巢狀命令以空白串接，如 `library create`）。
    static let commandRulings: [String: WriteGateRuling] = [
        // ── 過閘 ──
        "import-zotero": .gated,   // #658：pull 整份替換 fields、覆寫未歸戶作者；沒有乾跑
        "migrate": .gated,   // #653：預設就寫，不帶 --dry-run 時閘（以下兩格同）
        "migrate-provenance": .gated,
        "migrate-person-identity": .gated,
        "migrate-identifiers": .gated,   // #394：識別碼自 fields 升格、work 的 issn 移位至 venue——改寫既有記錄
        "migrate-venues": .gated,
        "repair-venue-names": .gated,   // #575：改寫既有 venue 的名字；乾跑預設、--apply 才寫（同 migrate 族）
        "bootstrap-people": .gated,
        "bootstrap-organizations": .gated,
        "bootstrap-venues": .gated,
        "enrich": .gated,   // #458：只加不存在的鍵，但仍改寫既有記錄檔；閘的成本是一行
        "enrich-from-zotero": .gated,
        "update-entry": .gated,   // #544／#614／#680／#677：預設乾跑、--apply 才寫；--remove-field 刪 fields 的值、--add-source 追加副本引用、--remove-zotero-source 拿掉記下的 Zotero 來源、--remove-source 收回副本引用——都改寫既有記錄檔（比照 enrich）；四條腿同一格：閘在命令入口（--apply），不分腿
        "authorize-names": .gated,   // #580 R1 verify：全庫掃蕩的布林 --apply，曾因宣告寫成 `: Bool` 漏在稽核外
        "resolve-divergence": .gated,
        "rename": .gated,   // #650／#653
        "rename-person": .gated,   // #650 R1 verify：一直呼叫本閘，卻曾不在手寫的清單內

        // ── 逐腿裁決 ──
        "resolve-people": .perLeg,
        "resolve-venues": .perLeg,
        "resolve-organizations": .perLeg,

        // ── 會寫 store、刻意不閘 ──
        "doctor": .notGated("只在佈局不存在時建立佈局（ensureLayout），並重建衍生的 index；不改寫任何既有記錄"),
        "import-wos": .notGated("只新增記錄、只補既有記錄上不存在的鍵；與來源不一致時拒絕覆寫、交人（conflicts）；有 --dry-run"),
        "create-entry": .notGated("只新增記錄（citekey 碰撞在批次內消解），不改寫既有記錄；有 --dry-run"),   // display-safe-exempt: notGated：編譯期字面常數（裁決理由），不含 store 衍生內容——「citekey」是欄位名不是某筆記錄的 citekey
        "add-person": .notGated("只新增一筆 person 記錄，不改寫既有記錄"),
        "add-venue": .notGated("只新增一筆 venue 記錄，不改寫既有記錄"),
        "store-source": .notGated("只把一份內容以 digest 定址存進 sources/（不進 git），同一份內容冪等；不改寫任何記錄"),
        "record-divergence": .notGated("新增一筆歧異記錄，或對同一組候選的既有記錄補上／更新判斷（原子替換；無判斷的重錄不得抹掉既有的判斷與 prefers，#133／#159）；刪除面是 dismiss-divergence（#586）"),
        "dismiss-divergence": .gated,   // #586 R1 verify：UUID 由候選 key 決定，錯的 store 上照樣對得上（#580 的判準）；不帶 --dry-run 時閘
        "link": .notGated("集合語意、冪等：--add 與 --remove 互為逆操作（disambiguate-before-irreversible-writes 的不適用類）"),
        "tag": .notGated("集合語意、冪等：--add 與 --remove 互為逆操作（disambiguate-before-irreversible-writes 的不適用類）"),
        "set-status": .notGated("冪等：設定一個狀態值或 --clear（disambiguate-before-irreversible-writes 的不適用類）"),
        "library create": .notGated("只新增一筆 library 記錄，不動任何 entry"),
        "library add": .notGated("集合語意、冪等：與 library remove 互為逆操作；#642 起對規則型／文件型逐筆比對規則，不符的不寫"),
        "library set-kind": .notGated("只改一筆 library 記錄的成員性質與規則、不動任何 entry；整值替換會回顯先前的值，替換既有性質時要求 registry 檔 tracked 且 clean（#573 一族的可回溯閘），所以舊值在 git、再跑一次就改回（#642）"),
        "library remove": .notGated("集合語意、冪等：與 library add 互為逆操作"),
        "file add": .notGated("store 路徑由參數顯式給、不經 registry 的 current 解析；寫 registry，並在佈局不存在時建立佈局"),
        "update-person": .notGated("逐筆指名一個 person key、有 --dry-run；提及的欄位整個替換、未提及的不動，references 只追加（被替換的舊值只在 git 歷史）。" + outsideNamedFamily),
        "fmt": .notGated("把全庫記錄重寫成 canonical form——字面上的 encode(decode(x)) 往返，只改排版不改內容，冪等；--check 只回報不寫。不是 #653 點名的格式遷移：遷移改格式版本與內容形狀，fmt 兩者都不改"),
        "update-venue": .notGated("逐筆指名一個 venue key；名字、ISSN（含角色，已記的角色不改寫）與 --references 以追加為主（#587），--authorize 同書寫系統替換（舊指定留在 names）、--note／--type 替換，--remove-issn 與 --remove-reference 要求 venue 檔已 commit、乾淨（#588／#673）。**這兩條移除腿沒有乾跑，CLI 也不過目標 store 確認閘**（以 venue key ＋ 值的位元組定位，clone 或備份的 store 裡照樣對得上）——防線是 git 閘與整批拒絕零寫入；`update-venue` 整個命令要不要有乾跑（連帶要不要閘）待使用者裁決（b13f R1 verify 第 10／39 列；同族的 `--drop-venue` 在 `resolve-venues` 的逐腿裁決裡是過閘的，`update-entry` 的移除腿則預設乾跑）。" + outsideNamedFamily),

        // ── 不寫 store ──
        "validate": .readOnly("schema 驗證與健康報告：只讀記錄、不寫任何檔"),
        "export-bib": .readOnly("匯出 .bib／CSL-JSON 到 stdout 或 --output 指定的檔"),
        "export-tables": .readOnly("匯出 CSV 與 DuckDB 載入腳本到 --output 目錄"),
        "query": .readOnly("走 index 的查詢"),
        "graph": .readOnly("以一篇為中心的關係圖"),
        "person": .readOnly("person 的讀取面"),
        "people": .readOnly("person 清單的讀取面"),
        "get-entry": .readOnly("work 的讀取面"),
        "divergences": .readOnly("歧異記錄的讀取面"),
        "venue": .readOnly("venue 的讀取面"),
        "venues": .readOnly("venue 清單的讀取面"),
        "view list": .readOnly("列出 config.yaml 宣告的 view"),
        "view show": .readOnly("展開一個 view 的外延（現算，不寫檔）"),
        "library list": .readOnly("列出 libraries 與成員數"),
        "library check": .readOnly("列出一個 library 不符成員規則的成員（#642）"),
        "file list": .readOnly("列出 registry 中已註冊的 store"),
        "file use": .readOnly("只改 registry 的 current，不寫任何 store"),
        "file remove": .readOnly("只自 registry 除名，不刪除任何資料"),
        "references extract": .readOnly("skill 的中間運算（切分 pdftotext 輸出），不寫 store（#617）"),
        "references nominate": .readOnly("skill 的中間運算（兩源提名，唯讀查 DOI 是否已在庫），不寫 store（#617）"),
        "literal-census": .readOnly("四域 literal 普查：只讀記錄檔的 YAML 原文與 store.yaml marker，不寫任何檔、不經 openStore（#629）"),
        "scan-yaml-profile": .readOnly("開發用：掃 YAML 檔統計 profile 外的語法，只讀、不經 openStore（#629）"),
        "fulltext verify": .readOnly("比對本機 PDF 與記錄、印 JSON 判定，不寫任何檔、不經 openStore（#629）"),
        "fulltext url-rule": .readOnly("純字串運算：從落地頁網址推出出版商 PDF 網址（#629）"),
        "fulltext bot-signals": .readOnly("從 stdin 比對頁面文字的起疑訊號，不寫任何檔（#629）"),
        "fulltext jitter": .readOnly("睡一個抽出來的間隔，不寫任何檔（#629）"),
        "fulltext fetch": .readOnly("替 safari-browser 編排一次全文抓取，只寫 --out 指定的檔（在 git 工作樹之外），不經 openStore、不寫 store；存進 store 是之後的 store-source（#629）"),
        "fulltext calibrate": .readOnly("開發用：在本機 PDF 資料夾與 Crossref 回應目錄上量驗證規則，只讀（#629）"),
        "crossref-match": .readOnly("比對本機的作品清單與 Crossref 回應檔，只寫 --out 指定的結果檔，不經 openStore、不寫 store（#629）"),
        "abstracts-to-proposals": .readOnly("adapter：把摘要 NDJSON 轉成 enrich 的提案 JSON，只讀 sources/ 的存檔、只寫 --out 指定的檔，不寫 store（#629）"),
        "s2 author-papers": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 author-search": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 batch": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 citations": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 match": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 paper": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 recommend": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 references": .readOnly("查 Semantic Scholar，不開 store（#664）"),
        "s2 status": .readOnly("只看金鑰讀不讀得到與節流狀態檔，不連網、不開 store（#664）"),
    ]

    /// 逐腿裁決的三個命令。鍵是旗標的主名（`--holder` 的舊名 `--person` 是同一格）。
    static let legRulings: [String: [String: WriteGateRuling]] = [
        "resolve-people": [
            "--apply": .gated,   // 篩選式批次歸戶（#298）
            "--drop-author": .gated,   // #658：沒有具名逆操作，被移除的作者位不留位置（#457）
            "--reject": .notGated("逐 id：只在被判定的 person 記錄追加一筆 rejected verdict，entry 不動、不覆寫或刪除任何既有內容。" + outsideNamedFamily),
            "--refute": .notGated("逐 id、理由必填：只在被判定的 person 記錄追加一筆逐篇層的 rejected verdict，entry 不動。" + outsideNamedFamily),
            "--undecided": .notGated("逐 id、說明必填：只追加一筆 resolution-undecided 記錄，作者位與既有判定都不動（未決不改變任何配對的狀態，#619）"),
            "--judge": .notGated("逐 id、理由必填：作者位由 literal 歸戶給指名的 person、寫一筆逐篇層的 confirmed verdict（已歸戶的只寫並存的判定，#636）；resolve-people 沒有把作者位退回 literal 的工具面。" + outsideNamedFamily),
            "--attribute-org": .notGated("逐 id、理由必填：作者位由 literal 改成 .organization，原 literal 記在該配對的 confirmed verdict；沒有把 .organization 退回 literal 的工具面（zero-instance-guards 第 33 列）。" + outsideNamedFamily),
            "--split-author": .notGated("具名逆操作是 --un-split（#513）；拆分記錄與作者位改寫同一次寫入（#450）"),
            "--un-split": .notGated("具名逆操作是 --split-author；被刪的拆分記錄要求那些 work 檔已 commit、乾淨（#659），原值在 git"),
            "--citekey": .readOnly("--apply 的收窄條件；不帶 --apply 時收窄列表"),
            "--person": .readOnly("--apply 的收窄條件；不帶 --apply 時收窄列表"),
            "--tier": .readOnly("--apply 的收窄條件；不帶 --apply 時收窄列表"),
            "--rests-on": .readOnly("--undecided 的證據參數，只伴隨它"),
            "--rows": .readOnly("歧義段列數上限的旋鈕（#388），只影響列表輸出"),
        ],
        // #580：全部寫入腿都閘——閘防的是寫錯 store，從錯的 store 列出來的 id 在錯的 store 上全部對得上
        "resolve-venues": [
            "--apply": .gated,
            "--reject": .gated,
            "--repoint": .gated,
            "--demote": .gated,
            "--undecided": .gated,
            "--drop-venue": .gated,   // #572
            "--rests-on": .readOnly("--undecided 的證據參數，只伴隨它"),
        ],
        "resolve-organizations": [
            "--apply": .gated,
            "--reject": .gated,   // #580：篩選式寫入
            "--undecided": .gated,   // #580 R2 verify
            "--judge": .gated,   // #647
            "--holder": .readOnly("--apply／--reject 的收窄條件；不帶寫入腿時收窄列表"),
            "--org": .readOnly("--apply／--reject 的收窄條件；不帶寫入腿時收窄列表"),
            "--rests-on": .readOnly("--undecided 的證據參數，只伴隨它"),
        ],
    ]

    /// 過閘的命令——由 `commandRulings`／`legRulings` 現算（命令本身 `.gated`，或至少有一條 `.gated` 的腿）。
    static let destructiveCommands: Set<String> = Set(commandRulings.compactMap { name, ruling in
        switch ruling {
        case .gated: return name
        case .perLeg: return (legRulings[name] ?? [:]).values.contains(.gated) ? name : nil
        case .notGated, .readOnly: return nil
        }
    })

    /// `--yes` 的說明，由表現算——先前那一句手寫的清單在 #653／#572 各漂過一次。
    static var yesHelp: String {
        let commands = commandRulings.filter { $0.value == .gated }.keys.sorted()
        let legs = legRulings.keys.sorted().compactMap { name -> String? in
            let gated = (legRulings[name] ?? [:]).filter { $0.value == .gated }.keys.sorted()
            return gated.isEmpty ? nil : name + " 的 " + gated.joined(separator: "／")
        }
        // 分隔符帶空白：ArgumentParser 只在空白處折行，而 CLI 頂層對輸出逐行截 400（`displaySafeAssembled`）——
        // 不折行的一長串會隨表長大被截掉
        return "我已確認目標是 registry 解析到的那個 store（未指定 --library 時必須；只在真的寫入時檢查，乾跑不擋）。適用： "
            + (commands + legs).joined(separator: "、 ")
    }
}
