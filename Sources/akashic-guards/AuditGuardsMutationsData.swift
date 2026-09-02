// **本檔由腳本生成，不要手改。** 來源：`plugin/tests/audit-guards-mutations.py`
// 生成腳本存在 #433 的 comment 裡，且它**自我驗證**：抽出的 edits 套用結果必須與原
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
    // **注入目標從 `MIGRATED` 表換成 runner**（#433 Step 5）：那張表在遷移完成後是空的，
    // 「拿掉一列」不再改變任何事。而 `migrated-guard-control` 真正的輸入是 `run-guards.sh`
    // ——注入一支沒有負控的守衛，它必須報出來。
    AGMCase(desc: "migrated：runner 多一支沒有負控的守衛", guardRel: "akashic-guards migrated-guard-control", edits: [
        AGMEdit(path: ".githooks/run-guards.sh", kind: "replaceFirst", a: ".build/debug/akashic-guards migrated-guard-control", b: ".build/debug/akashic-guards fake-guard\n.build/debug/akashic-guards migrated-guard-control"),
    ], expect: ["缺負控", "fake-guard"]),
    AGMCase(desc: "coverage①：連結整個拿掉（沒有任何可解析的相對路徑）", guardRel: "plugin/tests/rule-coverage.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceAll", a: "../../rules/assertions-must-be-measured.md", b: "見規則目錄"),
    ], expect: ["沒有指向這條規則的可解析相對路徑"]),
    AGMCase(desc: "coverage②：token 是別的檔名（引用不是這條規則本身）", guardRel: "plugin/tests/rule-coverage.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceFirst", a: "../../rules/assertions-must-be-measured.md", b: "../../rules/assertions-must-be-measured-v2.md"),
    ], expect: ["的引用不是這條規則本身"]),
    AGMCase(desc: "coverage③：basename 相同但目錄錯（`-f` 解析不到——`.md.bak` 教訓的那一格）", guardRel: "plugin/tests/rule-coverage.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/SKILL.md", kind: "replaceFirst", a: "../../rules/assertions-must-be-measured.md", b: "../../rulez/assertions-must-be-measured.md"),
    ], expect: ["的相對路徑解析不到"]),
    AGMCase(desc: "drift：生成的表被人手改了一段", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt", kind: "perturbTable", a: "", b: ""),
    ], expect: ["inline RANGES 與生成的表不一致"]),
    AGMCase(desc: "drift：multiscalar 的 inline RANGES 與表脫節", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", kind: "perturbRanges", a: "", b: ""),
    ], expect: ["inline RANGES 與生成的表不一致"]),
    AGMCase(desc: "drift：表中混進一個 ASCII range（快速路徑的不變式）", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt", kind: "prependAsciiRange", a: "", b: ""),
    ], expect: ["ASCII range"]),
    AGMCase(desc: "review：把 5000 前導零 fixture 改回會退化的長度", guardRel: "plugin/tests/review-claim-audit.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh", kind: "replaceAll", a: "printf '%05000d'", b: "printf '%0500d'"),
    ], expect: ["出貨的 parity 測試已改用新寫法且有長度斷言"]),
    AGMCase(desc: "review：把生成表從 parity workflow 的 paths 拿掉", guardRel: "plugin/tests/review-claim-audit.sh", edits: [
        AGMEdit(path: ".github/workflows/census-parity.yml", kind: "replaceAll", a: "      - \"plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt\"\n", b: ""),
    ], expect: ["生成表現在在 parity workflow 的 paths"]),
    AGMCase(desc: "review：讓生成器真的去讀 CommandLine.arguments", guardRel: "plugin/tests/review-claim-audit.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/derive-hash-extenders.swift", kind: "replaceFirst", a: "import Foundation", b: "import Foundation\nlet _ = CommandLine.arguments"),
    ], expect: ["確實從未讀 CommandLine.arguments"]),
    AGMCase(desc: "review：把宣稱 --check 的那句註解加回去", guardRel: "plugin/tests/review-claim-audit.sh", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/derive-hash-extenders.swift", kind: "replaceFirst", a: "import Foundation", b: "// 用法：derive-hash-extenders.swift --check <生成的表>\nimport Foundation"),
    ], expect: ["宣稱 --check 的那句註解已移除"]),
    AGMCase(desc: "multi：模型把 inTable 的判定反過來", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", kind: "replaceFirst", a: "return f < 0x80 ? true : !inTable(f)", b: "return f < 0x80 ? true : inTable(f)"),
    ], expect: ["分歧數：11"]),
    AGMCase(desc: "multi：模型改看最後一個 scalar", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", kind: "replaceFirst", a: "guard let f = cps.first else { return true }", b: "guard let f = cps.last else { return true }"),
    ], expect: ["分歧數：4"]),
    AGMCase(desc: "numbers：把某個數字唯一的行內時間錨拿掉", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules/literal-first-then-key.md", kind: "replaceFirst", a: "（#303 實測：2,123/3,720 邊，57.1%）", b: "（實測：2,123/3,720 邊，57.1%）"),
    ], expect: ["沒有時間錨"]),
    AGMCase(desc: "numbers：新增一個裸的 `實測 N`", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: "plugin/rules/assertions-must-be-measured.md", kind: "replaceFirst", a: "## 誠實邊界", b: "## 補充\n\n實測 99 筆。\n\n## 誠實邊界"),
    ], expect: ["沒有時間錨"]),
    AGMCase(desc: "numbers：規則目錄整個不見（不得被 CLAUDE.md 撐著回綠）", guardRel: "akashic-guards measured-numbers-audit", edits: [
        AGMEdit(path: ".claude/rules", kind: "delete", a: "", b: ""),
    ], expect: ["`.claude/rules/*.md` 一個檔都沒找到"]),
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
    AGMCase(desc: "scalar：`_scalar` 的最後一個分支被砍掉（切片可能被截斷）", guardRel: "akashic-guards literal-scalar-parity", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/literal-census.sh", kind: "replaceFirst", a: "        i = s.find(' #')\n        return (s[:i] if i >= 0 else s).strip()\n", b: "        pass\n"),
    ], expect: ["本體最後一行不是 `return`"]),
    AGMCase(desc: "zi-rows：新增一列裁決「寫」而編號在 Sources 裡不存在", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        // **插在表尾且編號接續**（#365，2026-08-28）。先前插在第 4 列前並用編號 `5`，
        // 於是列號序列變成 1,2,3,5,4,… ——而新加的列號連續檢查會先觸發並蓋掉本 case
        // 期望的訊息。錨點取表格後面那句散文（它不會隨列數成長）。
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "\n新增下一個零實例守衛 = 在這張表加一列。", b: "| 12 | **假的一列**（#9999：不存在的守衛） | ✅ **寫** | 為了測負控 |\n\n新增下一個零實例守衛 = 在這張表加一列。"),
    ], expect: ["在 Sources/ 裡都找不到"]),
    AGMCase(desc: "zi-rows：某一列完全不引用 issue 編號", guardRel: "akashic-guards zero-instance-rows-audit", edits: [
        AGMEdit(path: ".claude/rules/zero-instance-guards.md", kind: "replaceFirst", a: "（#254：", b: "（無編號："),
    ], expect: ["沒有引用任何 issue 編號"]),
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
    AGMCase(desc: "multi：案例表被清空（fixture 蒸發不得靜默通過）", guardRel: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift", kind: "replaceFirst", a: "let cases: [(String, [UInt32])] = [", b: "let cases: [(String, [UInt32])] = []\nlet _unused: [(String, [UInt32])] = ["),
    ], expect: ["案例只剩"]),
]

let agmRobust: [AGMCase] = [
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
    AGMCase(desc: "在 `_scalar` 裡插一行縮排不足的註解（不得截斷切片）", guardRel: "akashic-guards literal-scalar-parity", edits: [
        AGMEdit(path: "plugin/skills/akashic-promote-literals/scripts/literal-census.sh", kind: "replaceFirst", a: "        # 未加引號：", b: "# 範圍說明\n        # 未加引號："),
    ], expect: ["全部一致"]),
    AGMCase(desc: "把巢狀型別（enum Format）搬到 configuration 之前（純重排，不得被當成缺陷）", guardRel: "akashic-guards parity-table-drift", edits: [
        AGMEdit(path: "Sources/akashic/CreateEntryCommand.swift", kind: "moveNestedStruct", a: "", b: ""),
    ], expect: ["三面皆同步"]),
]

/// 出貨檔監看清單——結束前比對 mtime，確認 harness 沒有動到版控中的檔案。
let agmWatched: [String] = [
    "plugin/tests/rule-coverage.sh",
    "plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh",
    "plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt",
    "plugin/skills/akashic-promote-literals/scripts/tests/multiscalar-parity.swift",
    "plugin/rules/assertions-must-be-measured.md",
    "plugin/tests/review-claim-audit.sh",
    "plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh",
    "plugin/skills/akashic-promote-literals/scripts/tests/derive-hash-extenders.swift",
    ".github/workflows/census-parity.yml",
    "plugin/tests/measured-claims-audit.py",
    "plugin/tests/measured-numbers-audit.py",
    ".claude/rules/entity-backlink-completeness.md",
    "plugin/tests/parity-table-drift.py",
    ".claude/rules/mcp-cli-parity.md",
    "Sources/akashic-mcp/Server.swift",
    "plugin/tests/backlink-field-ratchet.py",
    "Sources/AkashicCore/Models.swift",
    "plugin/tests/zero-instance-rows-audit.py",
    ".claude/rules/zero-instance-guards.md",
    "Sources/akashic/CreateEntryCommand.swift",
    "plugin/tests/literal-scalar-parity.py",
    "plugin/skills/akashic-promote-literals/scripts/literal-census.sh",
]

/// 遷移期兩版並驗的守衛。刪掉 Python 版時這張表自然清空。
let agmMigrated: [(py: String, sub: String)] = [
    // **遷移完成後為空**（#433 Step 5）：沒有 Python 版可比對了。
]

/// 輸出**必須逐字相同**的 case 組——那個相同本身就是被斷言的性質。
let agmPairedIdentical: [[String]] = [
    ["parity：命令名只出現在某列的理由欄", "parity：某命令只在散文被提到、不在任何表列"],
]
