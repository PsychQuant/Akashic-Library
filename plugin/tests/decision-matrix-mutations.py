#!/usr/bin/env python3
"""decision-matrix-drift.py 的 negative control。

一個沒紅過的檢查，與一個不存在的檢查，在輸出上完全一樣。本支逐一注入缺陷，
要求守衛 **(1) rc=1、(2) 具名到那一列或那個症狀、(3) 沒有順帶把別的格報壞**。

**mutate 的是 pristine copy，出貨的 CLAUDE.md 從頭到尾不被開啟以寫入**——結束前
以 `os.stat` 的 mtime 前後比對確認（前一版 harness 就地改寫版控中的檔案，#407 R6）。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MD = os.path.join(ROOT, 'CLAUDE.md')
GUARD = os.path.join(ROOT, 'plugin', 'tests', 'decision-matrix-drift.py')

R6 = '> | 正常 `git push` | 恢復 | 指向本樹 | 執行 | 執行 |'
R3 = '> | 正常 `git push` | 不跑（**現況**） | 指向本樹（merge 後） | **執行** | **零執行** |'
R5 = '> | 正常 `git push` | 恢復 | 指向主 repo（**未 merge**） | **零執行** | **執行** |'
R2 = '> | 正常 `git push` | 不跑（**現況**） | 指向主 repo（**本 worktree 現況**） | **零執行** | 零執行 |'
R1 = '> | 正常 `git push` | 不跑（**現況**） | 未設定（他人 clone 的預設） | 零執行 | 零執行 |'
HEAD = '> | push 方式 | CI 狀態 | hooksPath | 留在 pre-push | 移出、只留 CI |'

CASES = [
    # (名稱, mutate fn, 必須出現的字串, 不得出現的字串)
    ('把 R26q 那一列放回來（任一 × 留欄不一致）',
     lambda s: s.replace(R6, '> | 正常 `git push` | 恢復 | 任一 | 執行 | 執行 |'),
     ['✗ 列6', '被重複宣稱'], []),
    ('翻掉一格的宣稱值（列3 執行→零執行）',
     lambda s: s.replace(R3, R3.replace('| **執行** |', '| **零執行** |', 1)),
     ['✗ 列3'], ['✗ 列1', '✗ 列2', '✗ 列4']),
    ('刪掉一列（列5）→ 涵蓋出現缺口',
     lambda s: s.replace(R5 + '\n', ''),
     ['缺 ', "'主repo'"], ['✗ 列']),
    ('讓兩列重疊（列1 的 hooksPath 改成任一）',
     lambda s: s.replace(R1, '> | 正常 `git push` | 不跑（**現況**） | 任一 | 零執行 | 零執行 |'),
     ['✗ 列1', '被重複宣稱'], []),
    ('把一格的 hooksPath 弄成解析不出來的字',
     lambda s: s.replace(R2, R2.replace('指向主 repo（**本 worktree 現況**）', '（見上）', 1)),
     ['<未解析>'], ['矩陣與規則一致']),
    ('改掉表頭 → 找不到表',
     lambda s: s.replace(HEAD, '> | 推送方式 | CI | hooks | 留 | 移出 |'),
     ['找不到決策矩陣的表頭'], []),
    ('多塞一欄 → 欄數不是 5',
     lambda s: s.replace(R6, R6 + ' 備註 |'),
     ['欄數不是 5'], ['矩陣與規則一致']),
    # 這一個是負控自己抓出來的：上一版的「多塞一欄」寫成 `R6[:-1] + " 備註 |"`，
    # 切出來仍是 5 欄、mutation 沒生效。修它時看見結果格的子串比對會把
    # 「執行（只在 merge 後）」讀成無條件「執行」——限定詞被安靜丟掉。
    # #407 R28：三個「人讀是 A、parser 讀成 B 且不出聲」的自然編輯。上一輪只把
    # 結果欄改嚴格，其餘三欄仍是子串比對——修了一欄就以為修完了。
    ('push 格的註記提到「--no-verify」→ 不得被讀成 --no-verify',
     lambda s: s.replace(R6, '> | 正常 push（不帶 --no-verify） | 恢復 | 指向本樹 | 執行 | 執行 |'),
     ['<未解析>'], ['矩陣與規則一致']),
    ('hooksPath 格寫成「本樹以外」→ 不得只讀到其中一值',
     lambda s: s.replace(R6, '> | 正常 `git push` | 恢復 | 指向本樹以外（未設定或主 repo） | 執行 | 執行 |'),
     ['<未解析>'], ['矩陣與規則一致']),
    ('結果格帶限定詞 → 不得被讀成無條件',
     lambda s: s.replace(R6, R6.replace('| 執行 |', '| 執行（只在 merge 後） |', 1)),
     ['<未解析>'], ['矩陣與規則一致']),
]


def run(path):
    p = subprocess.run([sys.executable, GUARD, path], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# **不是每個注入都該讓守衛變紅。** 下面這些注入的正確結果是**維持綠**——它們檢查
# 的是「守衛沒有把裝飾當成內容」。把它們混進上面的清單會逼出一個錯的修法（實地
# 踩到：#407 R28b，我先把它寫成負控，於是「剝掉註記」這個**正確**的行為被當成缺陷）。
ROBUST = [
    ('CI 格的註記提到「恢復」→ 不得因此被讀成恢復',
     lambda s: s.replace('| 不跑（**現況**） |', '| 不跑（**等 macOS 帳務恢復**） |', 1),
     ['✓ 列1', '不跑']),
    ('push 格加一句無害註記 → 仍是正常',
     lambda s: s.replace(R1, R1.replace('正常 `git push`', '正常 `git push`（一般情形）', 1)),
     ['✓ 列1', '正常']),
]


def main():
    before = os.stat(MD)
    src = io.open(MD, encoding='utf8').read()

    rc, out = run(MD)
    print(f'baseline：rc={rc} ✓' if rc == 0 else f'✗ baseline 就紅了：\n{out}')
    if rc != 0:
        return 1
    print(f'（{len(CASES)} 個 mutation 待跑）\n')

    ok = 0
    for name, fn, must, mustnot in CASES:
        mutated = fn(src)
        # 注入沒生效卻報綠，是假 harness 的形狀（#407 R19）——直接擋掉。
        if mutated == src:
            print(f'✗ 注入「{name}」→ **內容沒變**，這個 case 無效')
            continue
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, 'CLAUDE.md')
            io.open(p, 'w', encoding='utf8').write(mutated)
            rc, out = run(p)
        miss = [m for m in must if m not in out]
        stray = [m for m in mustnot if m in out]
        if rc == 1 and not miss and not stray:
            print(f'✓ 注入「{name}」→ rc=1，具名且無旁及')
            ok += 1
        else:
            print(f'✗ 注入「{name}」→ rc={rc}'
                  + (f'，缺 {miss}' if miss else '')
                  + (f'，旁及 {stray}' if stray else ''))
            print('   ' + out.replace('\n', '\n   ')[:600])

    for name, fn, must in ROBUST:
        mutated = fn(src)
        if mutated == src:
            print(f'✗ 裝飾注入「{name}」→ **內容沒變**，這個 case 無效')
            continue
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, 'CLAUDE.md')
            io.open(p, 'w', encoding='utf8').write(mutated)
            rc, out = run(p)
        miss = [m for m in must if m not in out]
        if rc == 0 and not miss:
            print(f'✓ 裝飾注入「{name}」→ 維持綠，且讀到對的值')
            ok += 1
        else:
            print(f'✗ 裝飾注入「{name}」→ rc={rc}' + (f'，缺 {miss}' if miss else ''))

    after = os.stat(MD)
    same = (before.st_mtime_ns, before.st_size) == (after.st_mtime_ns, after.st_size)
    print(f'\n=== negative control {ok}/{len(CASES) + len(ROBUST)} '
          f'（{len(CASES)} 個須紅 ＋ {len(ROBUST)} 個須綠）===')
    print(f'{"出貨檔未被開啟以寫入" if same else "**出貨檔被動到了**"}：CLAUDE.md')
    return 0 if (ok == len(CASES) + len(ROBUST) and same) else 1


if __name__ == '__main__':
    sys.exit(main())
