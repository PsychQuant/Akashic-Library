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
    ], expect: ["沒有任何 bullet 講它"]),
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
    // 每一條 `<akashic …> | grep -c …` 要有 `LC_ALL=C grep -a -q … &&` 的閘，或與 `正對照` 同在一個區塊。錨都在**量測段的文字**上
    // （第 13 列的第一條、第 28 列的閘、第 70／71 列的區塊），不碰列號，也不寫死閘的片段以外的任何數字。
    // **這一組與別組的輸出互不相同**（各自指名不同的行號與指令），所以不需要進 `PAIRED_IDENTICAL`。
    AGMCase(desc: "zi-rows：量測指令的自證閘被拿掉（舊 binary 會印 0）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '死 verdict' \"$(command -v akashic)\" && akashic validate 2>&1 | grep -c '死 verdict'",
                b: "akashic validate 2>&1 | grep -c '死 verdict'"),
    ], expect: ["沒有自證閘", "grep -c '死 verdict'"]),
    // 閘還在、`LC_ALL=C` 沒了：macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 比不到中文，閘會把新 binary 判成舊的。
    AGMCase(desc: "zi-rows：量測指令的閘沒有 LC_ALL=C", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '重複的判定記錄' \"$(command -v akashic)\"",
                b: "grep -a -q '重複的判定記錄' \"$(command -v akashic)\""),
    ], expect: ["沒有 `LC_ALL=C`", "重複的判定記錄"]),
    // 區塊：第 71 列的第一個區塊靠前面那行閘與 `正對照` 兩者；兩者都拿掉，後面三條都沒有自證。
    AGMCase(desc: "zi-rows：量測指令的區塊裡閘與正對照都被拿掉", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '抽取認不出' .build/debug/akashic-guards && LC_ALL=C grep -a -q '宣告是空的' .build/debug/akashic-guards && echo \"有這兩條檢查\"",
                b: "echo \"有這兩條檢查\""),
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "# 正對照，2026-09-30：18", b: "# 2026-09-30：18"),
    ], expect: ["沒有自證閘", "grep -c '抽取認不出'"]),
    // 第 70 列的區塊沒有閘，靠第一行的 `正對照` 讓後面那條 0 有對照；拿掉它，兩條都沒有。
    AGMCase(desc: "zi-rows：量測指令的正對照被拿掉（區塊裡沒有閘）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "# 正對照，2026-09-30：3（0＝這個 binary 沒有範圍檢查，或中途中止）", b: "# 2026-09-30：3（0＝這個 binary 沒有範圍檢查，或中途中止）"),
    ], expect: ["沒有自證閘", "grep -cE '^✓ .*宣告"]),
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
    // #711：區塊裡自證的兩種來源各自單獨成立——只剩閘（沒有 `正對照`）、或只剩 `正對照`（沒有閘），後面的計數都照樣有自證。
    // 繼承的寫法若只認其中一種，另一格會紅。注入不改任何指令的個數，所以輸出與未注入逐字相同。
    AGMCase(desc: "zi-rows：區塊裡只剩閘、沒有正對照（閘要能讓後面的計數繼承）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "# 正對照，2026-09-30：18", b: "# 2026-09-30：18"),
    ], expect: ["每一列裁決「寫」的都找得到實作"]),
    AGMCase(desc: "zi-rows：區塊裡只剩正對照、沒有閘（正對照要能讓後面的計數繼承）", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst",
                a: "LC_ALL=C grep -a -q '抽取認不出' .build/debug/akashic-guards && LC_ALL=C grep -a -q '宣告是空的' .build/debug/akashic-guards && echo \"有這兩條檢查\"",
                b: "echo \"有這兩條檢查\""),
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
]

/// 遷移期兩版並驗的守衛。刪掉 Python 版時這張表自然清空。
let agmMigrated: [(py: String, sub: String)] = [
    // **遷移完成後為空**（#433 Step 5）：沒有 Python 版可比對了。
]

/// 輸出**必須逐字相同**的 case 組——那個相同本身就是被斷言的性質。
let agmPairedIdentical: [[String]] = [
    ["parity：命令名只出現在某列的理由欄", "parity：某命令只在散文被提到、不在任何表列"],
]
