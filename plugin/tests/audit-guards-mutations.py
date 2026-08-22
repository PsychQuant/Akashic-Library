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
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COVERAGE_REL = 'plugin/tests/rule-coverage.sh'
REVIEW_REL = 'plugin/tests/review-claim-audit.sh'
PARITY_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh'
GEN_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/derive-hash-extenders.swift'
WF_REL = '.github/workflows/census-parity.yml'
CLAIMS_REL = 'plugin/tests/measured-claims-audit.py'
NUMBERS_REL = 'plugin/tests/measured-numbers-audit.py'
BACKLINK_REL = '.claude/rules/entity-backlink-completeness.md'
DRIFT_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh'
TABLE_REL = 'plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt'
MULTI_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/multiscalar-parity.swift'
RULE_REL = 'plugin/rules/assertions-must-be-measured.md'

WATCHED = [COVERAGE_REL, DRIFT_REL, TABLE_REL, MULTI_REL, RULE_REL,
           REVIEW_REL, PARITY_REL, GEN_REL, WF_REL, CLAIMS_REL,
           NUMBERS_REL, BACKLINK_REL]


def with_copy(guard_rel, edits):
    """複製相關子樹、套用 edits、跑 copy 裡的那支守衛。"""
    with tempfile.TemporaryDirectory(prefix='audit-mut-') as tmp:
        for sub in ('plugin', '.github', '.claude'):
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
    ('coverage：把某個 skill 的規則連結整個拿掉',
     COVERAGE_REL,
     {'plugin/skills/akashic-literal-campaign/SKILL.md':
      lambda t: t.replace('../../rules/assertions-must-be-measured.md', '見規則目錄')},
     ['✗']),
    ('coverage：掛載還在但相對路徑指到不存在的檔',
     COVERAGE_REL,
     {'plugin/skills/akashic-literal-campaign/SKILL.md':
      lambda t: t.replace('../../rules/assertions-must-be-measured.md',
                          '../../rules/assertions-must-be-measured-v2.md', 1)},
     ['✗']),
    # ── hash-table-drift.sh ───────────────────────────────────────────────
    ('drift：生成的表被人手改了一段',
     DRIFT_REL,
     {TABLE_REL: lambda t: t.replace('\n', '\n', 1) and _perturb_table(t)},
     ['✗']),
    ('drift：multiscalar 的 inline RANGES 與表脫節',
     DRIFT_REL,
     {MULTI_REL: lambda t: _perturb_ranges(t)},
     ['✗']),
    # ── review-claim-audit.sh（#407 R34）──────────────────────────────────
    # 它重建的是四個歷史 finding 的失敗情境。每個 mutation 把其中一個修法**還原**，
    # 對應的 verdict 就該翻掉。R32 把這支列為「值得，不在本輪」——本輪補上。
    ('review：把 5000 前導零 fixture 改回會退化的長度',
     REVIEW_REL,
     {PARITY_REL: lambda t: t.replace("printf '%05000d'", "printf '%0500d'")},
     ['✗']),
    ('review：把生成表從 parity workflow 的 paths 拿掉',
     REVIEW_REL,
     {WF_REL: lambda t: t.replace('      - "plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt"\n', '')},
     ['✗']),
    ('review：讓生成器真的去讀 CommandLine.arguments',
     REVIEW_REL,
     {GEN_REL: lambda t: t.replace('import Foundation',
                                   'import Foundation\nlet _ = CommandLine.arguments', 1)},
     ['✗']),
    ('review：把宣稱 --check 的那句註解加回去',
     REVIEW_REL,
     {GEN_REL: lambda t: t.replace('import Foundation',
                                   '// 用法：derive-hash-extenders.swift --check <生成的表>\nimport Foundation', 1)},
     ['✗']),
    # ── measured-claims-audit.py（#407 R35）───────────────────────────────
    ('claims：改壞偵測式（抽取式仍指向舊字面）',
     CLAIMS_REL,
     # **要打到程式碼那一份，不是註解那一份**：R26x 之後抽取式會先剝註解，
     # 所以改註解不會讓守衛紅——那是它**該有**的行為。用完整的偵測式字面定位。
     {CLAIMS_REL: lambda t: t.replace(
         '''| sed '/^$/q' | grep -q '^gpgsig' ''',
         '''| sed '/^$/q' | grep -q '^gpgSIG' ''', 1)},
     ['✗']),
    # 白名單要打**真的會出現在 header 裡**的欄位。先前寫 `gpgsig-sha256`——本 repo
    # 的 commit 未簽署，那個欄位從不出現，於是拿掉它對輸出零影響、守衛正確地不紅
    # （#407 R35 當場量到）。`tree` 每個 commit 都有。
    ('claims：把白名單裡的 tree 拿掉（它每個 commit 都有）',
     CLAIMS_REL,
     {CLAIMS_REL: lambda t: t.replace("'tree': '內容指標'", "'tree-x': '內容指標'", 1)},
     ['✗']),
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
     ['分歧數']),
    ('multi：模型改看最後一個 scalar',
     MULTI_REL,
     {MULTI_REL: lambda t: t.replace('guard let f = cps.first else { return true }',
                                     'guard let f = cps.last else { return true }', 1)},
     ['分歧數']),
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


def main():
    before = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}

    for rel in (COVERAGE_REL, DRIFT_REL):
        r = subprocess.run(['bash', os.path.join(ROOT, rel)],
                           capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0:
            print(f'✗ baseline 就紅了：{rel}\n{r.stdout}{r.stderr}')
            return 1
    print(f'baseline：兩支皆綠 ✓（{len(CASES)} 個 mutation 待跑）\n')

    ok = 0
    for name, guard, edits, must in CASES:
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

    after = {r: os.stat(os.path.join(ROOT, r)).st_mtime_ns for r in WATCHED}
    same = before == after
    print(f'\n=== negative control {ok}/{len(CASES)} ===')
    print(f'{"出貨檔未被開啟以寫入" if same else "**出貨檔被動到了**"}：{len(WATCHED)} 個受監看檔')
    return 0 if (ok == len(CASES) and same) else 1


if __name__ == '__main__':
    sys.exit(main())
