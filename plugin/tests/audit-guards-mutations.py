#!/usr/bin/env python3
"""`rule-coverage.sh` 與 `hash-table-drift.sh` 的 negative control。

**為什麼是這兩支**（#407 R32）：R31 直接讀四支既有 harness 的呼叫行，量到 9 支守衛
裡只有 4 支被人跑過並要求變紅。剩下五支每次都綠，而「沒紅過的檢查與不存在的檢查
無從區分」正是本 issue 的立場——那五支落在自己的立場之外。

本支先補其中兩支（兩支 shell、自足、跑得快）。另外三支的裁決寫在下面，**不是漏掉**：

  `measured-claims-audit.py`  它的偵測式要跑 `git rev-list --all`，而 mutation 必須在
                              pristine copy 上跑；copy 裡沒有 `.git` → 偵測式在 copy
                              裡本來就不成立，紅得與注入無關。這正是 R27 踩過的
                              「因錯誤理由變紅的負控等於不存在」。要補它得先讓它
                              接受一個 `--repo` 之類的參數，屬另一件事。
  `review-claim-audit.sh`     它重建的是四個歷史 finding 的失敗情境，注入要跨
                              `.github/workflows` 與 parity 腳本兩處；成本明顯高於
                              本檔這兩支，值得但不在本輪。
  `multiscalar-parity.swift`  注入要改它內建的 census 模型再重編；每個 case 約一秒
                              的 swift 啟動，值得但同樣不在本輪。

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
DRIFT_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh'
TABLE_REL = 'plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt'
MULTI_REL = 'plugin/skills/akashic-literal-campaign/scripts/tests/multiscalar-parity.swift'
RULE_REL = 'plugin/rules/assertions-must-be-measured.md'

WATCHED = [COVERAGE_REL, DRIFT_REL, TABLE_REL, MULTI_REL, RULE_REL]


def with_copy(guard_rel, edits):
    """複製相關子樹、套用 edits、跑 copy 裡的那支守衛。"""
    with tempfile.TemporaryDirectory(prefix='audit-mut-') as tmp:
        for sub in ('plugin',):
            shutil.copytree(os.path.join(ROOT, sub), os.path.join(tmp, sub))
        for rel, fn in edits.items():
            p = os.path.join(tmp, rel)
            before = io.open(p, encoding='utf8').read()
            after = fn(before)
            if after == before:
                raise SystemExit(f'✗ 注入對 {rel} 沒有造成任何改動——這個 case 無效')
            io.open(p, 'w', encoding='utf8').write(after)
        r = subprocess.run(['bash', os.path.join(tmp, guard_rel)],
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
