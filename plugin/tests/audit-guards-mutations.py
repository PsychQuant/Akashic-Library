#!/usr/bin/env python3
"""`rule-coverage.sh`、`hash-table-drift.sh`、`review-claim-audit.sh` 的 negative control。

**為什麼是這兩支**（#407 R32）：R31 直接讀四支既有 harness 的呼叫行，量到 9 支守衛
裡只有 4 支被人跑過並要求變紅。剩下五支每次都綠，而「沒紅過的檢查與不存在的檢查
無從區分」正是本 issue 的立場——那五支落在自己的立場之外。

本支覆蓋**五支**：`rule-coverage.sh`、`hash-table-drift.sh`、`review-claim-audit.sh`、
`measured-claims-audit.py`、`multiscalar-parity.swift`。加上既有的四支 harness，
**9 支守衛全部都有 negative control**（R31 量到的基準是 4/9）。

前一版把後兩支列為「要先給守衛一個參數」而延後——**兩個都不需要**（#407 R35）：

  `measured-claims-audit.py`  它的偵測式要 `git rev-list --all`，而 copy 裡沒有 `.git`。
                              解法不是改守衛，是在 copy 裡把 `.git` **symlink** 回真的
                              repo：守衛只讀歷史（rev-list／cat-file／log／show），
                              symlink 讓那些查詢照常成立，而檔案讀取仍落在 copy 上。
  `multiscalar-parity.swift`  單檔自足，複製該檔、改內建的 census 模型、`swift` 跑它即可。

**mutate 的是 pristine copy**，出貨檔以 mtime 前後比對確認未被開啟以寫入。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import shutil as _sh
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COVERAGE_REL = 'plugin/tests/rule-coverage.sh'
REVIEW_REL = 'plugin/tests/review-claim-audit.sh'
PARITY_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh'
GEN_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/derive-hash-extenders.swift'
WF_REL = '.github/workflows/census-parity.yml'
CLAIMS_REL = 'plugin/tests/measured-claims-audit.py'
NUMBERS_REL = 'plugin/tests/measured-numbers-audit.py'
PARITY_TABLE_REL = 'plugin/tests/parity-table-drift.py'
RATCHET_REL = 'plugin/tests/backlink-field-ratchet.py'
ZIROWS_REL = 'plugin/tests/zero-instance-rows-audit.py'
ZI_RULE_REL = '.claude/rules/zero-instance-guards.md'
CREATE_ENTRY_REL = 'Sources/akashic/CreateEntryCommand.swift'
MODELS_REL = 'Sources/AkashicCore/Models.swift'
MCP_RULE_REL = '.claude/rules/mcp-cli-parity.md'
SERVER_REL = 'Sources/akashic-mcp/Server.swift'
BACKLINK_REL = '.claude/rules/entity-backlink-completeness.md'
DRIFT_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh'
TABLE_REL = 'plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt'
MULTI_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/multiscalar-parity.swift'
RULE_REL = 'plugin/rules/assertions-must-be-measured.md'

WATCHED = [COVERAGE_REL, DRIFT_REL, TABLE_REL, MULTI_REL, RULE_REL,
           REVIEW_REL, PARITY_REL, GEN_REL, WF_REL, CLAIMS_REL,
           NUMBERS_REL, BACKLINK_REL, PARITY_TABLE_REL, MCP_RULE_REL, SERVER_REL,
           RATCHET_REL, MODELS_REL, ZIROWS_REL, ZI_RULE_REL, CREATE_ENTRY_REL]


def with_copy(guard_rel, edits):
    """複製相關子樹、套用 edits、跑 copy 裡的那支守衛。"""
    with tempfile.TemporaryDirectory(prefix='audit-mut-') as tmp:
        for sub in ('plugin', '.github', '.claude', 'Sources'):
            shutil.copytree(os.path.join(ROOT, sub), os.path.join(tmp, sub))
        for rel, fn in edits.items():
            p = os.path.join(tmp, rel)
            before = io.open(p, encoding='utf8').read()
            after = fn(before)
            if after == before:
                raise SystemExit(f'✗ 注入對 {rel} 沒有造成任何改動——這個 case 無效')
            io.open(p, 'w', encoding='utf8').write(after)
        # 守衛只讀 git **歷史**（rev-list／cat-file／log／show），所以把 `.git`
        # symlink 回真 repo 是安全的；沒有它，`measured-claims-audit.py` 會因為
        # 「這裡不是 repo」而紅——與注入無關的紅等於沒有負控（#407 R27）。
        os.symlink(os.path.join(ROOT, '.git'), os.path.join(tmp, '.git'))
        interp = {'py': sys.executable, 'sh': 'bash', 'swift': 'swift'}[
            guard_rel.rsplit('.', 1)[1]]
        r = subprocess.run([interp, os.path.join(tmp, guard_rel)],
                           capture_output=True, text=True, cwd=tmp)
        return r.returncode, r.stdout + r.stderr


CASES = [
    # ── rule-coverage.sh ──────────────────────────────────────────────────
    # 注意：改散文裡的**名字**不夠——守衛驗的是「解析得到的相對路徑 token」，
    # 不是字串出現過（那正是它自己註解裡記的 R6 findings 14／15／17）。所以
    # 這個 case 要把**連結**整個拿掉。
    # `rule-coverage.sh` 每個 skill 有**三個**失敗分支，訊息各不相同。斷言用各自的
    # 具體訊息、不用裸 `✗`——前一版兩個 case 都只斷言 `✗`，於是第二個**標成**
    # 「相對路徑解析不到」卻其實打中「引用不是這條規則本身」，而被 `.md.bak` 教訓
    # 硬化過的 `-f` 分支**一次都沒被行使**（#407 R39，跨模型審查指名）。
    ('coverage①：連結整個拿掉（沒有任何可解析的相對路徑）',
     COVERAGE_REL,
     {'plugin/skills/akashic-literal-campaign/SKILL.md':
      lambda t: t.replace('../../rules/assertions-must-be-measured.md', '見規則目錄')},
     ['沒有指向這條規則的可解析相對路徑']),
    ('coverage②：token 是別的檔名（引用不是這條規則本身）',
     COVERAGE_REL,
     {'plugin/skills/akashic-literal-campaign/SKILL.md':
      lambda t: t.replace('../../rules/assertions-must-be-measured.md',
                          '../../rules/assertions-must-be-measured-v2.md', 1)},
     ['的引用不是這條規則本身']),
    ('coverage③：basename 相同但目錄錯（`-f` 解析不到——`.md.bak` 教訓的那一格）',
     COVERAGE_REL,
     {'plugin/skills/akashic-literal-campaign/SKILL.md':
      lambda t: t.replace('../../rules/assertions-must-be-measured.md',
                          '../../rulez/assertions-must-be-measured.md', 1)},
     ['的相對路徑解析不到']),
    # ── hash-table-drift.sh ───────────────────────────────────────────────
    ('drift：生成的表被人手改了一段',
     DRIFT_REL,
     {TABLE_REL: lambda t: t.replace('\n', '\n', 1) and _perturb_table(t)},
     ['inline RANGES 與生成的表不一致']),
    ('drift：multiscalar 的 inline RANGES 與表脫節',
     DRIFT_REL,
     {MULTI_REL: lambda t: _perturb_ranges(t)},
     ['inline RANGES 與生成的表不一致']),
    # `hash-table-drift.sh` 的第三個分支：**表中不得出現 ASCII range**。它是那個
    # 讓 `multiscalar-parity.swift` 的 ASCII 快速路徑可證為冗餘的不變式，而先前
    # 一次都沒被行使（#407 R39）。
    ('drift：表中混進一個 ASCII range（快速路徑的不變式）',
     DRIFT_REL,
     # 表用**裸十六進位**（`0300 0300`），不是 `0x` 前綴——前一版寫 `0x0041` 於是
     # ASCII 檢查的 regex 不匹配，注入改而觸發後面的 RANGES 比對，看起來「有紅」
     # 卻紅在別的分支（#407 R39 的同一個形狀，在修它的那一輪又犯一次）。
     # regex 是「1–2 位十六進位 ＋ 空白」（`^[0-7]?[0-9a-f] `）。`0041` 是四位、
     # `0x0041` 有 `x`——兩個我都試過，兩次都改而觸發後面的 RANGES 比對：**看起來
     # 有紅、卻紅在別的分支**，正是本輪 finding 的形狀，在修它的那一輪連犯兩次。
     {TABLE_REL: lambda t: '41 41\n' + t},
     ['ASCII range']),
    # ── review-claim-audit.sh（#407 R34）──────────────────────────────────
    # 它重建的是四個歷史 finding 的失敗情境。每個 mutation 把其中一個修法**還原**，
    # 對應的 verdict 就該翻掉。R32 把這支列為「值得，不在本輪」——本輪補上。
    ('review：把 5000 前導零 fixture 改回會退化的長度',
     REVIEW_REL,
     {PARITY_REL: lambda t: t.replace("printf '%05000d'", "printf '%0500d'")},
     ['出貨的 parity 測試已改用新寫法且有長度斷言']),
    ('review：把生成表從 parity workflow 的 paths 拿掉',
     REVIEW_REL,
     {WF_REL: lambda t: t.replace('      - "plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt"\n', '')},
     ['生成表現在在 parity workflow 的 paths']),
    ('review：讓生成器真的去讀 CommandLine.arguments',
     REVIEW_REL,
     {GEN_REL: lambda t: t.replace('import Foundation',
                                   'import Foundation\nlet _ = CommandLine.arguments', 1)},
     ['確實從未讀 CommandLine.arguments']),
    ('review：把宣稱 --check 的那句註解加回去',
     REVIEW_REL,
     {GEN_REL: lambda t: t.replace('import Foundation',
                                   '// 用法：derive-hash-extenders.swift --check <生成的表>\nimport Foundation', 1)},
     ['宣稱 --check 的那句註解已移除']),
    # ── measured-claims-audit.py（#407 R35）───────────────────────────────
    ('claims：改壞偵測式（抽取式仍指向舊字面）',
     CLAIMS_REL,
     # **要打到程式碼那一份，不是註解那一份**：R26x 之後抽取式會先剝註解，
     # 所以改註解不會讓守衛紅——那是它**該有**的行為。用完整的偵測式字面定位。
     {CLAIMS_REL: lambda t: t.replace(
         '''| sed '/^$/q' | grep -q '^gpgsig' ''',
         '''| sed '/^$/q' | grep -q '^gpgSIG' ''', 1)},
     ['抽出 0 個 pattern']),
    # 白名單要打**真的會出現在 header 裡**的欄位。先前寫 `gpgsig-sha256`——本 repo
    # 的 commit 未簽署，那個欄位從不出現，於是拿掉它對輸出零影響、守衛正確地不紅
    # （#407 R35 當場量到）。`tree` 每個 commit 都有。
    ('claims：把白名單裡的 tree 拿掉（它每個 commit 都有）',
     CLAIMS_REL,
     {CLAIMS_REL: lambda t: t.replace("'tree': '內容指標'", "'tree-x': '內容指標'", 1)},
     ['tree']),
    # ── multiscalar-parity.swift（#407 R35）───────────────────────────────
    # **兩個試過但不成立的注入也記在這裡**，因為它們各自說明一件事：
    #   「移除 ASCII 快速路徑」→ 零分歧。**不是 fixture 沒涵蓋**：`hash-table-drift.sh`
    #     強制表中不得出現 ASCII range，所以那條路徑在該不變式下**可證為冗餘**。
    #   「案例表清空」→ 先前也是零分歧、rc=0（fixture 蒸發卻靜默通過）。那是真缺陷，
    #     已在守衛裡加案例數下限修掉；下面那個 case 就是它的負控。
    ('multi：模型把 inTable 的判定反過來',
     MULTI_REL,
     {MULTI_REL: lambda t: t.replace('return f < 0x80 ? true : !inTable(f)',
                                     'return f < 0x80 ? true : inTable(f)', 1)},
     ['★']),
    ('multi：模型改看最後一個 scalar',
     MULTI_REL,
     {MULTI_REL: lambda t: t.replace('guard let f = cps.first else { return true }',
                                     'guard let f = cps.last else { return true }', 1)},
     ['★']),
    # ── measured-numbers-audit.py（#407 R36）──────────────────────────────
    # 要挑**只靠行內錨**的那一個。先前挑 `entity-backlink` 的「（#339 立案當時）」，
    # 但同一小節裡還有 R33 加的 ⚠ 區塊帶著日期，小節層的錨照樣成立——注入不生效
    # （#407 R36 當場量到）。`literal-first-then-key.md:35` 的 `#303` 是該行唯一的錨。
    ('numbers：把某個數字唯一的行內時間錨拿掉',
     NUMBERS_REL,
     {'.claude/rules/literal-first-then-key.md':
      lambda t: t.replace('（#303 實測：2,123/3,720 邊，57.1%）',
                          '（實測：2,123/3,720 邊，57.1%）', 1)},
     ['沒有時間錨']),
    ('numbers：新增一個裸的 `實測 N`',
     NUMBERS_REL,
     {RULE_REL: lambda t: t.replace('## 誠實邊界',
                                    '## 補充\n\n實測 99 筆。\n\n## 誠實邊界', 1)},
     ['沒有時間錨']),
    ('numbers：規則目錄整個不見（不得靜默回綠）',
     NUMBERS_REL,
     {NUMBERS_REL: lambda t: t.replace("'.claude/rules/*.md'", "'.claude/rulez/*.md'", 1)
                              .replace("'plugin/rules/*.md'))", "'plugin/rulez/*.md'))", 1)},
     ['一個規則檔都沒找到']),
    # ── parity-table-drift.py（#407 R50）──────────────────────────────────
    ('parity：程式新增一個 MCP tool 而表沒補',
     PARITY_TABLE_REL,
     {SERVER_REL: lambda t: t.replace('Tool(name: "akashic_doctor"',
                                      'Tool(name: "akashic_brandnew"', 1)},
     ['在程式裡但**不在規則的 MCP 表**']),
    ('parity：表列了一個程式沒有的 tool',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| `akashic_doctor` |',
                                        '| `akashic_ghost` |', 1)},
     ['但程式裡**沒有這個 tool**']),
    # #407 R59：只在散文提到、不在任何表列裡 → 不算被裁決過。
    ('parity：某命令只在散文被提到、不在任何表列',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| `fmt` |', '| `fmt-x` |', 1)},
     ['規則檔裡完全沒提到']),
    ('parity：規則檔完全不提某個 CLI subcommand',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('`doctor`', '`doktor`')},
     ['規則檔裡完全沒提到']),
    ('parity：表把某命令標成退場但它仍註冊著（表→命令方向）',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| ~~`migrate-work-types`~~',
                                        '| ~~`doctor`~~', 1)},
     ['仍註冊在 CLI.swift']),
    ('parity：退場的列沒劃掉（孤兒列）',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| ~~`migrate-work-types`~~',
                                        '| `migrate-work-types`', 1)},
     ['已不在 CLI.swift']),
    # ── backlink-field-ratchet.py（#407 R51）──────────────────────────────
    # #407 R52：純量型別的新欄位**也**要被抓到（上一版的候選謂詞會漏掉
    # `public var seeAlso: [String]` 這種直接掛在頂層的 key 陣列）。
    # #407 R53：`public let` 也要抓（第 13 條邊的解析形式就是 let）。
    # ── zero-instance-rows-audit.py（#407 R55）───────────────────────────
    ('zi-rows：新增一列裁決「寫」而編號在 Sources 裡不存在',
     ZIROWS_REL,
     # 表的欄位分隔是「空白 ＋ 管線 ＋ 空白」；少一個空白就與 row regex 不合，
     # 注入會靜默不生效（#407 R55 當場踩到）。
     {ZI_RULE_REL: lambda t: t.replace('| 4 |', '| 5 | **假的一列**（#9999：不存在的守衛） | ✅ **寫** | 為了測負控 |\n| 4 |', 1)},
     ['在 Sources/ 裡都找不到']),
    ('zi-rows：某一列完全不引用 issue 編號',
     ZIROWS_REL,
     {ZI_RULE_REL: lambda t: t.replace('（#254：', '（無編號：', 1)},
     ['沒有引用任何 issue 編號']),
    # #407 R57：棘輪現在也讀那張表——列被改名／Swift 那側改名都要紅。
    # #407 R59：名字不變而**型別**改變——c49 列為 HIGH 的那一格。
    ('ratchet：邊欄位的宣告型別被改掉（名字沒動）',
     RATCHET_REL,
     {'Sources/AkashicCore/Temporal.swift':
      lambda t: t.replace('public var affiliations: TimelineOf<OrgRef>',
                          'public var affiliations: [String]', 1)},
     ['宣告型別變了']),
    ('ratchet：表裡某一列的欄位名被改掉（Swift 沒動）',
     RATCHET_REL,
     {BACKLINK_REL: lambda t: t.replace('`Entry.venues`', '`Entry.venuez`', 1)},
     ['在六個型別檔裡找不到']),
    ('ratchet：Swift 多一個 public let 欄位',
     RATCHET_REL,
     {MODELS_REL: lambda t: t.replace('public var authors:',
                                      'public let ghostEdge: String = ""\n    public var authors:', 1)},
     ['新欄位未經裁決']),
    ('ratchet：Swift 多一個 [String] 欄位（上一版會漏）',
     RATCHET_REL,
     {MODELS_REL: lambda t: t.replace('public var authors:',
                                      'public var seeAlso: [String] = []\n    public var authors:', 1)},
     ['新欄位未經裁決']),
    # #407 R52：`export-tables --view` 這種含空白的 token，上一版的 ②b 兩個分支都看不到。
    ('parity：含空白的命令 token 退場了卻沒劃掉',
     PARITY_TABLE_REL,
     # **要帶行首管線**：`export-tables --view` 的首次出現在第 44 行的散文裡，
     # 不是 CLI-only 表那一列——不帶管線的注入會打到散文，守衛保持綠是**正確的**
     # （#407 R52 當場踩到：注入打錯地方而我一度以為是守衛的洞）。
     {MCP_RULE_REL: lambda t: t.replace('| `export-tables --view`',
                                        '| `ghost-command --view`', 1)},
     ['已不在 CLI.swift']),
    ('ratchet：Swift 多一個非純量欄位而沒被裁決',
     RATCHET_REL,
     {MODELS_REL: lambda t: t.replace('public var authors:',
                                      'public var brandNewEdge: [VenueRef] = []\n    public var authors:', 1)},
     ['新欄位未經裁決']),
    ('multi：案例表被清空（fixture 蒸發不得靜默通過）',
     MULTI_REL,
     # `[] + [...]` **不會**清空（前一版寫成那樣，於是這個 case 一直在測別的東西，
     # 而我卻拿它當「vacuous pass 存在」的證據——#407 R35 當場抓到）。真的清空要
     # 讓 `cases` 綁到空陣列，原本的字面另外綁一個沒人用的名字。
     {MULTI_REL: lambda t: t.replace(
         'let cases: [(String, [UInt32])] = [',
         'let cases: [(String, [UInt32])] = []\nlet _unused: [(String, [UInt32])] = [', 1)},
     ['案例只剩']),
]


def _perturb_table(t):
    lines = t.split('\n')
    for i, l in enumerate(lines):
        if l.strip() and not l.lstrip().startswith('#'):
            lines[i] = l + '  '          # 尾隨空白改不了語意
            parts = l.split()
            if parts:
                lines[i] = l.replace(parts[0], parts[0][:-1] + 'F', 1)
            break
    return '\n'.join(lines)


def _perturb_ranges(t):
    i = t.find('0x')
    return t[:i] + '0xFFFE' + t[i + 6:] if i >= 0 else t


# **不是每個注入都該讓守衛變紅。** 下面這些注入的正確結果是**維持綠**——它們檢查的是
# 「守衛沒有把合法的重排當成缺陷」。R55 把大括號配對的驗證做成一次性 fixture 而沒有
# 常設化，本輪補上（#407 R56）。
def _move_nested_struct_up(src):
    """把 `CreateEntryCmd` 裡巢狀的 `EntryDraft` 搬到 `configuration` **之前**。

    這是一次**純重排**（Swift 語意不變）。上一版的抽取邊界（到下一個 `struct ` 宣告
    為止）在這個排列下會抽不到 `commandName` 而回 `None`——訊息會去怪稽核程序自己。
    大括號配對不受影響。
    """
    m = re.search(r'    struct EntryDraft \{.*?\n    \}\n', src, re.S)
    if not m:
        return src
    return src.replace(m.group(0), '').replace(
        'struct CreateEntryCmd: ParsableCommand {',
        'struct CreateEntryCmd: ParsableCommand {\n' + m.group(0), 1)


ROBUST = [
    # #407 R58：掃描器要跳過字串裡的大括號。注入一個**不平衡**的 `"{"` 字面——
    # 天真計數會讓區段暴走（實測 90,902 字元 vs 該檔 15,061），修好之後不受影響。
    ('Swift 裡多一個不平衡的大括號字串字面（不得讓區段暴走）',
     PARITY_TABLE_REL,
     {CREATE_ENTRY_REL: lambda t: t.replace(
         'struct CreateEntryCmd: ParsableCommand {',
         'struct CreateEntryCmd: ParsableCommand {\n    static let brace = "{"', 1)},
     ['三面皆同步']),
    ('把巢狀型別搬到 configuration 之前（純重排，不得被當成缺陷）',
     PARITY_TABLE_REL,
     {CREATE_ENTRY_REL: _move_nested_struct_up},
     ['三面皆同步']),
]


def main():
    before = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}

    has_swift = shutil.which('swift') is not None
    for rel in ([COVERAGE_REL] + ([DRIFT_REL] if has_swift else [])):
        r = subprocess.run(['bash', os.path.join(ROOT, rel)],
                           capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0:
            print(f'✗ baseline 就紅了：{rel}\n{r.stdout}{r.stderr}')
            return 1
    _n = 2 if has_swift else 1
    print(f'baseline：{_n} 支皆綠 ✓（{len(CASES)} 個 mutation 待跑）\n')

    # **缺 swift 時大聲跳過，不假裝乾淨**（#407 R42）：本 harness 有 6 個 case 需要真的
    # Swift toolchain（`multiscalar-parity.swift` 三個、`hash-table-drift.sh` 三個經由
    # 它的表生成器）。而 `plugin-guards.yml` 跑在 **ubuntu-latest**，stock image 沒有
    # Swift——那些 case 會以與注入無關的理由失敗。跳過它們，但把**跳了哪幾個、為什麼**
    # 印出來：`lossless-intake` 的「靜默是最糟的形式」。
    skipped = []
    if not has_swift:
        skipped = [n for n, g, _, _ in CASES
                   if g.endswith('.swift') or g == DRIFT_REL]
        print(f'⚠ 此環境沒有 swift——跳過 {len(skipped)} 個需要 Swift toolchain 的 case：')
        for n in skipped:
            print(f'    · {n}')
        print('  （其餘 case 照跑。「跳過」不等於「檢查過且乾淨」。）\n')

    ok = 0
    for name, guard, edits, must in CASES:
        if name in skipped:
            continue
        try:
            rc, out = with_copy(guard, edits)
        except SystemExit as e:
            print(e)
            continue
        miss = [m for m in must if m not in out]
        if rc != 0 and not miss:
            print(f'✓ 注入「{name}」→ rc={rc}，具名')
            ok += 1
        else:
            print(f'✗ 注入「{name}」→ rc={rc}' + (f'，缺 {miss}' if miss else ''))
            print('   ' + (out or '（無輸出）').replace('\n', '\n   ')[:500])

    for name, guard, edits, must in ROBUST:
        try:
            rc, out = with_copy(guard, edits)
        except SystemExit as e:
            print(e)
            continue
        miss = [m for m in must if m not in out]
        if rc == 0 and not miss:
            print(f'✓ 重排注入「{name}」→ 維持綠')
            ok += 1
        else:
            print(f'✗ 重排注入「{name}」→ rc={rc}' + (f'，缺 {miss}' if miss else ''))

    after = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}
    same = before == after
    expected = len(CASES) - len(skipped) + len(ROBUST)
    print(f'\n=== negative control {ok}/{expected} '
          f'（{len(CASES) - len(skipped)} 須紅 ＋ {len(ROBUST)} 須綠）==='
          + (f'（另有 {len(skipped)} 個因缺 swift 跳過）' if skipped else ''))
    print(f'{"出貨檔未被開啟以寫入" if same else "**出貨檔被動到了**"}：{len(WATCHED)} 個受監看檔')
    if ok != expected or not same:
        return 1
    # **跳過要進 exit code，不能只印在 stdout**（#407 R43，跨模型審查指名）：`expected`
    # 隨 `skipped` 一起縮，於是分子分母同縮、跳過對回傳值**不可見**。而 CI 步驟只看
    # 回傳值——那正是「未涵蓋不得冒充通過」（`zero-instance-guards` 第 3 列）。
    # **2 ＝ 跑得動的都綠，但有沒跑到的**，沿用 `hash-table-drift.sh` 既有的 exit 2 慣例。
    # 有 swift 的環境（pre-push、macOS CI）拿到 0；ubuntu 那一步顯式接受 2 並印出來。
    return 2 if skipped else 0


if __name__ == '__main__':
    sys.exit(main())
