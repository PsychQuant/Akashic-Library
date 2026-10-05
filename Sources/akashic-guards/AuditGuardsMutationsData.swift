// **本檔由腳本生成**——那是歷史：#433 時由 `plugin/tests/audit-guards-mutations.py` 生成，
// 該腳本已隨 #433 從 repo 移除（只留在 #433 的 comment 裡），**本檔現為手維護**（#365 fix，
// 2026-09-02 起）。上一行「本檔由腳本生成」這串字**不得刪**：`ZeroInstanceRowsAudit` 用它
// （`prefix(600)`）把本檔排除在 Sources 掃描之外，拿掉它就會把本檔內注入用的 `#9999` 當成
// Sources 裡的真引用，負控從此紅。日後若重跑生成器，#433 comment 裡那份 lambda 要先同步本檔的
// 手改（否則會把它們洗掉）。
// 生成腳本當年**自我驗證**：抽出的 edits 套用結果必須與原
// lambda 逐字相同（import 該模組、拿真檔案當輸入）。沒有那道驗證，兩個抽取缺陷會靜默——
// 兩者都真的發生過：
//   1. **丟掉 `count` 引數**：Python 的 `str.replace(old, new)` 換全部、帶 `count=1` 才換
//      第一個。5 個 case 因此換錯範圍。
//   2. **鏈式 replace 只抽最外層**：`t.replace(A,B).replace(C,D)` 的第一個換掉了。2 個 case
//      因此注入不完整，而守衛照跑、只是不紅——失敗訊息看起來像「守衛對它是盲的」。
//
// `kind` 是封閉列舉：`replaceAll`／`replaceFirst`／`delete` ＋ 六個具名的特殊 edit
// （後者在 `AuditGuardsMutations.swift` 手寫）。同一個 path 可以有多個 edit，**依序套用**。

struct AGMEdit { let path: String; let kind: String; let a: String; let b: String }
struct AGMCase { let desc: String; let guardRel: String; let edits: [AGMEdit]; let expect: [String] }


let agmCases: [AGMCase] = [
    // （#707：`migrated-guard-control` 的格子搬到 `migrated-guard-control-mutations`。那支守衛改讀執行紀錄，不再讀
    //  `run-guards.sh` 的呼叫寫法、`main.swift` 的分派或 harness 的原始碼——這裡原本那 19 格注入的正是那些文字，
    //  對新判準是空轉。#689 的四種形狀與 #707 comment 的六種在新 harness 裡各成一格，而且是真的建置、真的執行。）
    // ── plugin-store-format-parity（#408／#629）：宣告的 store format 必須等於 `StoreVersion.supported` ──
    // 注入不寫死數字（寫死就是第三份副本）：在 `supported` 前面塞一個 `9`（`21` → `921`）、或在宣告的數字前塞一個 `9`，
    // 讓兩邊必然不等，而不必知道當下的版號。
    AGMCase(desc: "psfp：唯一來源 bump 了而兩份宣告沒跟上", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: "Sources/AkashicStoreIO/StoreVersion.swift", kind: "replaceFirst", a: "public static let supported = ", b: "public static let supported = 9"),
    ], expect: ["store format 宣告與唯一來源不一致", "plugin/.claude-plugin/plugin.json: 宣告", "mcpb/manifest.json: 宣告"]),
    AGMCase(desc: "psfp：mcpb 出貨物的宣告被改（Claude Desktop 安裝者看到的那份）", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: "mcpb/manifest.json", kind: "replaceFirst", a: "Store format ", b: "Store format 9"),
    ], expect: ["mcpb/manifest.json: 宣告"]),
    AGMCase(desc: "psfp：plugin.json 的 `Store format N.` 被拿掉（宣告消失不得當成一致）", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: "plugin/.claude-plugin/plugin.json", kind: "replaceFirst", a: "Store format ", b: "Store fmt "),
    ], expect: ["找不到 `Store format N.`"]),
    AGMCase(desc: "psfp：宣告來源檔整個不見（不是「沒有宣告」）", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: "mcpb/manifest.json", kind: "delete", a: "", b: ""),
    ], expect: ["mcpb/manifest.json 不存在或讀不到"]),
    AGMCase(desc: "psfp：marketplace 條目帶了 description（會覆蓋 plugin.json 的第四份副本）", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: ".claude-plugin/marketplace.json", kind: "replaceFirst", a: "\"source\": \"./plugin\",", b: "\"source\": \"./plugin\",\n      \"description\": \"override\","),
    ], expect: ["條目帶了 description", "akashic-mcp"]),
    AGMCase(desc: "psfp：marketplace manifest 不見（前提「marketplace 在本 repo」不成立）", guardRel: "akashic-guards plugin-store-format-parity", edits: [
        AGMEdit(path: ".claude-plugin/marketplace.json", kind: "delete", a: "", b: ""),
    ], expect: ["marketplace.json 不存在"]),
    AGMCase(desc: "coverage①：連結整個拿掉（沒有任何可解析的相對路徑）", guardRel: "akashic-guards rule-coverage", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceAll", a: "../../rules/assertions-must-be-measured.md", b: "見規則目錄"),
    ], expect: ["沒有指向這條規則的可解析相對路徑"]),
    AGMCase(desc: "coverage②：token 是別的檔名（引用不是這條規則本身）", guardRel: "akashic-guards rule-coverage", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceFirst", a: "../../rules/assertions-must-be-measured.md", b: "../../rules/assertions-must-be-measured-v2.md"),
    ], expect: ["的引用不是這條規則本身"]),
    AGMCase(desc: "coverage③：basename 相同但目錄錯（`-f` 解析不到——`.md.bak` 教訓的那一格）", guardRel: "akashic-guards rule-coverage", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceFirst", a: "../../rules/assertions-must-be-measured.md", b: "../../rulez/assertions-must-be-measured.md"),
    ], expect: ["的相對路徑解析不到"]),
    // **#629 R1 verify 第 22 則**：零條規則的分支是移植時新增的（shell 版是意外變紅、Swift 版的空迴圈會直接印綠燈）。它的證據原本是
    // 「移植時的新舊差分（不在 repo）」，於是這條分支沒有任何東西釘住。刪光 `plugin/rules/` 底下的 `.md`（目錄還在）即得那個狀態。
    AGMCase(desc: "coverage④：規則目錄在、一條 .md 規則都沒有（空集合不得冒充通過）", guardRel: "akashic-guards rule-coverage", edits: [
        AGMEdit(path: "plugin/rules/assertions-must-be-measured.md", kind: "delete", a: "", b: ""),
        AGMEdit(path: "plugin/rules/source-of-truth-over-consent.md", kind: "delete", a: "", b: ""),
    ], expect: ["沒有任何 .md 規則檔"]),
    AGMCase(desc: "numbers：把某個數字唯一的行內時間錨拿掉", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/literal-first-then-key.md", kind: "replaceFirst", a: "（#303 實測：2,123/3,720 邊，57.1%）", b: "（實測：2,123/3,720 邊，57.1%）"),
    ], expect: ["沒有時間錨"]),
    AGMCase(desc: "numbers：新增一個裸的 `實測 N`", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "plugin/rules/assertions-must-be-measured.md", kind: "replaceFirst", a: "## 誠實邊界", b: "## 補充\n\n實測 99 筆。\n\n## 誠實邊界"),
    ], expect: ["沒有時間錨"]),
    AGMCase(desc: "numbers：規則目錄整個不見（不得被 CLAUDE.md 撐著回綠）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules", kind: "delete", a: "", b: ""),
    ], expect: ["`.claude/rules/*.md` 一個檔都沒找到"]),
    // #527：守衛的**輸入**不見時，要說「輸入不在」而不是靜默走訪空陣列。在此之前
    // `rawFile` 回 ""，於是這個 case 會走到第 ⑤ 列的「第 5 列不見了或重複」——紅是紅了，
    // 但指向錯的原因（讀者會去看規則檔的第 5 列，而那個檔根本不在）。
    AGMCase(desc: "claims：規則檔整個不見（要說輸入不在，不是說某一列不見）", guardRel: "akashic-guards measured-claims-audit", edits: [
        AGMEdit(path: "plugin/rules/assertions-must-be-measured.md", kind: "delete", a: "", b: ""),
    ], expect: ["讀不到", "守衛的輸入不在"]),
    // ── #526：workflow 的 `run:` 跑的腳本必須存在 ────────────────────────────
    AGMCase(desc: "workflow-run：跑一支不存在的腳本（step 會掛掉並擋住其後全部步驟）", guardRel: "akashic-guards workflow-run-scripts", edits: [
        AGMEdit(path: ".github/workflows/census-parity.yml", kind: "replaceFirst",
                a: "        run: bash .githooks/run-guards.sh",
                b: "        run: bash .githooks/run-guards.sh\n      - name: 負控\n        run: bash tools/gone-526.sh"),
    ], expect: ["tools/gone-526.sh，而那個檔不在", "擋住其後全部步驟"]),
    // 空集合不得冒充通過——#521 close 時我自己的第一版掃描回報「0 個引用、0 個不存在」，
    // 那不是綠，是掃描壞了。刪掉整個 workflow 目錄即得那個狀態；訊息要說得出是哪個原因。
    AGMCase(desc: "workflow-run：workflow 目錄整個不見（0 個引用不是綠）", guardRel: "akashic-guards workflow-run-scripts", edits: [
        AGMEdit(path: ".github/workflows", kind: "delete", a: "", b: ""),
    ], expect: ["一個檔都沒有"]),
    // ── #522：受保護清單的棘輪 ────────────────────────────────────────────
    // `missing` 問的是「列了卻不存在」，而 **glob 成員永遠不會列了卻不存在**——它只會
    // 變少。三組實測（刪守衛／刪 glob 規則檔／拿掉顯式條目）全部 rc=0 印「無缺口」。
    AGMCase(desc: "ratchet：glob 規則檔消失（既有的 missing 檢查對它結構上看不見）", guardRel: "akashic-guards protected-ratchet", edits: [
        AGMEdit(path: ".claude/rules/no-compat-fallback.md", kind: "delete", a: "", b: ""),
    ], expect: ["少了", "no-compat-fallback.md"]),
    // 另一個方向：往已在 CI paths 的路徑根加一個零讀者的檔可以零成本灌水（#522 半二 3），
    // 所以新成員也要被 review。用「從棘輪拿掉一行」模擬（AGM 的 edit 建不了新檔）。
    AGMCase(desc: "ratchet：清單多了一個成員（新成員也要被 review）", guardRel: "akashic-guards protected-ratchet", edits: [
        AGMEdit(path: ".githooks/protected-ratchet.txt", kind: "replaceFirst",
                a: ".claude/rules/apa7-is-the-work-floor.md\n", b: ""),
    ], expect: ["多了", ".claude/rules/apa7-is-the-work-floor.md"]),
    AGMCase(desc: "ratchet：棘輪檔整個不見（沒有基準不是綠）", guardRel: "akashic-guards protected-ratchet", edits: [
        AGMEdit(path: ".githooks/protected-ratchet.txt", kind: "delete", a: "", b: ""),
    ], expect: ["棘輪檔", "不存在"]),
    AGMCase(desc: "numbers：CLAUDE.md 不見（同樣不得被另外兩個來源撐著）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "CLAUDE.md", kind: "delete", a: "", b: ""),
    ], expect: ["`CLAUDE.md` 一個檔都沒找到"]),
    // #711：零實例表的量測搬到 `docs/zero-instance-measurements.md` 之後，那裡的「實測 N」要跟著被讀——檔不見與裸數字各一格。
    AGMCase(desc: "numbers：量測文件不見（不得被其他來源撐著）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "delete", a: "", b: ""),
    ], expect: ["`docs/zero-instance-measurements.md` 一個檔都沒找到"]),
    AGMCase(desc: "numbers：量測文件裡出現一個裸的 `實測 N`", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst", a: "## 各列的歷輪補記", b: "## 補充\n\n實測 88 筆。\n\n## 各列的歷輪補記"),
    ], expect: ["沒有時間錨", "docs/zero-instance-measurements.md"]),
    AGMCase(desc: "numbers：標題用「十五」而表沒有十五列（查表版會靜默略過）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/blocked-issues-must-be-scannable.md", kind: "replaceFirst", a: "（哪些「等」需要標記——封閉列舉，現有 4 列）", b: "（哪些「等」需要標記——封閉列舉，現有十五列）"),
    ], expect: ["現有十五列", "而下方的表有 4 列"]),
    AGMCase(desc: "numbers：標題宣稱列數、自己沒有表，而下一節有（不得借用）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "ziVerdictHeading", a: "## 前言（封閉列舉——現有 6 列）\n\n散文一句。\n\n## 裁決史（一列不多一列不少）", b: ""),
    ], expect: ["最近的表在「## 裁決史（一列不多一列不少）」之後"]),
    AGMCase(desc: "numbers：標題的數字解析不出來（不得靜默略過）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "ziVerdictHeading", a: "## 前言（封閉列舉——現有 廿 列）\n\n散文一句。\n\n## 裁決史（一列不多一列不少）", b: ""),
    ], expect: ["解析不出來"]),
    AGMCase(desc: "numbers：宣稱與表之間隔了兩個標題（診斷要說「隔了 2 個」並具名）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "| # | 情形 | 裁決 | 理由 |", b: "## 插入的空節甲\n\n## 插入的空節乙\n\n| # | 情形 | 裁決 | 理由 |"),
    ], expect: ["隔了 2 個標題", "插入的空節甲", "插入的空節乙"]),
    AGMCase(desc: "numbers：CLAUDE.md 裡出現一個裸的 `實測 N`", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "CLAUDE.md", kind: "replaceFirst", a: "## Rules", b: "## 補充\n\n實測 77 支。\n\n## Rules"),
    ], expect: ["沒有時間錨", "CLAUDE.md"]),
    AGMCase(desc: "numbers：表多一列而標題的計數沒跟上", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/blocked-issues-must-be-scannable.md", kind: "replaceFirst", a: "| 4 | 等時間累積", b: "| 3.5 | 等一個外部帳務事件 | ✅ **`### Blocking`** | 佔位 |\n| 4 | 等時間累積"),
    ], expect: ["現有 4 列", "而下方的表有 5 列"]),
    AGMCase(desc: "numbers：標題宣稱了列數卻沒有表（錨不存在）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "removeTableSeparator", a: "", b: ""),
    ], expect: ["找不到表——錨不存在"]),
    AGMCase(desc: "parity：程式新增一個 MCP tool 而表沒補", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: "Sources/akashic-mcp/Server.swift", kind: "replaceFirst", a: "Tool(name: \"akashic_doctor\"", b: "Tool(name: \"akashic_brandnew\""),
    ], expect: ["在程式裡但**不在規則的 MCP 表**"]),
    AGMCase(desc: "parity：表列了一個程式沒有的 tool", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceFirst", a: "| `akashic_doctor` |", b: "| `akashic_ghost` |"),
    ], expect: ["但程式裡**沒有這個 tool**"]),
    AGMCase(desc: "parity：命令名只出現在某列的理由欄", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceAll", a: "| `fmt` | 有理由缺席", b: "| `fmt-x` | 有理由缺席"),
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceAll", a: "全庫改寫＝維運例外", b: "全庫改寫＝維運例外（同 `fmt`）"),
    ], expect: ["`fmt`", "規則檔裡完全沒提到"]),
    AGMCase(desc: "parity：某命令只在散文被提到、不在任何表列", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceFirst", a: "| `fmt` |", b: "| `fmt-x` |"),
    ], expect: ["`fmt`", "規則檔裡完全沒提到"]),
    AGMCase(desc: "parity：規則檔完全不提某個 CLI subcommand", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceAll", a: "`doctor`", b: "`doktor`"),
    ], expect: ["`doctor`", "規則檔裡完全沒提到"]),
    AGMCase(desc: "parity：表把某命令標成退場但它仍註冊著（表→命令方向）", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceFirst", a: "| ~~`migrate-work-types`~~", b: "| ~~`doctor`~~"),
    ], expect: ["仍註冊在 CLI.swift"]),
    AGMCase(desc: "parity：退場的列沒劃掉（孤兒列）", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceFirst", a: "| ~~`migrate-work-types`~~", b: "| `migrate-work-types`"),
    ], expect: ["已不在 CLI.swift"]),
    AGMCase(desc: "zi-rows：某一列裁決「寫」而它引用的編號在 Sources 裡不存在", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        // **改既有列的編號，不再注入新列**（#365 fix，2026-09-02）。前兩版都靠注入一列：
        // 先是插在第 4 列前編號 `5`（列號連續檢查先觸發、蓋掉本 case 的訊息），再改成
        // 插表尾並**寫死**編號 `12`——而表真的長到 12 列時（#365 補 pseudonym 那列）
        // 注入列就與真列撞號，守衛報「第 13 個是 12」而不是本 case 期望的訊息，
        // pre-push 因此紅。任何寫死的列號都會在表下一次成長時重演。
        //
        // 改成把第 9 列（`Organization.ror`，✅ 寫，唯一引用 #394）的編號換成不存在的
        // #9999：列數、列號、分隔符全不動，表長多少都無所謂，只剩「寫而找不到實作」
        // 這一件事會變。
        //
        // **前提**：第 9 列只引用 #394 這一個編號——守衛的條件是「該列引用的編號**全部**在
        // Sources 找不到才報」。日後若第 9 列多引一個存在於 Sources 的編號，本 case 會**大聲**
        // 失敗（期望 rc=1 卻得 0），不會安靜通過。
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "（#394：`Organization.ror`。", b: "（#9999：`Organization.ror`。"),
    ], expect: ["在 Sources/ 裡都找不到"]),
    // **#479 補的兩格**：`zero-instance-rows-audit` 有四條失敗路徑，先前只有兩條有負控
    // （「✅ 而編號不在 Sources」「完全不引用編號」）。沒有負控的兩條正是 #365 於
    // 2026-08-28 加的——**列號跳號**與**裁決欄挪格**，而那兩條抓的都是「守衛對自己的
    // 覆蓋率說謊」：一列整個被跳過而守衛照樣綠、或判斷的是錯的欄位而照樣印 ✓。
    //
    // **兩個變異都錨在第 1 列的文字上，不碰任何列號。** 這一格上面那段註解記過教訓：
    // 任何寫死的列號都會在表下一次成長時重演（#365 補 pseudonym 那列時就撞過一次）。
    AGMCase(desc: "zi-rows：某一列在共通段沒有 bullet 講它", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        // 錨在**第 1 列的 bullet 文字**上。bullet 不會像注入的新列那樣與真列撞號
        // （上一段記過的那個坑是「注入一列並寫死它的編號」，性質不同）。
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "- 第 1 列的理由是**失敗的不可見性**", b: "- 這一列的理由是**失敗的不可見性**"),
        // expect 錨在那則訊息的**後半段**，不錨「沒有任何 bullet 講它」：那是第 19 列自證閘的片段，寫在這裡就編進
        // `akashic-guards`，真的檢查不在時閘照樣成立（#711 R1 verify 第 6、11 列；守衛自 R1 起擋這件事）。
    ], expect: ["每列理由**彼此不同**的說明"]),
    AGMCase(desc: "zi-rows：列號跳號（一列被整個跳過而守衛照樣綠）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "| 1 | **零實例、成本一行、前件精確**", b: "| 2 | **零實例、成本一行、前件精確**"),
    ], expect: ["裁決表的列號跳號"]),
    AGMCase(desc: "zi-rows：多一個 `|` 讓裁決欄讀到別欄", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        // 插在 issue 編號**之後**——插在前面會先命中「沒有引用任何 issue 編號」那條，
        // 蓋掉本 case 要驗的分支（同一份檔案上面那段記過的同型錯誤）。
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "rationale 種類數 = 0）|", b: "rationale 種類數 = 0|）|"),
    ], expect: ["那不像裁決"]),
    AGMCase(desc: "zi-rows：某一列完全不引用 issue 編號", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "（#254：", b: "（無編號："),
    ], expect: ["沒有引用任何 issue 編號"]),
    // ── #711：`zero-instance-rows-audit` 的第五條失敗路徑——量測指令的自證閘 ─────────────────────────
    // R2 起一條對 binary 輸出計數的量測只有一種合法寫法：`LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'`，
    // `<BIN>` 兩處逐字相同（`selfProofTemplate`）。錨都在**量測段的文字**上（第 13、18、28、36 列的量測、表尾的段落標題），不碰列號。
    // **這一組與別組的輸出互不相同**（各自指名不同的行號與指令），所以不需要進 `PAIRED_IDENTICAL`。
    //
    // **錨字串不得含對 `akashic-guards` 的閘的片段**（#711 R1 verify 第 6、11 列）：這個檔編進 `akashic-guards`，片段寫在這裡，
    // 閘就對沒有那條檢查的 binary 成立——第 19 列（`zero-instance-rows-audit` 那則訊息）與第 70 列（`trigger-coverage` 範圍段的標題）
    // 的片段都不得出現在這裡。對 `akashic` 的閘的片段不受這條限制（`akashic` 的原始碼不含 `akashic-guards` 的目錄）。
    //
    // R2 拿掉 R1 的三格：「量測指令的正對照被拿掉」「正對照寫成否定句」（正對照不再讓別行繼承，它只是註解）、「閘在較早一行」
    // （改成下面的「閘在上一行、以 `\` 接續」，錨到第 18 列）。
    AGMCase(desc: "zi-rows：量測指令的自證閘被拿掉（舊 binary 會印 0）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "\"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["不是唯一合法的寫法", "`\"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'`"]),
    // 閘還在、`LC_ALL=C` 沒了：macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 比不到中文，閘會把新 binary 判成舊的。
    AGMCase(desc: "zi-rows：量測指令的閘沒有 LC_ALL=C", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '重複的判定記錄' \"$(command -v akashic)\"",
                b: "grep -a -q '重複的判定記錄' \"$(command -v akashic)\""),
    ], expect: ["不是唯一合法的寫法", "`grep -a -q '重複的判定記錄'"]),
    // #711 R1（verify 第 2、13 列）：閘以 `;` 接上——閘失敗時被量的指令照跑、印 0。
    AGMCase(desc: "zi-rows：閘與量測指令之間是 ; 不是 &&", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "\"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "\"$(command -v akashic)\"; \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["不是唯一合法的寫法", "\"$(command -v akashic)\"; \"$(command -v akashic)\" validate"]),
    // #711 R1（verify 第 13、27 列）：閘查的 binary 與被量的不是同一支——閘證明不了被量的那支有這條檢查。改的是**被量的**那一處，
    // 閘的片段與目標不動，所以片段的條件照樣通過；錯誤訊息指出兩處各是什麼。
    AGMCase(desc: "zi-rows：閘查的 binary 與被量的不是同一支", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "\"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "\"$(command -v akashic)\" && \"$(command -v akashic-guards)\" validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["閘查的是 `\"$(command -v akashic)\"`，被量的是 `\"$(command -v akashic-guards)\"`"]),
    // #711 R2（verify 第 0、7、11、16 列）：同檔名、不同路徑——R1 只比最後一段，`.build/debug/akashic` 的閘替 `/tmp/old/akashic` 背書，
    // 而舊的那支沒有這條檢查時印 0。
    AGMCase(desc: "zi-rows：閘與被量的同檔名、不同路徑", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "\"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: ".build/debug/akashic && /tmp/old/akashic validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["閘查的是 `.build/debug/akashic`，被量的是 `/tmp/old/akashic`"]),
    // #711 R2（verify 第 1、23 列）：前導的 `||`——shell 解析成 `(true || G) && M`，閘被短路、被量的照跑。R1 只看緊鄰的那個 `&&`。
    AGMCase(desc: "zi-rows：閘前面有 || 讓閘被短路", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "true || LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["不是唯一合法的寫法", "`true || LC_ALL=C grep -a -q"]),
    // #711 R2（verify 第 12、23 列）：尾端的 `|| echo 0`——閘失敗時 `&&` 串失敗、`echo 0` 照跑，舊 binary 又印 0。
    AGMCase(desc: "zi-rows：被量的指令後面接 || echo 0", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "\"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'`",
                b: "\"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict' || echo 0`"),
    ], expect: ["不是唯一合法的寫法", "grep -c '死 verdict' || echo 0`"]),
    // #711 R2（verify 第 13、20、22 列）：包在 `if … then … fi` 裡——R1 的來源樣式錨在第一個 token，`then` 開頭的命令整個不被看見。
    AGMCase(desc: "zi-rows：量測包在 if … then … fi 裡", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "if LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\"; then \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'; fi"),
    ], expect: ["不是唯一合法的寫法", "`if LC_ALL=C grep -a -q"]),
    // #711 R2（verify 第 13、20、22 列）：計數存進變數 `n=$( … )`——R1 把 `$( … )` 裡的運算子整段吞進一個命令，什麼都沒判。
    AGMCase(desc: "zi-rows：量測包在 n=$( … ) 裡", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: "n=$(LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict')"),
    ], expect: ["不是唯一合法的寫法", "`n=$(LC_ALL=C grep -a -q"]),
    // R1 的「閘在較早一行」改錨到第 18 列：閘在上一行、以 `\` 接續到被量的那一行。R2 的單位是一行，第二行沒有閘（R2 verify 第 22 列）；
    // R3 起兩行先接成一個邏輯行——接起來逐字是模板，仍然紅：模板寫在一行（#711 R3 verify 第 3、4、5 列）。
    AGMCase(desc: "zi-rows：閘在上一行、以 \\ 接續", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '截斷會讓一個不是來源給的值進 store' \"$(command -v akashic)\" && \"$(command -v akashic)\" enrich",
                b: "LC_ALL=C grep -a -q '截斷會讓一個不是來源給的值進 store' \"$(command -v akashic)\" && \\\n  \"$(command -v akashic)\" enrich"),
    ], expect: ["起跨 2 行的單位", "\"${over:?mktemp 失敗}\" && test -f"]),   // R4：第 18 列以前置條件開頭，訊息的前 200 字到不了 `enrich`
    // #711 R2（verify 第 14 列）：行尾的 `# 正對照` 不讓同一個區塊後面的計數繼承——R1 讓一行正對照替後面任何 binary 的計數背書。
    AGMCase(desc: "zi-rows：行尾的 # 正對照 不讓同區塊後面的計數繼承", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "--json 2>&1 | grep -c '超過上限'   # 應為 1\n",
                b: "--json 2>&1 | grep -c '超過上限'   # 正對照：應為 1\n\"$(command -v akashic)\" validate 2>&1 | grep -c 'zzz-never-existed-check'\n"),
    ], expect: ["不是唯一合法的寫法", "grep -c 'zzz-never-existed-check'"]),
    // #711 R1（verify 第 14 列）：**空掃描不是通過**——一條被量的指令都沒掃到，代表抽取式與檔的寫法脫節了。
    AGMCase(desc: "zi-rows：量測指令一條都沒掃到", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        // R4：binary 的輸出經管線送進不在「已知不計數」清單裡的命令也算計數，而樣式裡的 `\|` 被當成管線（誤認的方向）——把 `grep -c`
        // 換成 `grep -q` 不再讓每一條都消失。改成讓 binary 的名字消失：變數名不含 akashic 的 `"$B1"` 是誠實邊界裡的「以變數執行」。
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceAll", a: "\"$(command -v akashic)\"", b: "\"$B1\""),
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceAll", a: ".build/debug/akashic-guards", b: "\"$B2\""),
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceAll", a: "\"$(command -v akashic)\"", b: "\"$B1\""),
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceAll", a: ".build/debug/akashic-guards", b: "\"$B2\""),
    ], expect: ["的指令一條都沒掃到"]),
    // #711 R1（verify 第 3、5、10 列）：閘的片段只在 ≤15 位元組的字面段裡——release 版找不到它，閘把有這條檢查的 binary 讀成舊的。
    // 換回第 36 列 R1 之前的片段（13 位元組，`LibraryStore.swift` 裡自成一段）。
    AGMCase(desc: "zi-rows：閘的片段只在短字面段裡（release 版找不到）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "'一個 ISSN 只屬於一本刊'", b: "'個 venue 上'"),
    ], expect: ["只在 `akashic` 原始碼裡短於 16 位元組的字串字面段裡"]),
    // #711 R2（verify 第 21 列）：片段在原始碼裡完全找不到——訊息改了字、或檢查已移除。R1 對它印「字面段太短」那一句，把人導錯方向。
    AGMCase(desc: "zi-rows：閘的片段在原始碼裡找不到（訊息改字）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "'一個 ISSN 只屬於一本刊'", b: "'這則訊息早就改字了'"),
    ], expect: ["在 `akashic` 的原始碼裡找不到（任何字串字面段都沒有）"]),
    // #711 R2（verify 第 17 列）：片段太短——`verdict` 在 `akashic` 裡到處都是，閘恆真。
    AGMCase(desc: "zi-rows：閘的片段太短", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "'不在載入集合，且沒有任何檔宣稱它'", b: "'verdict'"),
    ], expect: ["只有 7 位元組（下限 8）"]),
    // #711 R2（verify 第 17 列）：片段含基本正規式的特殊字元——`grep -a -q` 把 `.` 當任意字元，守衛卻把片段當字面比對。
    AGMCase(desc: "zi-rows：閘的片段含正規式字元", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "'不在載入集合，且沒有任何檔宣稱它'", b: "'store.yaml'"),
    ], expect: ["含基本正規式的特殊字元（`.`）"]),
    // #711 R1（verify 第 6、11 列）：負控 harness 的字串裡出現對 `akashic-guards` 的閘的片段。注入的字串在**執行期**拼起來——
    // 寫成一個字面就是本檔自己把它種進 binary（上面那段說的事）。
    AGMCase(desc: "zi-rows：閘的片段被負控 harness 種進 akashic-guards", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "Sources/akashic-guards/PluginRootsMutations.swift", kind: "replaceFirst",
                a: "import Foundation",
                b: "import Foundation\nlet plantedGateNeedle = \"" + ["沒有任何 bullet", " 講它"].joined() + "\""),
    ], expect: ["出現在負控 harness"]),
    // #711 R2（verify 第 2、4、5、6 列）：fence 沒有收尾——R1 見到 ``` 就切換內外，第 80／81 列的區塊漏了收尾，之後整份檔內外顛倒、
    // 新加的量測區塊不被掃，守衛照樣綠。拿掉第 18 列區塊的收尾：下一個 ```bash 落在它裡面。
    AGMCase(desc: "zi-rows：fence 沒有收尾（下一個 fence 的開頭落在它裡面）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "rm -f \"$over\"\n```\n",
                b: "rm -f \"$over\"\n"),
    ], expect: ["是新 fence 的開頭，卻落在第", "的 fence 沒有收尾"]),
    // 同上，另一種形：最後一節前面多一行 ```bash，到檔尾都沒有收尾。
    AGMCase(desc: "zi-rows：fence 到檔尾都沒有收尾", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 跟其他規則的關係", b: "\n```bash\n## 跟其他規則的關係"),
    ], expect: ["的 fence 到檔尾都沒有收尾"]),
    // #711 R2（verify 第 9、18 列）：`text` fence 照掃——R1 對任何 `text` fence 一律不掃，換個語言標記就能讓量測安靜通過。
    AGMCase(desc: "zi-rows：text fence 照掃", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```text\n\"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'\n```\n\n## 各列共通的東西"),
    ], expect: ["的 `text` fence 裡對 binary 的輸出計數"]),
    // ── #711 R3（b31 W6 第 0、2–7、9、11、12、14、15、19、20 列）：R2 的單位是 fence 內一個實體行、fence 外同一實體行裡的一段 inline code，
    // binary 與計數拆在兩行、寫在 fence 與 inline code 以外、或計數的寫法沒被認出時，那一條不成量測、守衛照樣綠。每一格注入幾種寫法，
    // 每一種各帶一個獨有的記號（`zi-a1-…`），expect 逐一點名——其中一種退回靜默時，那個記號不會出現在輸出裡，這一格就紅。
    // 跨行：`\`、行尾 `|`、`&&`、`||`、`|` 之後的 `#` 註解、下一行開頭的 `|`。
    AGMCase(desc: "zi-rows：跨行的量測（\\、行尾 |／&&／||、# 註解後的 |、下一行開頭的 |）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate 2>&1 \\\n  | grep -c 'zi-a1-backslash'\n\n\"$(command -v akashic)\" validate 2>&1 |\n  grep -c 'zi-a2-pipe'\n\n\"$(command -v akashic)\" validate 2>&1 &&\n  grep -c 'zi-a3-andand' /dev/null\n\n\"$(command -v akashic)\" validate 2>&1 ||\n  grep -c 'zi-a4-oror' /dev/null\n\n\"$(command -v akashic)\" validate 2>&1 |   # 計數\n  grep -c 'zi-a5-comment'\n\n\"$(command -v akashic)\" validate 2>&1\n  | grep -c 'zi-a6-leading'\n```\n\n## 各列共通的東西"),
    ], expect: ["起跨 2 行的單位", "zi-a1-backslash", "zi-a2-pipe", "zi-a3-andand", "zi-a4-oror", "zi-a5-comment", "zi-a6-leading"]),
    // fence 與 inline code 以外：縮排區塊、`<pre>`、散文——一律紅；引用區塊裡的 fence 先剝掉 `>` 再判，它是 fence，所以照模板判。
    // 最後一個 expect 要「輸出計數，卻不是」這一段：不剝 `>` 時三個反引號會被當成一段跨行的 inline code，訊息是「跨行不是唯一合法的寫法」，
    // 只比「不是唯一合法的寫法」會讓這一格對那個退化照綠（守衛的 mutant 實測過）。
    AGMCase(desc: "zi-rows：fence 與 inline code 以外的量測（縮排區塊、<pre>、散文、引用區塊裡的 fence）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n縮排區塊：\n\n    akashic validate 2>&1 | grep -c 'zi-b1-indent'\n\n<pre>\nakashic validate 2>&1 | grep -c 'zi-b2-pre'\n</pre>\n\n"
                    + "散文裡的 akashic validate 2>&1 | grep -c 'zi-b3-prose' 一句。\n\n"
                    + "> ```bash\n> \"$(command -v akashic)\" validate 2>&1 | grep -c 'zi-b4-quote'\n> ```\n\n## 各列共通的東西"),
    ], expect: ["在 fence 與 inline code 以外", "zi-b1-indent", "zi-b2-pre", "zi-b3-prose", "輸出計數，卻不是唯一合法的寫法", "zi-b4-quote"]),
    // inline code 的配對（CommonMark）：跨行的 span、只隔空白而以 `|` 相連的兩段、同一行前面一個孤立的反引號（後面的量測落在散文裡）、
    // 前面一段雙反引號 span（R2 的逐行 regex 讓後面的配對錯位）。
    AGMCase(desc: "zi-rows：inline code 的配對（跨行的 span、只隔空白的兩段、孤立的反引號、雙反引號 span）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n跨行：`\"$(command -v akashic)\" validate 2>&1 |\ngrep -c 'zi-c1-span'` 結束。\n\n"
                    + "兩段：`\"$(command -v akashic)\" validate 2>&1 |` `grep -c 'zi-c2-adjacent'`\n\n"
                    + "孤立的反引號 ` 之後 `\"$(command -v akashic)\" validate 2>&1 | grep -c 'zi-c3-lone'` 結束`\n\n"
                    + "雙反引號 ``echo `date` `` 之後 `\"$(command -v akashic)\" validate 2>&1 | grep -c 'zi-c4-double'` 結束\n\n## 各列共通的東西"),
    ], expect: ["起跨 2 行的單位", "zi-c1-span", "zi-c2-adjacent", "在 fence 與 inline code 以外", "zi-c3-lone", "不是唯一合法的寫法", "zi-c4-double"]),
    // 計數與 binary 的辨識：選項加引號、`-c` 在含 `|` 的樣式之後、BRE 的 `\|`、`uniq -c`、預設值展開 `${X:-akashic}`、`wc -l`、
    // `rg --count`、`egrep -c`、`grep --count`、`~~~` fence。記號放在 <參數> 裡的（`uniq`、`wc`）沒有樣式可放。
    AGMCase(desc: "zi-rows：計數與 binary 的辨識（引號、樣式之後的 -c、uniq -c、${X:-akashic}、wc、rg、egrep、--count、~~~ fence）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`\"$(command -v akashic)\" validate 2>&1 | grep '-c' 'zi-d1-quoted'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | grep -e 'zi-d2|alt' -c`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | grep 'zi-d3\\|bre' -c`\n\n"
                    + "`\"$(command -v akashic)\" validate --zi-d4-uniq 2>&1 | sort | uniq -c`\n\n"
                    + "`${AKASHIC_BIN:-akashic} validate 2>&1 | grep -c 'zi-d5-default'`\n\n"
                    + "`\"$(command -v akashic)\" validate --zi-d6-wc 2>&1 | wc -l`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | rg --count 'zi-d7-rg'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | egrep -c 'zi-d8-egrep'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | grep --count 'zi-d9-long'`\n\n"
                    + "~~~bash\n\"$(command -v akashic)\" validate 2>&1 | grep -c 'zi-d10-tilde'\n~~~\n\n## 各列共通的東西"),
    ], expect: ["不是唯一合法的寫法", "zi-d1-quoted", "zi-d2|alt", "zi-d3", "zi-d4-uniq", "zi-d5-default", "zi-d6-wc", "zi-d7-rg",
                "zi-d8-egrep", "zi-d9-long", "zi-d10-tilde"]),
    // 不再切註解：`$'…'` 裡的 `\'` 讓 R2 的詞法器把後半當註解、shell 照跑（第 15 列）；<參數> 裡的 `#` 讓計數整段落進註解，R3 起模板不收。
    AGMCase(desc: "zi-rows：$'…' 與 <參數> 裡的 #（守衛不再切註解）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate $'\\' # ' 2>&1 | grep -c 'zi-e1-ansi'\n"
                    + "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate # zi-e2-hash 2>&1 | grep -c '死 verdict'\n"
                    + "```\n\n## 各列共通的東西"),
    ], expect: ["不是唯一合法的寫法", "zi-e1-ansi", "zi-e2-hash"]),
    // 閘的片段以 `-` 開頭：`grep -a -q '--include-absent-authors' f` 把片段當選項、結束碼 2，閘恆失敗（第 12 列）。片段在原始碼的長字面段裡，
    // 其餘條件都過，只有這一條紅。
    AGMCase(desc: "zi-rows：閘的片段以 - 開頭", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "'不在載入集合，且沒有任何檔宣稱它'", b: "'--include-absent-authors'"),
    ], expect: ["以 `-` 開頭"]),
    // 棘輪：一條量測改寫成守衛不判讀的寫法（binary 的輸出存進變數、另一段再數——誠實邊界的第 1 類），沒有任何一行紅，合模板的條數掉到下限以下
    // （第 7 列：R2 對同一種改寫 33 條照樣綠）。
    AGMCase(desc: "zi-rows：合模板的量測少於棘輪下限（一條改寫成變數來源）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "`LC_ALL=C grep -a -q '本機缺承重存檔' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '本機缺承重存檔：'`",
                b: "`out=$(\"$(command -v akashic)\" validate 2>&1)`、`printf '%s' \"$out\" | grep -c '本機缺承重存檔：'`"),
    ], expect: ["棘輪標記的下限是"]),
    // ── #711 R4（b33 X6 第 0、1、2、3、4、5、6、7、11、12、13、20、21 列）：R3 仍在列舉「什麼算」，R4 反過來——認不出時偏向「是量測」、
    // 邊界認不出時偏向「同一個單位」。每一格都是**新增**一條沒有閘的量測（不是改寫既有的），合模板的條數不變、棘輪不會紅——抓到它的只能是辨識。
    // 每一種寫法各帶一個獨有的記號（`zr4-…`），其中一種退回靜默時那個記號不出現，這一格就紅。
    // 單位：管線之後的空白行與純註解行照接；下一個有內容的行以 `|` 開頭也照接（第 0 列）。
    AGMCase(desc: "zi-rows：管線跨空白行與純註解行（fence）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate 2>&1 |\n\n  grep -c 'zr4-a1-blank'\n\n"
                    + "\"$(command -v akashic)\" validate 2>&1 |\n# 計數\ngrep -c 'zr4-a2-comment'\n\n"
                    + "\"$(command -v akashic)\" validate --zr4-a3-lead 2>&1\n\n| grep -c 'x'\n```\n\n## 各列共通的東西"),
    ], expect: ["起跨 3 行的單位", "zr4-a1-blank", "zr4-a2-comment", "zr4-a3-lead"]),
    // 單位：以 `|` 開頭的行只有在 GFM 表格裡才是表格列；多行 inline code 裡以 `|` 開頭的續行不切段（第 2 列）。段落、清單項目、引用區塊各一。
    AGMCase(desc: "zi-rows：以 | 開頭而不是表格列的續行", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n段落：`\"$(command -v akashic)\" validate 2>&1\n| grep -c 'zr4-b1-para'` 結束。\n\n"
                    + "- 清單：`\"$(command -v akashic)\" validate 2>&1\n  | grep -c 'zr4-b2-list'`\n\n"
                    + "> 引用：`\"$(command -v akashic)\" validate 2>&1\n> | grep -c 'zr4-b3-quote'`\n\n## 各列共通的東西"),
    ], expect: ["起跨 2 行的單位", "zr4-b1-para", "zr4-b2-list", "zr4-b3-quote"]),
    // 單位：段落最後一段 inline code 以接續運算子結尾、下一段落以 inline code 開頭時接成一個；兩段之間只隔一個接續運算子時也接（第 20 列）。
    AGMCase(desc: "zi-rows：跨段落、以運算子相連的 inline code", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`\"$(command -v akashic)\" validate --zr4-c1-paragraphs 2>&1 |`\n\n`grep -c 'x'`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-c2-operator 2>&1` | `grep -c 'x'`\n\n## 各列共通的東西"),
    ], expect: ["起跨 2 行的單位", "zr4-c1-paragraphs 2>&1 | grep -c 'x'", "zr4-c2-operator 2>&1 | grep -c 'x'"]),   // 接起來的內容：沒接上時前一段單獨也紅（管線之後沒有命令），只比記號會漏
    // 計數：名字以 `grep` 結尾的命令、以 `--cou` 開頭的長選項、binary 的輸出經管線送進不在「已知不計數」清單裡的命令（第 4、7、12、20 列）。
    AGMCase(desc: "zi-rows：計數的辨識（以 grep 結尾的命令、--count-matches、管線進任何命令）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`\"$(command -v akashic)\" validate 2>&1 | ggrep -c 'zr4-d1-ggrep'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | zgrep -c 'zr4-d2-zgrep'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | pcregrep -c 'zr4-d3-pcregrep'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | ugrep -c 'zr4-d4-ugrep'`\n\n"
                    + "`\"$(command -v akashic)\" validate 2>&1 | rg --count-matches 'zr4-d5-matches'`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d6-awk 2>&1 | awk 'END{print NR}'`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d7-nl 2>&1 | nl | tail -1`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d8-sed 2>&1 | sed -n '$='`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d9-python 2>&1 | python3 -c 'import sys; print(len(sys.stdin.readlines()))'`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d10-grepn 2>&1 | grep -n x | tail -n 1`\n\n"
                    + "`\"$(command -v akashic)\" validate --zr4-d11-env 2>&1 | LC_ALL=C sort | uniq`\n\n"
                    // 不經管線的兩種（process substitution）：管線的判準管不到，只靠「名字以 grep 結尾」與「以 --cou 開頭的長選項」
                    + "`ggrep -c 'zr4-d12-procsub' <(\"$(command -v akashic)\" validate 2>&1)`\n\n"
                    + "`rg --count-matches 'zr4-d13-procsub' <(\"$(command -v akashic)\" validate 2>&1)`\n\n## 各列共通的東西"),
    ], expect: ["不是唯一合法的寫法", "zr4-d1-ggrep", "zr4-d2-zgrep", "zr4-d3-pcregrep", "zr4-d4-ugrep", "zr4-d5-matches", "zr4-d6-awk",
                "zr4-d7-nl", "zr4-d8-sed", "zr4-d9-python", "zr4-d10-grepn", "zr4-d11-env", "zr4-d12-procsub", "zr4-d13-procsub"]),
    // binary：參數展開不帶冒號的預設值、名字的大小寫（第 4、20 列；macOS 的檔案系統不分大小寫）。
    AGMCase(desc: "zi-rows：binary 的辨識（${X-akashic}、大小寫）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`\"${AKASHIC_BIN-akashic}\" validate 2>&1 | grep -c 'zr4-e1-dash'`\n\n"
                    + "`~/bin/Akashic validate 2>&1 | grep -c 'zr4-e2-case'`\n\n## 各列共通的東西"),
    ], expect: ["不是唯一合法的寫法", "zr4-e1-dash", "zr4-e2-case"]),
    // `${V:?…}` 寫在管線裡只結束那一段的子 shell，計數照印 0（第 1、3、5 列）：量測與非量測的單位都紅。
    AGMCase(desc: "zi-rows：管線裡的 ${V:?…}", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate --library \"${STORE:?zr4-f1-args}\" 2>&1 | grep -c '死 verdict'`\n\n"
                    + "`find \"${STORE:?zr4-f2-find}/sources\" -name 'x' | wc -l`\n\n## 各列共通的東西"),
    ], expect: ["寫在管線裡", "zr4-f1-args", "zr4-f2-find"]),
    // 前置條件：<參數> 用到的變數要在最前面的 `: "${V:?…}"` 裡；`--library "$V"` 要 `test -f "$V/store.yaml"`（第 1、3、5、15 列）。
    AGMCase(desc: "zi-rows：量測缺前置條件", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate --library \"$STORE\" --zr4-g1 2>&1 | grep -c '死 verdict'`\n\n"
                    + "`: \"${STORE:?x}\" && LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate --library \"$STORE\" --zr4-g2 2>&1 | grep -c '死 verdict'`\n\n## 各列共通的東西"),
    ], expect: ["前面卻沒有 `: \"${STORE:?…}\" && `", "zr4-g1", "前面卻沒有 `test -f \"$STORE/store.yaml\" && `", "zr4-g2"]),
    // 退場標記不再是出口（第 6、11、13、21 列）：既有的 `text` 區塊裡把一行換成沒有閘的量測（個數、行數都不變），以及新加一個帶舊標記的區塊。
    AGMCase(desc: "zi-rows：退場標記不再是出口", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "out=$(.build/debug/akashic-guards migrated-guard-control); echo \"rc=$?\"   # 2026-09-30：rc=0\n",
                b: "\"$(command -v akashic)\" validate 2>&1 | grep -c 'zr4-h1-replaced'\n"),
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n<!-- zero-instance-rows-audit: 已退場的量測紀錄，不掃 -->\n```text\n\"$(command -v akashic)\" validate 2>&1 | grep -c 'zr4-h2-marker'\n```\n\n## 各列共通的東西"),
    ], expect: ["`text` fence 照掃", "zr4-h1-replaced", "zr4-h2-marker"]),
    // 棘輪依閘去重（第 21 列）：一條量測改寫成變數來源、另貼一份既有量測的複本——不去重的話條數不變、地板照樣滿足。
    AGMCase(desc: "zi-rows：同一道閘的複本不撐地板", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "`LC_ALL=C grep -a -q '本機缺承重存檔' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '本機缺承重存檔：'`",
                b: "`out=$(\"$(command -v akashic)\" validate 2>&1)`、`printf '%s' \"$out\" | grep -c '本機缺承重存檔：'`"),
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'`\n\n## 各列共通的東西"),
    ], expect: ["棘輪標記的下限是"]),
    // ── #711 R4（b33 X6 第 19 列）：R3 的辨識分支多數沒有負控——13 個原始碼突變體 12 個存活。R4 把「管線進任何命令」設成計數之後，
    // R3 那幾格以管線寫的 `uniq -c`／`wc -l`／`rg --count` 不再區分得出計數辨識本身，所以這裡補不經管線的寫法（process substitution），
    // 接續與段落邊界各一個記號。段落邊界那幾格的記號放在「`：`」之後：邊界在時那一段是 inline code、訊息是「卻不是唯一合法的寫法 `…`：`<內容>`」，
    // 邊界被拿掉時前一行孤立的反引號與它的開頭配對、量測落進散文，訊息換成「在 fence 與 inline code 以外…：`<內容>`」——只比記號兩種都綠。
    AGMCase(desc: "zi-rows：接續與段落邊界（行尾 |&、下一行開頭的 &&、反斜線奇偶、清單、引用加深、HTML 註解、標題）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate --zr4-i1-pipeamp 2>&1 |&\ngrep -c 'x'\n\n"
                    + "LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' \"$(command -v akashic)\"\n&& \"$(command -v akashic)\" validate --zr4-i2-leadand 2>&1 | grep -c '死 verdict'\n\n"
                    + "echo zr4 \\\\\n\"$(command -v akashic)\" validate --zr4-j5-parity 2>&1 | grep -c 'x'\n```\n\n"
                    + "- 甲 ` 孤立\n- `\"$(command -v akashic)\" validate --zr4-j1-list 2>&1 | grep -c 'x'`\n\n"
                    + "乙 ` 孤立\n> `\"$(command -v akashic)\" validate --zr4-j2-quote 2>&1 | grep -c 'x'`\n\n"
                    + "丙 ` 孤立\n<!-- zr4 -->\n`\"$(command -v akashic)\" validate --zr4-j3-comment 2>&1 | grep -c 'x'`\n\n"
                    + "丁 ` 孤立\n### zr4 標題\n`\"$(command -v akashic)\" validate --zr4-j4-heading 2>&1 | grep -c 'x'`\n\n## 各列共通的東西"),
    ], expect: ["起跨 2 行的單位", "--zr4-i1-pipeamp 2>&1 |& grep -c 'x'", "akashic)\" && \"$(command -v akashic)\" validate --zr4-i2-leadand",
                "`：`\"$(command -v akashic)\" validate --zr4-j5-parity", "`：`\"$(command -v akashic)\" validate --zr4-j1-list",
                "`：`\"$(command -v akashic)\" validate --zr4-j2-quote", "`：`\"$(command -v akashic)\" validate --zr4-j3-comment",
                "`：`\"$(command -v akashic)\" validate --zr4-j4-heading"]),
    // 不經管線的計數：計數命令在前、binary 在 `<( … )` 裡——管線的判準管不到，只靠計數命令與計數選項的辨識。
    AGMCase(desc: "zi-rows：不經管線的計數（ag、ack、uniq、wc、jq length、--cou）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n`ag -c 'zr4-i3-ag' <(\"$(command -v akashic)\" validate 2>&1)`\n\n"
                    + "`ack -c 'zr4-i4-ack' <(\"$(command -v akashic)\" validate 2>&1)`\n\n"
                    + "`uniq -c <(\"$(command -v akashic)\" validate --zr4-i5-uniq 2>&1)`\n\n"
                    + "`wc -l <(\"$(command -v akashic)\" validate --zr4-i6-wc 2>&1)`\n\n"
                    + "`jq length <(\"$(command -v akashic)\" validate --zr4-i7-jq 2>&1)`\n\n"
                    + "`grep --cou 'zr4-i8-abbrev' <(\"$(command -v akashic)\" validate 2>&1)`\n\n## 各列共通的東西"),
    ], expect: ["不是唯一合法的寫法", "zr4-i3-ag", "zr4-i4-ack", "zr4-i5-uniq", "zr4-i6-wc", "zr4-i7-jq", "zr4-i8-abbrev"]),
    // 散文的同一組判斷（R4 起與 fence、inline code 同一把）：縮排區塊裡隔著空白行、下一行以 `|` 開頭；引用區塊裡沒收尾的 inline code 接到
    // 下一行沒有 `>` 的 lazy continuation；HTML 實體寫的 `|`。三種在 R4 之前都切成兩半或認不出管線。
    AGMCase(desc: "zi-rows：散文跨空白行、引用區塊的 lazy continuation、實體寫的 |", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n    akashic validate --zr4-j8-indent 2>&1\n\n    | grep -c 'x'\n\n"
                    + "> 見 `\"$(command -v akashic)\" validate --zr4-j7-lazy 2>&1 |\ngrep -c 'x'` 結束\n\n"
                    + "散文 akashic validate --zr4-j6-entity 2>&amp;1 &#124; sort 一句。\n\n## 各列共通的東西"),
    ], expect: ["在 fence 與 inline code 以外", "zr4-j8-indent", "起跨 2 行的單位", "zr4-j7-lazy", "zr4-j6-entity"]),
    AGMCase(desc: "zi-rows：棘輪標記不見", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "<!-- zero-instance-rows-audit 棘輪：", b: "<!-- 棘輪："),
    ], expect: ["棘輪標記要恰好一個（找到 0 個）"]),
    // ── #711（使用者 2026-10-05 裁決）：規則檔拆成規則檔＋量測文件。守衛改讀兩份，每一條新分支各一格。
    // 量測文件不在：不得當成「沒有量測」——自證閘與棘輪都沒有輸入時要說輸入不在。
    AGMCase(desc: "zi-rows：量測文件不見（不得當成沒有量測）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "delete", a: "", b: ""),
    ], expect: ["找不到 docs/zero-instance-measurements.md", "自證閘與棘輪都沒有輸入"]),
    // 棘輪標記搬回規則檔：兩份各一個時地板有兩個數。量測文件那一個留著，只多規則檔這一個。
    AGMCase(desc: "zi-rows：棘輪標記出現在規則檔", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n<!-- zero-instance-rows-audit 棘輪：合模板的量測（依 binary 與閘的片段去重）至少 1 條 -->\n\n## 各列共通的東西"),
    ], expect: ["棘輪標記住在 docs/zero-instance-measurements.md", "裡不得有（找到 1 個）"]),
    // 規則裡的模板與守衛的 `selfProofTemplate` 分岔：照規則寫的量測會被守衛判紅。拿掉規則那一行的 `LC_ALL=C`。
    AGMCase(desc: "zi-rows：量測寫法規則裡的模板與守衛分岔", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/measurement-commands-self-prove.md", kind: "replaceFirst",
                a: "]]LC_ALL=C grep -a -q '<片段>' <BIN>", b: "]]grep -a -q '<片段>' <BIN>"),
    ], expect: ["裡找不到與守衛逐字相同的模板", "measurement-commands-self-prove.md"]),
    // 規則被刪：「沒有東西可比」不得冒充「一致」。
    AGMCase(desc: "zi-rows：量測寫法規則不見", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/measurement-commands-self-prove.md", kind: "delete", a: "", b: ""),
    ], expect: ["找不到 .claude/rules/measurement-commands-self-prove.md"]),
    // 規則檔仍被掃：表格裡沒有閘的量測照樣紅（第 56 列的量測寫在表格裡）。錨在第 56 列那一條的閘上，拿掉閘。
    AGMCase(desc: "zi-rows：規則檔表格裡的量測少了閘", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "`LC_ALL=C grep -a -q '附加 Zotero 來源沒記 library_id' \"$(command -v akashic)\" && ",
                b: "`"),
    ], expect: [".claude/rules/zero-instance-guards.md 第", "不是唯一合法的寫法", "grep -c '附加 Zotero 來源沒記 library_id'"]),
    AGMCase(desc: "ratchet：同名誘餌 ＋ 真欄位改型別（裸名鍵會被騙過）", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: "Sources/AkashicCore/Models.swift", kind: "replaceFirst", a: "public var authors:", b: "public var affiliations: TimelineOf<OrgRef> = .init()\n    public var authors:"),
        AGMEdit(path: "Sources/AkashicCore/Temporal.swift", kind: "replaceFirst", a: "public var affiliations: TimelineOf<OrgRef>", b: "public var affiliations: [String]"),
    ], expect: ["宣告型別變了"]),
    AGMCase(desc: "ratchet：邊欄位的宣告型別被改掉（名字沒動）", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: "Sources/AkashicCore/Temporal.swift", kind: "replaceFirst", a: "public var affiliations: TimelineOf<OrgRef>", b: "public var affiliations: [String]"),
    ], expect: ["宣告型別變了"]),
    AGMCase(desc: "ratchet：表裡某一列的欄位名被改掉（Swift 沒動）", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: ".claude/rules/entity-backlink-completeness.md", kind: "replaceFirst", a: "`Entry.venues`", b: "`Entry.venuez`"),
    ], expect: ["在六個型別檔裡找不到"]),
    AGMCase(desc: "ratchet：Swift 多一個 public let 欄位", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: "Sources/AkashicCore/Models.swift", kind: "replaceFirst", a: "public var authors:", b: "public let ghostEdge: String = \"\"\n    public var authors:"),
    ], expect: ["ghostEdge", "新欄位未經裁決"]),
    AGMCase(desc: "ratchet：Swift 多一個 [String] 欄位（上一版會漏）", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: "Sources/AkashicCore/Models.swift", kind: "replaceFirst", a: "public var authors:", b: "public var seeAlso: [String] = []\n    public var authors:"),
    ], expect: ["seeAlso", "新欄位未經裁決"]),
    AGMCase(desc: "parity：含空白的命令 token 退場了卻沒劃掉", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: ".claude/rules/mcp-cli-parity.md", kind: "replaceFirst", a: "| `export-tables --view`", b: "| `ghost-command --view`"),
    ], expect: ["已不在 CLI.swift"]),
    AGMCase(desc: "ratchet：Swift 多一個非純量欄位而沒被裁決", guardRel: "akashic-guards backlink-field-ratchet", edits: [
        AGMEdit(path: "Sources/AkashicCore/Models.swift", kind: "replaceFirst", a: "public var authors:", b: "public var brandNewEdge: [VenueRef] = []\n    public var authors:"),
    ], expect: ["brandNewEdge", "新欄位未經裁決"]),
]

let agmRobust: [AGMCase] = [
    // #711：自證閘的寫法差異不得改變判定——閘與被量的都寫成路徑形式的同一支 binary（兩處逐字相同）。
    // 注入不改任何指令的個數與行號，所以輸出與未注入逐字相同。（R1 另有一格「`&&` 不留空白」：R2 起模板逐字比對、
    // 運算子兩側要有空白，那一格不再是同一個判定，拿掉。）
    AGMCase(desc: "zi-rows：閘與被量的都寫成路徑形式的同一支 binary", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: "docs/zero-instance-measurements.md", kind: "replaceFirst",
                a: "\"$(command -v akashic)\" && \"$(command -v akashic)\" validate 2>&1 | grep -c '死 verdict'",
                b: ".build/debug/akashic && .build/debug/akashic validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["每一列裁決「寫」的都找得到實作"]),
    // #711 R4：辨識偏向「是量測」，但不是一切都是量測——已知不計數的顯示命令（`head`、不帶計數選項的 grep 家族）、名字不是 binary 的
    // （`che-akashic`）、沒有管線的 `${V:?…}`（簡單指令讓 shell 停下）、表格列裡的 `|`（欄的分隔，不是管線）都不改變任何事。
    // （R2／R3 這裡是「前一行是退場標記的 text fence 不掃」；R4 拿掉了退場標記，那一格改成須紅的「退場標記不再是出口」。）
    AGMCase(desc: "zi-rows：顯示命令、別的名字、沒有管線的 ${V:?…}、表格列的 | 不是量測", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate 2>&1 | head -1\n\"$(command -v akashic)\" doctor 2>&1 | grep -E '^orphaned'\n"
                    + "che-akashic validate 2>&1 | grep -c 'x'\npython3 - \"${STORE:?x}\" <<'PY'\nPY\n```\n\n"
                    + "| 欄 | Akashic 的表格 |\n|---|---|\n| a | Akashic validate 之後 | grep 以外 |\n\n## 各列共通的東西"),
    ], expect: ["每一列裁決「寫」的都找得到實作"]),
    // #711 R4（b33 X6 第 19 列）：顯示命令前面的環境設定、路徑、反斜線不改變它是顯示命令；名字以 grep 結尾、沒有計數選項的命令只挑行；
    // 散文裡 HTML 標記內的 `|` 不是管線（標記先去掉）。
    AGMCase(desc: "zi-rows：顯示命令的前綴與 HTML 標記裡的 | 不是計數", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "\n## 各列共通的東西",
                b: "\n```bash\n\"$(command -v akashic)\" validate 2>&1 | LC_ALL=C head -1\n\"$(command -v akashic)\" validate 2>&1 | /usr/bin/head -1\n"
                    + "\"$(command -v akashic)\" validate 2>&1 | \\head -1\n\"$(command -v akashic)\" doctor 2>&1 | zgrep -E '^orphaned'\n```\n\n"
                    + "執行 akashic validate 看 <a href=\"x|y\">連結</a>。\n\n## 各列共通的東西"),
    ], expect: ["每一列裁決「寫」的都找得到實作"]),

    // #526 的第一個坑：`ci.yml` 自己就有一段註解逐字寫著「原本是 python3 …」——掃全檔會把
    // 那個**刻意記下的已刪檔名**當成引用，於是修好的東西因為被寫進註解而重新變紅。
    AGMCase(desc: "workflow-run：run 區塊的 shell 註解提到已刪腳本（不得當成引用）", guardRel: "akashic-guards workflow-run-scripts", edits: [
        AGMEdit(path: ".github/workflows/census-parity.yml", kind: "replaceFirst",
                a: "        run: bash .githooks/run-guards.sh",
                b: "        run: |\n          # 舊版跑的是 bash tools/long-since-deleted-526.sh\n          bash .githooks/run-guards.sh"),
    ], expect: ["全部存在"]),
    // 直譯器從 stdin 讀（`cat x | bash`）沒有腳本檔可查——不得把 shell 運算子當成路徑。
    // 實測過的假紅：`bash --version && cat … | bash` 曾讓 `bash` 的下一個 token 是 `&&`。
    AGMCase(desc: "workflow-run：管線下游的裸直譯器與 shell 運算子不得被當成路徑", guardRel: "akashic-guards workflow-run-scripts", edits: [
        AGMEdit(path: ".github/workflows/census-parity.yml", kind: "replaceFirst",
                a: "        run: bash .githooks/run-guards.sh",
                b: "        run: bash .githooks/run-guards.sh && cat .githooks/run-guards.sh | bash"),
    ], expect: ["全部存在"]),
    AGMCase(desc: "numbers：宣稱與表之間有一行以 #407 開頭的散文（不得當成標題）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "| # | 情形 | 裁決 | 理由 |", b: "#407 R67l 的量測見下表。\n\n| # | 情形 | 裁決 | 理由 |"),
    ], expect: ["列數宣稱皆相符"]),
    AGMCase(desc: "numbers：標題與表之間夾一段 fence 包住的示範表（不得被當成真的表）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/blocked-issues-must-be-scannable.md", kind: "replaceFirst", a: "| # | 情形 | 裁決 | 理由 |", b: "```markdown\n| 示範 | 表 |\n|---|---|\n| a | b |\n```\n\n| # | 情形 | 裁決 | 理由 |"),
    ], expect: ["列數宣稱皆相符"]),
    AGMCase(desc: "numbers：一張無關的表緊接在受檢表之後（不得併入計數）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/blocked-issues-must-be-scannable.md", kind: "replaceFirst", a: "不用 `### Blocking`", b: "不用 `### Blocking`"),
        AGMEdit(path: ".claude/rules/blocked-issues-must-be-scannable.md", kind: "replaceFirst", a: "\n\n## 跟其他規則的關係", b: "\n| 另一張 | 表 |\n|---|---|\n| x | y |\n\n## 跟其他規則的關係"),
    ], expect: ["列數宣稱皆相符"]),
    AGMCase(desc: "在散文（非標題）加一句「只有 2 條」，其後有表（不得被誤判為不符）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "## 裁決史", b: "不得類推：本檔的封閉性只有 2 條依據。\n\n## 裁決史"),
    ], expect: ["列數宣稱皆相符"]),
    AGMCase(desc: "Swift 裡多一個不平衡的大括號字串字面（不得讓區段暴走）", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: "Sources/akashic/CreateEntryCommand.swift", kind: "replaceFirst", a: "struct CreateEntryCmd: ParsableCommand {", b: "struct CreateEntryCmd: ParsableCommand {\n    static let brace = \"{\""),
    ], expect: ["三面皆同步"]),
    AGMCase(desc: "把巢狀型別（enum Format）搬到 configuration 之前（純重排，不得被當成缺陷）", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: "Sources/akashic/CreateEntryCommand.swift", kind: "moveNestedStruct", a: "", b: ""),
    ], expect: ["三面皆同步"]),
]

/// 出貨檔監看清單——結束前比對 mtime，確認 harness 沒有動到版控中的檔案。
let agmWatched: [String] = [
    "plugin/rules/assertions-must-be-measured.md",
    ".github/workflows/census-parity.yml",
    // #629 新增的 psfp 各 case 改寫的來源（都只在 copy 裡被改，出貨檔不得被開啟以寫入）
    "plugin/.claude-plugin/plugin.json",
    "mcpb/manifest.json",
    ".claude-plugin/marketplace.json",
    "Sources/AkashicStoreIO/StoreVersion.swift",
    ".claude/rules/entity-backlink-completeness.md",
    ".claude/rules/mcp-cli-parity.md",
    "Sources/akashic-mcp/Server.swift",
    "Sources/AkashicCore/Models.swift",
    ".claude/rules/zero-instance-guards.md",
    "Sources/akashic/CreateEntryCommand.swift",
    // #711：量測文件與量測寫法的規則也被注入（只在 copy 裡）
    "docs/zero-instance-measurements.md",
    ".claude/rules/measurement-commands-self-prove.md",
]

/// 遷移期兩版並驗的守衛。刪掉 Python 版時這張表自然清空。
let agmMigrated: [(py: String, sub: String)] = [
    // **遷移完成後為空**（#433 Step 5）：沒有 Python 版可比對了。
]

/// 輸出**必須逐字相同**的 case 組——那個相同本身就是被斷言的性質。
let agmPairedIdentical: [[String]] = [
    ["parity：命令名只出現在某列的理由欄", "parity：某命令只在散文被提到、不在任何表列"],
]
