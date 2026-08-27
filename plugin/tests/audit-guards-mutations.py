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
import collections
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


def _zi_verdict_heading(new):
    """把 zero-instance-guards 的裁決史標題整行換成 `new`——**不寫死列數**。

    #414：先前三個 case 各自寫死 `'## 裁決史（封閉列舉——現有 6 列，一列不多一列不少）'`
    當字面錨。那個數字**是規則檔那個數字的第二份副本**，於是規則檔加一列（6 → 7）時
    三個 case 同時失效——而它們失效的方式是「注入沒有造成任何改動」，也就是這個 harness
    自己的 fail-loud 檢查抓到的（#407 R67 起就有那道檢查，這次是它第一次抓到真的漂移）。

    寫死數字是本 issue 反覆記過的形狀，出現在**檢查那個形狀的工具自己身上**。用 regex
    綁「標題的結構」而非「標題此刻的內容」：列數怎麼變都命中，而標題若被改成別的形狀
    （不再宣稱列數），regex 不命中 → 同一道 fail-loud 照樣出聲。
    """
    pat = re.compile(r'^## 裁決史（封閉列舉——現有 \S+ 列，一列不多一列不少）$', re.M)
    def sub(text):
        return pat.sub(lambda _: new, text, count=1)
    return sub
CREATE_ENTRY_REL = 'Sources/akashic/CreateEntryCommand.swift'
SCALAR_GUARD_REL = 'plugin/tests/literal-scalar-parity.py'

# ── 遷移期：runner 跑的是 Swift 版，所以負控必須驗**它**（#433）──────────────
#
# `run-guards.sh` 換成 `.build/debug/akashic-guards X` 之後，這支 harness 若仍只跑
# `plugin/tests/X.py`，它驗的就是一個**不再被執行的實作**——負控全綠，而實際在跑的
# 那一版會不會紅，沒有任何東西在保證。這是本 repo 反覆記過的形狀（一份規格與現實
# 安靜分岔），而這一次是**遷移自己製造的**：兩邊都綠，缺口在它們中間。
#
# **兩版都跑並要求逐字一致**，不是二選一。理由是兩者在遷移期各有不可取代的角色：
# Python 版是 oracle（Swift 版的正確性正是由「與它輸出相同」建立的），Swift 版是
# 實際在跑的。要求一致同時保住兩者，並把「遷移期兩版不得分岔」從一次性的手動比對
# 變成**每個 mutation 都跑**的斷言——比我手動比對過的那 19 格涵蓋更廣。
#
# Step 4 刪掉 Python 版時這張表自然清空，harness 退化成只跑 Swift。
MIGRATED = {
    CLAIMS_REL: 'measured-claims-audit',
    SCALAR_GUARD_REL: 'literal-scalar-parity',
    NUMBERS_REL: 'measured-numbers-audit',
    PARITY_TABLE_REL: 'parity-table-drift',
    RATCHET_REL: 'backlink-field-ratchet',
    ZIROWS_REL: 'zero-instance-rows-audit',
}
GUARDS_BIN = os.path.join(ROOT, '.build/debug/akashic-guards')
# 注入**守衛自己原始碼**的 case：Swift 側結構上測不到，見 `with_copy` 裡的說明。
# 收集起來在 main() 尾端彙總印出——靜默跳過會讓「Swift 側沒有負控」這件事消失。
SOURCE_INJECTED = []
CENSUS_REL = 'plugin/skills/akashic-literal-campaign/scripts/literal-census.sh'
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
           RATCHET_REL, MODELS_REL, ZIROWS_REL, ZI_RULE_REL, CREATE_ENTRY_REL,
           SCALAR_GUARD_REL, CENSUS_REL]


def with_copy(guard_rel, edits):
    """複製相關子樹、套用 edits、跑 copy 裡的那支守衛。"""
    with tempfile.TemporaryDirectory(prefix='audit-mut-') as tmp:
        for sub in ('plugin', '.github', 'Sources'):
            shutil.copytree(os.path.join(ROOT, sub), os.path.join(tmp, sub))
        # **`.claude` 只複製 `rules/`。** 整個 `.claude` 是 **2.0 GB／25,519 個檔**——
        # 其中 `.claude/worktrees/` 佔 2.0 GB（IDD 的隔離工作樹，見 `git worktree list`），
        # 而守衛讀的只有 `.claude/rules/`（144 KB；private repo，外部讀者取不到）。全樹複製
        # 要 **16.5 秒一次**，
        # 乘上 `tested` 的每支 baseline ＋ 每個 mutation case，讓這支 harness 從
        # 30.6 秒漲到 **13 分鐘以上**，`oracle-precondition-control.py`（它 import 本模組
        # 並多次呼叫 `with_copy`）漲到 **5 分 44 秒**。
        #
        # **這是安靜的**：兩支都照樣全綠，只是慢——而 CLAUDE.md 已經記過「四分鐘的
        # pre-push 在頻繁 push 時會被 `--no-verify` 繞過，那時**所有**守衛等於不存在」。
        # 一個因為別處長出 2 GB 而變慢十倍的 harness，走的正是那條路。
        #
        # 全部守衛（含 `plugin/skills/*/scripts/tests/`）引用的 `.claude` 路徑實測**只有**
        # `.claude/rules/`（private repo，外部讀者取不到）；`.claude/rulez` 與
        # `.claude/rules/x.md`（同樣取不到）是負控刻意用的**不存在**路徑——
        # 不需要複製任何東西就能扮演它們的角色。
        os.makedirs(os.path.join(tmp, '.claude'))
        shutil.copytree(os.path.join(ROOT, '.claude', 'rules'),
                        os.path.join(tmp, '.claude', 'rules'))
        # **CLAUDE.md 是檔案不是目錄**，所以它不在上面那個迴圈裡（#407 R67g）。
        # `measured-numbers-audit.py` 自 R67g 起也掃它，而少了這一行，針對它的注入
        # 會以 `FileNotFoundError` 失敗——那是與注入無關的紅，等於沒有負控。
        shutil.copy2(os.path.join(ROOT, 'CLAUDE.md'), os.path.join(tmp, 'CLAUDE.md'))
        for rel, fn in edits.items():
            p = os.path.join(tmp, rel)
            # **`None` ＝ 把它整個搬走**（#433）。用來測「輸入來源歸零」這一類性質，
            # 而不是改守衛**自己的原始碼**去指向一個錯的路徑。
            #
            # 差別在遷移之後才顯現：注入原始碼只對直譯語言有效——Swift 版的等價字串在
            # compiled binary 裡，改 `.py` 對它**結構上**無效，於是那種 case 在兩版比對
            # 下永遠報分岔，而分岔的原因與守衛的正確性無關。改成搬走目錄之後，測的仍是
            # 同一個性質（守衛會不會發現輸入源沒了），但**語言中立**——而那個性質正是
            # 守衛訊息自己寫的那句「路徑錯了還是**被搬走了**？」。
            if fn is None:
                if not os.path.exists(p):
                    raise SystemExit(f'✗ 注入要搬走 {rel} 但它不存在——這個 case 無效')
                shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
                continue
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
        sub = MIGRATED.get(guard_rel)
        # **注入守衛自己的原始碼時不做兩版比對。** Swift 版的等價程式碼在 compiled
        # binary 裡，改 `.py` 對它**結構上**無效——比對必然分岔，而分岔與守衛的正確性
        # 無關。這類注入測的是 harness **自己**的機制（`oracle-precondition-control.py`
        # 毒化守衛以驗證 ROBUST oracle 的降級行為），不是守衛在測的那個性質。
        #
        # 判準是結構的（`edits` 動到 `guard_rel` 自己），不是一張名單——名單會與 CASES
        # 分岔，而這個性質從 edits 就讀得出來。
        #
        # 代價要說出來：這些 case 的 **Swift 側沒有負控**。能改成環境注入的就該改
        # （本輪把 `.claude/rules` 與 `CLAUDE.md` 那兩個改掉了，它們測的「輸入源歸零」
        # 本來就與語言無關）；真正在測 harness 機制的那些改不掉，只能記著。
        if sub and guard_rel in edits:
            SOURCE_INJECTED.append(guard_rel)
            sub = None
        if sub and os.path.exists(GUARDS_BIN):
            # Swift 版以 **cwd** 定位 repo，所以 binary 留在 ROOT、cwd=tmp 即讀到注入後
            # 的副本（Python 版靠 `__file__`，而它自己也被複製進 tmp 了）。
            rs = subprocess.run([GUARDS_BIN, sub],
                                capture_output=True, text=True, cwd=tmp)
            if (rs.returncode, rs.stdout + rs.stderr) != (r.returncode, r.stdout + r.stderr):
                raise SystemExit(
                    f'✗ 遷移期兩版分岔：{guard_rel} vs `akashic-guards {sub}`\n'
                    f'  ── python rc={r.returncode}\n{r.stdout}{r.stderr}\n'
                    f'  ── swift  rc={rs.returncode}\n{rs.stdout}{rs.stderr}')
            return rs.returncode, rs.stdout + rs.stderr   # 回傳**實際在跑的**那一版
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
     # **斷言具體的分歧數，不是裸的 `★`**（#407 R67，跨模型審查指名）：`★` 是
     # 任何一列不符都會印的通用標記，兩個 multi case 先前**斷言完全相同**——
     # 把它們對調也不會被發現，而一個與注入無關的破壞（改某列的 expected、
     # RANGES 差一格）同樣會印 `★` 而被記成「抓到了」。實測兩者分歧數不同：
     # inTable 反轉 11 列、改看最後一個 scalar 4 列。
     ['分歧數：11']),
    ('multi：模型改看最後一個 scalar',
     MULTI_REL,
     {MULTI_REL: lambda t: t.replace('guard let f = cps.first else { return true }',
                                     'guard let f = cps.last else { return true }', 1)},
     ['分歧數：4']),
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
    ('numbers：規則目錄整個不見（不得被 CLAUDE.md 撐著回綠）',
     NUMBERS_REL,
     # 只打壞 `.claude/rules`——聯集版會被另外兩個來源撐住而靜默回綠，逐來源版
     # 必須具名是**哪一個**歸零（#407 R67g）。
     {'.claude/rules': None},
     ['`.claude/rules/*.md` 一個檔都沒找到']),
    ('numbers：CLAUDE.md 不見（同樣不得被另外兩個來源撐著）',
     NUMBERS_REL,
     {'CLAUDE.md': None},
     ['`CLAUDE.md` 一個檔都沒找到']),
    # #413：`borrowed` 分桶先前只看 `c[4]`，安全性靠一個**跨函式**的不變量——
    # `declared_counts` 在數字解析失敗時 append `(…, None, None)` 並立刻 `continue`，
    # 所以 `_rows_after` 根本不會被呼叫。這個 mutation 拿掉那個 `continue`（改成
    # 無論解析成功與否都算 rows），把不變量從「隱含」變成「被測」：
    #
    #   加了 `c[3] is not None` 之後 → 那筆的 c[3] 是 None → **不進 borrowed**，
    #   照樣落在 `unparsed`，訊息仍是「解析不出來」。守衛維持綠。
    #   拿掉那個守衛 → 同一筆同時進 borrowed，印出「標題說『廿』而它自己沒有表」，
    #   而「廿」是一個解析失敗的裸數字——語意錯位、零錯誤訊息。
    ('numbers：解析失敗的宣稱仍算 rows（不變量：它必須留在 unparsed，不得變 borrowed）',
     NUMBERS_REL,
     # 這是上一個 case 的注入**再加**「讓 `declared_counts` 對解析失敗也算 rows」。
     # `borrowed` 加了 `c[3] is not None` 之後，那個加法**不得改變任何事**——那筆的
     # `c[3]` 是 None，照樣只落在 `unparsed`。拿掉守衛則它同時進 `borrowed`，兩者
     # 的輸出立刻分岔（配對不變式即在測這件事）。
     {NUMBERS_REL: lambda t: t.replace(
         "                    out.append((os.path.relpath(fp, root), i + 1, m.group(0), None, None))\n"
         "                    continue\n",
         "                    out.append((os.path.relpath(fp, root), i + 1, m.group(0), None,\n"
         "                                _rows_after(lines, i)))\n"
         "                    continue\n", 1),
      '.claude/rules/zero-instance-guards.md':
      _zi_verdict_heading('## 前言（封閉列舉——現有 廿 列）\n\n散文一句。\n\n'
                          '## 裁決史（一列不多一列不少）')},
     ['解析不出來']),
    # #407 R67i：中文數字用算的（不是查表）、表不得跨標題借用、解析不出要報。
    ('numbers：標題用「十五」而表沒有十五列（查表版會靜默略過）',
     NUMBERS_REL,
     {'.claude/rules/blocked-issues-must-be-scannable.md':
      lambda t: t.replace('（哪些「等」需要標記——封閉列舉，現有 4 列）',
                          '（哪些「等」需要標記——封閉列舉，現有十五列）', 1)},
     ['現有十五列', '而下方的表有 4 列']),
    ('numbers：標題宣稱列數、自己沒有表，而下一節有（不得借用）',
     NUMBERS_REL,
     {'.claude/rules/zero-instance-guards.md':
      _zi_verdict_heading('## 前言（封閉列舉——現有 6 列）\n\n散文一句。\n\n'
                          '## 裁決史（一列不多一列不少）')},
     # R67l 起訊息具名跨過的標題，不再是一句「下一個標題之後」。
     ['最近的表在「## 裁決史（一列不多一列不少）」之後']),
    ('numbers：標題的數字解析不出來（不得靜默略過）',
     NUMBERS_REL,
     # `廿` 在 `_COUNT` 的字元類裡但 `_num` 不處理——這正是「匹配得到卻解析不出」
     # 那條路徑唯一走得到的形狀。字元類刻意比 `_num` 寬就是為了讓它可達。
     #
     # **標題刻意做成「自己沒有表」**（把表推到下一節）：這樣 `_rows_after` 才會回
     # `('borrowed', …)` 而不是 int——`borrowed` 分桶只收 tuple，用 int 的話那個
     # 守衛在不在都沒差，配對的不變式就會是**空的**（#413 第一版正是這樣，回退守衛
     # 仍綠才發現）。
     {'.claude/rules/zero-instance-guards.md':
      _zi_verdict_heading('## 前言（封閉列舉——現有 廿 列）\n\n散文一句。\n\n'
                          '## 裁決史（一列不多一列不少）')},
     ['解析不出來']),
    # #407 R67l：跨 >=2 個標題時，診斷要具名跨過哪些（不是一句「下一個標題」）。
    ('numbers：宣稱與表之間隔了兩個標題（診斷要說「隔了 2 個」並具名）',
     NUMBERS_REL,
     {'.claude/rules/zero-instance-guards.md':
      lambda t: t.replace(
          '| # | 情形 | 裁決 | 理由 |',
          '## 插入的空節甲\n\n## 插入的空節乙\n\n| # | 情形 | 裁決 | 理由 |', 1)},
     ['隔了 2 個標題', '插入的空節甲', '插入的空節乙']),
    # #407 R67g：CLAUDE.md 也在掃描範圍內。它是每個 session 自動注入的檔案，
    # 一個過期數字在那裡的影響面比任何規則檔都大。
    ('numbers：CLAUDE.md 裡出現一個裸的 `實測 N`',
     NUMBERS_REL,
     {'CLAUDE.md': lambda t: t.replace('## Rules', '## 補充\n\n實測 77 支。\n\n## Rules', 1)},
     ['沒有時間錨', 'CLAUDE.md']),
    # #407 R67d：標題宣稱的列數 vs 表的實際列數。三個方向——漂移、錨不存在、
    # 以及**不得誤傷散文**（收窄前件的那一格；它是須綠的，放在 ROBUST 裡）。
    ('numbers：表多一列而標題的計數沒跟上',
     NUMBERS_REL,
     {'.claude/rules/blocked-issues-must-be-scannable.md':
      lambda t: t.replace(
          '| 4 | 等時間累積',
          '| 3.5 | 等一個外部帳務事件 | ✅ **`### Blocking`** | 佔位 |\n| 4 | 等時間累積', 1)},
     ['現有 4 列', '而下方的表有 5 列']),
    ('numbers：標題宣稱了列數卻沒有表（錨不存在）',
     NUMBERS_REL,
     # **移除全檔的表分隔線**，而不是只拿掉裁決史那一張（#414 R1）。
     # 先前只拿掉一張，於是 40 行的前向掃描會找到**別節**的表，這個 case 因此改走
     # `borrowed` 分支——它從「錨不存在」悄悄變成「錨在別節」，兩條路都有 case，
     # 所以測試套件的計數沒變、覆蓋卻少了一格。觸發它的是同一份規則檔多長出一張表。
     #
     # 表由分隔線認得（`_rows_after` 的 `^\|[-\s|:]+\|$`），所以把分隔線全部拿掉
     # ＝ 全檔沒有任何表，`borrowed` 分支結構上到不了。
     {'.claude/rules/zero-instance-guards.md':
      lambda t: re.sub(r'^\|[-\s|:]+\|\s*$', '（表分隔線已移除）', t, flags=re.M)},
     ['找不到表——錨不存在']),
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
    # #407 R60：把命令名種在既有列的**理由欄**（第 3 格）不算被裁決過。
    ('parity：命令名只出現在某列的理由欄',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| `fmt` | 有理由缺席', '| `fmt-x` | 有理由缺席')
                              .replace('全庫改寫＝維運例外', '全庫改寫＝維運例外（同 `fmt`）')},
     # **這一格的可區分性不在字串裡**（#407 R67b，自己量出來的）：本 case 的注入
     # 是下一個 case 的注入**再加**「把 `fmt` 種進理由欄」，而它的主張正是那個
     # 加法**不得改變任何事**——所以兩者的輸出逐字相同，任何字串斷言都分不開它們。
     # 可區分的斷言是下方 `main()` 裡的不變式：out(理由欄版) == out(純散文版)。
     ['`fmt`', '規則檔裡完全沒提到']),
    # #407 R59：只在散文提到、不在任何表列裡 → 不算被裁決過。
    ('parity：某命令只在散文被提到、不在任何表列',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('| `fmt` |', '| `fmt-x` |', 1)},
     ['`fmt`', '規則檔裡完全沒提到']),
    ('parity：規則檔完全不提某個 CLI subcommand',
     PARITY_TABLE_REL,
     {MCP_RULE_REL: lambda t: t.replace('`doctor`', '`doktor`')},
     ['`doctor`', '規則檔裡完全沒提到']),
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
    # ── literal-scalar-parity.py（#407 R65）──────────────────────────────
    # R64 把「結構完整檢查會紅」記為**沒有被反向證實**（當時的診斷腳本自己壞了）。
    # 常設化：砍掉 `_scalar` 的最後一個分支，本體就不以 `return` 結尾。
    ('scalar：`_scalar` 的最後一個分支被砍掉（切片可能被截斷）',
     SCALAR_GUARD_REL,
     {CENSUS_REL: lambda t: t.replace(
         "        i = s.find(' #')\n        return (s[:i] if i >= 0 else s).strip()\n",
         "        pass\n", 1)},
     ['本體最後一行不是 `return`']),
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
    # #407 R60：同名誘餌不得遮住真正的型別變更（限定名鍵）。
    ('ratchet：同名誘餌 ＋ 真欄位改型別（裸名鍵會被騙過）',
     RATCHET_REL,
     {'Sources/AkashicCore/Models.swift':
      lambda t: t.replace('public var authors:',
                          'public var affiliations: TimelineOf<OrgRef> = .init()\n    public var authors:', 1),
      'Sources/AkashicCore/Temporal.swift':
      lambda t: t.replace('public var affiliations: TimelineOf<OrgRef>',
                          'public var affiliations: [String]', 1)},
     ['宣告型別變了']),
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
     ['ghostEdge', '新欄位未經裁決']),
    ('ratchet：Swift 多一個 [String] 欄位（上一版會漏）',
     RATCHET_REL,
     {MODELS_REL: lambda t: t.replace('public var authors:',
                                      'public var seeAlso: [String] = []\n    public var authors:', 1)},
     ['seeAlso', '新欄位未經裁決']),
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
     ['brandNewEdge', '新欄位未經裁決']),
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
    # #407 R67l：行首的 #NNN issue 編號**不是**標題（CommonMark 要求 # 後接空白）。
    # 修之前這一格會紅——那張表本來就屬於當前標題，卻被判成 borrowed。
    ('numbers：宣稱與表之間有一行以 #407 開頭的散文（不得當成標題）',
     NUMBERS_REL,
     {'.claude/rules/zero-instance-guards.md':
      lambda t: t.replace(
          '| # | 情形 | 裁決 | 理由 |',
          '#407 R67l 的量測見下表。\n\n| # | 情形 | 裁決 | 理由 |', 1)},
     ['列數宣稱皆相符']),
    # #407 R67j（跨模型審查指名的兩個子點，修完後**須綠**）：修之前兩者都會紅
    # ——fence 內那張 1 列的示範表會被當成真的表；緊鄰的第二張表的表頭與分隔線會被
    # 算成第一張的資料列。所以它們是這兩個修正的回歸守衛，不是新缺陷的偵測器。
    ('numbers：標題與表之間夾一段 fence 包住的示範表（不得被當成真的表）',
     NUMBERS_REL,
     {'.claude/rules/blocked-issues-must-be-scannable.md':
      # 插在**裁決表的標題與它自己的表之間**——那才是「現有 4 列」綁的那張表。
      # 前一版插在檔案較早的另一張表前面，對受檢宣稱完全沒有影響（實測：回退修正
      # 後那一格仍綠 ⇒ 空的 case）。位置錯了，控制組就什麼都沒測到。
      lambda t: t.replace('| # | 情形 | 裁決 | 理由 |',
                          '```markdown\n| 示範 | 表 |\n|---|---|\n| a | b |\n```\n\n'
                          '| # | 情形 | 裁決 | 理由 |', 1)},
     ['列數宣稱皆相符']),
    ('numbers：一張無關的表緊接在受檢表之後（不得併入計數）',
     NUMBERS_REL,
     {'.claude/rules/blocked-issues-must-be-scannable.md':
      # 緊接在裁決表**最後一列之後、中間沒有空行**——有空行的話 while 迴圈本來就停了，
      # 測不到「表頭與分隔線被算成資料列」那條路徑。
      lambda t: t.replace(
          '不用 `### Blocking`',
          '不用 `### Blocking`', 1).replace(
          '\n\n## 跟其他規則的關係',
          '\n| 另一張 | 表 |\n|---|---|\n| x | y |\n\n## 跟其他規則的關係', 1)},
     ['列數宣稱皆相符']),
    # #407 R67d：收窄前件的那一格要有守衛。散文裡的「只有一條」與 10 行外的一張
    # 10 列的表**不是**不符——寬版謂詞當初正是這樣誤傷 `mcp-cli-parity.md` 的。
    ('在散文（非標題）加一句「只有 2 條」，其後有表（不得被誤判為不符）',
     NUMBERS_REL,
     {'.claude/rules/zero-instance-guards.md':
      lambda t: t.replace('## 裁決史', '不得類推：本檔的封閉性只有 2 條依據。\n\n## 裁決史', 1)},
     ['列數宣稱皆相符']),
    # #407 R58：掃描器要跳過字串裡的大括號。注入一個**不平衡**的 `"{"` 字面——
    # 天真計數會讓區段暴走（實測 90,902 字元 vs 該檔 15,061），修好之後不受影響。
    ('Swift 裡多一個不平衡的大括號字串字面（不得讓區段暴走）',
     PARITY_TABLE_REL,
     {CREATE_ENTRY_REL: lambda t: t.replace(
         'struct CreateEntryCmd: ParsableCommand {',
         'struct CreateEntryCmd: ParsableCommand {\n    static let brace = "{"', 1)},
     ['三面皆同步']),
    # #407 R65：縮排不足的註解**不得**終止切片（維護者加範圍說明時很自然會左對齊）。
    ('在 `_scalar` 裡插一行縮排不足的註解（不得截斷切片）',
     SCALAR_GUARD_REL,
     {CENSUS_REL: lambda t: t.replace('        # 未加引號：',
                                      '# 範圍說明\n        # 未加引號：', 1)},
     ['全部一致']),
    ('把巢狀型別搬到 configuration 之前（純重排，不得被當成缺陷）',
     PARITY_TABLE_REL,
     {CREATE_ENTRY_REL: _move_nested_struct_up},
     ['三面皆同步']),
]


# 這兩個 case 的輸出**必須逐字相同**（見 main() 的不變式檢查）。名字寫在這裡而不是
# 用索引，是因為索引會在 CASES 增刪時安靜錯位。
PAIRED_IDENTICAL = (
    # 每一組的輸出**必須逐字相同**，而那個相同本身就是被斷言的性質。
    # 用名字而非索引：索引會在 CASES 增刪時安靜錯位。
    ('parity：命令名只出現在某列的理由欄',
     'parity：某命令只在散文被提到、不在任何表列'),
    # #413：後者是前者的注入**再加**「讓 `declared_counts` 對解析失敗仍呼叫
    # `_rows_after`」。`borrowed` 分桶加了 `c[3] is not None` 之後，那個加法
    # **不得改變任何事**——那筆的 `c[3]` 是 None，照樣只落在 `unparsed`。
    # 拿掉守衛則它同時進 `borrowed`，兩者的輸出立刻分岔。
    ('numbers：標題的數字解析不出來（不得靜默略過）',
     'numbers：解析失敗的宣稱仍算 rows（不變量：它必須留在 unparsed，不得變 borrowed）'),
)
_PAIRED_FLAT = {n for pair in PAIRED_IDENTICAL for n in pair}


def main():
    paired = {}
    by_output = collections.defaultdict(list)
    before = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}

    has_swift = shutil.which('swift') is not None
    # **binary 缺席要說出來，不得靜默退回只驗 Python**（`lossless-intake` 執行細節 3）：
    # 那會讓 `MIGRATED` 的四支在這台機器上失去負控，而輸出與「驗過了」完全一樣。
    if not os.path.exists(GUARDS_BIN):
        print(f'ℹ {GUARDS_BIN} 不存在——`MIGRATED` 的 {len(MIGRATED)} 支只驗 Python 版，'
              f'實際在 run-guards.sh 跑的 Swift 版**在這台機器上沒有負控**。'
              f'先跑 `swift build --product akashic-guards`。')
    for rel in ([COVERAGE_REL] + ([DRIFT_REL] if has_swift else [])):
        r = subprocess.run(['bash', os.path.join(ROOT, rel)],
                           capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0:
            print(f'✗ baseline 就紅了：{rel}\n{r.stdout}{r.stderr}')
            return 1
    # **每一支被當成受測對象的守衛都要驗 baseline**（#407 R67j，自審抓到）：上一版
    # 只驗這兩支，於是其餘守衛若在注入**之前**就已經紅，它們的控制組會平白通過——
    # 控制組宣稱「注入造成了紅」，而紅早就在那裡。實測（把一個裸數字先注進規則檔）：
    # 10 個 numbers 控制組**全部**照樣報 ✓。這與 R67h 的教訓同型：一個跑過的控制組
    # 不等於一個能失敗的控制組，而這裡連「它在測什麼」都不成立。
    tested = sorted({g for _, g, _, _ in CASES + ROBUST})
    if not has_swift:
        tested = [g for g in tested if not g.endswith('.swift') and g != DRIFT_REL]
    dirty = []
    for rel in tested:
        rc, out = with_copy(rel, {})          # 未注入的乾淨 copy
        if rc != 0:
            dirty.append((rel, out))
    if dirty:
        print(f'✗ {len(dirty)} 支守衛在**注入之前**就已經紅——它們的控制組會平白通過：')
        for rel, out in dirty:
            print(f'  · {rel}\n    ' + (out or '（無輸出）').strip().replace('\n', '\n    ')[:300])
        return 1
    # **印實際驗過的支數**（#407 R67l）：R67j 把 baseline 驗證從固定 2 支擴成
    # `tested` 全部，而這行訊息沿用舊的 `_n`（2 或 1），於是它**低報**了自己做過
    # 的事（實測驗了 10 支卻說 2 支）。本 repo 有一整支守衛在抓「宣稱的數字沒跟上
    # 實際狀態」，而這行就落在同一支 harness 裡。
    print(f'baseline：{len(tested)} 支皆綠 ✓（{len(CASES)} 個 mutation 待跑）\n')
    SOURCE_INJECTED.clear()   # baseline 階段的計數不算——那裡 edits 是空的

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
        if name in _PAIRED_FLAT:
            paired[name] = out
        by_output[(guard, out)].append(name)
        if rc != 0 and not miss:
            print(f'✓ 注入「{name}」→ rc={rc}，具名')
            ok += 1
        else:
            print(f'✗ 注入「{name}」→ rc={rc}' + (f'，缺 {miss}' if miss else ''))
            print('   ' + (out or '（無輸出）').replace('\n', '\n   ')[:500])

    # **輸出逐字相同的 case 互相不可區分**（#407 R67c，把 R67b 的形狀一般化）。
    # 它可能是刻意的（`PAIRED_IDENTICAL` 那對，見下），也可能是沒人發現的重複——
    # 而重複**看起來像多一份覆蓋**：計數從 35 變 36、多印一個 ✓，維護者讀成
    # 「又多檢查了一件事」，其實是同一件事查了兩次。這與既有四列零實例守衛的理由
    # 都不同（不是看不見、不是假訊號、不是沉默的歧義，是**對測試自己的計數說謊**），
    # 所以在 `.claude/rules/zero-instance-guards.md` 另立一列（private repo，外部讀者取不到）。
    # 成本是零：上面的迴圈本來就跑完全部 case，這裡只是分組。實測 0 個未具名重複。
    _declared = [set(p) for p in PAIRED_IDENTICAL]
    undeclared = [names for names in by_output.values()
                  if len(names) > 1 and set(names) not in _declared]
    if undeclared:
        print(f'✗ {len(undeclared)} 組 case 的輸出逐字相同卻未具名為刻意的一對：')
        for names in undeclared:
            for x in names:
                print(f'      · {x}')
            print('    （若是刻意的，加進 PAIRED_IDENTICAL 並寫下為什麼相同）')
    else:
        print('✓ 無未具名的重複 case（輸出逐字相同者只有已具名的那一對）')
        ok += 1

    # **理由欄的提及不得改變任何事**（#407 R67b）：上面兩個 parity case 一個是
    # 另一個的注入**再加**一句種在理由欄的 `fmt`。R60 的主張就是那個加法無效，
    # 所以正確的斷言是**兩者輸出逐字相同**——而那是字串斷言做不到的（實測它們
    # 的輸出本來就一模一樣，所以先前給兩者加同一個 `` `fmt` `` 毫無區分力）。
    # 這一格若壞掉（理由欄開始算數），兩者的輸出會分岔。
    # **逐組檢查**（#413 起不只一組）：每一組的兩個 case 輸出必須逐字相同。
    inv_ok = True
    for a, b in PAIRED_IDENTICAL:
        if a not in paired or b not in paired:
            print(f'✗ 不變式：這一組只收到部分輸出（case 被改名或跳過？）\n'
                  f'   {a}\n   {b}')
            inv_ok = False
        elif paired[a] != paired[b]:
            print(f'✗ 不變式：這一組的輸出分岔了——被斷言為「不得改變任何事」'
                  f'的那個加法改變了守衛輸出\n   {a}\n   {b}')
            inv_ok = False
    if inv_ok:
        print(f'✓ 不變式：{len(PAIRED_IDENTICAL)} 組刻意相同的 case 輸出各自逐字一致')
        ok += 1

    # **純重排的正確斷言是「輸出逐字不變」，不是「有印通過訊息」**（#407 R67，
    # 跨模型審查指名兩個 ROBUST case 斷言完全相同）。通過訊息對所有 ROBUST case
    # 都一樣，所以它證明不了「通過得對」——切片若靜默截斷而剛好沒少掉命令名，
    # 守衛照樣印通過。改成拿**同一支守衛在未注入的 copy 上**的輸出當 oracle：
    # 重排不得改變任何一個字（含 `MCP 30｜CLI 43｜橫切 2` 這行計數）。
    # 現算而非寫死——寫死 43 會製造第二份會與 CLI.swift 分岔的規格，正是本 issue
    # 在修的形狀。
    # **oracle 的前提要自己驗**（#407 R67e）：逐字比對只在守衛輸出是決定性時才有
    # 意義。若哪天某支開始印時間、耗時、temp 路徑或走訪順序，ROBUST 會**偶發假紅**
    # ——而假紅比漏報更貴：它不只讓這一格失效，還會訓練維護者忽略**所有**紅燈。
    # 這是本 harness 唯一一個「失敗會傷到其他守衛」的檢查，所以它自己要被檢查。
    # 成本是每支 ROBUST 守衛多跑一次未注入（實測 2 支、約 2 秒）。實測全部決定性。
    pristine = {}
    nondeterministic = set()
    for name, guard, edits, must in ROBUST:
        try:
            if guard not in pristine and guard not in nondeterministic:
                first = with_copy(guard, {})[1]
                second = with_copy(guard, {})[1]
                if first != second:
                    diff = [l for l in second.splitlines() if l not in first.splitlines()]
                    print(f'✗ oracle 前提不成立：{guard} 的未注入輸出兩次不同'
                          f'——逐字比對會偶發假紅\n   第二次獨有：{diff[:3]}')
                    nondeterministic.add(guard)
                    continue
                pristine[guard] = first
            rc, out = with_copy(guard, edits)
        except SystemExit as e:
            print(e)
            continue
        if guard not in pristine:
            # **這個 continue 必須在算 drift 之前**（#407 R67h，跨模型審查指名）：
            # 前一版寫在後面，於是「同一支守衛有第二個 ROBUST case」時會先執行
            # `pristine[guard]` 而 KeyError——整支 harness crash，不是乾淨地少一格。
            # 而 R67e 的反向證實**結構上測不到它**：它毒化的守衛只有一個 ROBUST
            # case，第一輪就在上面 `continue` 了。挑一個只有一格的守衛當控制組，
            # 等於挑了唯一不會暴露這個路徑的那支。
            continue                      # 前提不成立時不假裝這一格通過
        miss = [m for m in must if m not in out]
        drift = out != pristine[guard]
        if rc == 0 and not miss and not drift:
            print(f'✓ 重排注入「{name}」→ 維持綠，且輸出與未注入逐字相同')
            ok += 1
        else:
            print(f'✗ 重排注入「{name}」→ rc={rc}'
                  + (f'，缺 {miss}' if miss else '')
                  + ('，輸出與未注入不同' if drift else ''))

    after = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}
    same = before == after
    expected = len(CASES) - len(skipped) + len(ROBUST) + 2  # +2 = 不變式、重複掃描
    if SOURCE_INJECTED:
        # **不靜默。** 這些 case 的 Swift 側沒有負控，而輸出若不說，它與「兩版都驗過了」
        # 長得一模一樣（`lossless-intake` 執行細節 3 的同一個立場）。
        uniq = sorted({os.path.basename(g) for g in SOURCE_INJECTED})
        print(f'ℹ {len(SOURCE_INJECTED)} 個 case 注入的是守衛**自己的原始碼**'
              f'（{"、".join(uniq)}）——Swift 版的等價程式碼在 compiled binary 裡，'
              f'改 .py 對它無效，所以這些 case **只驗了 Python 版**。'
              f'能改成環境注入的就該改（見 `with_copy` 的說明）。')
    print(f'\n=== negative control {ok}/{expected} '
          f'（{len(CASES) - len(skipped)} 須紅 ＋ {len(ROBUST)} 須綠 ＋ 2 後設檢查）==='
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
