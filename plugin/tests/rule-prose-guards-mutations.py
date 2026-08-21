#!/usr/bin/env python3
"""rule-prose-guards.py 的 negative control：五項各證明會紅。

為什麼這支也要出貨
==================
與 `akashic-literal-campaign/scripts/tests/marker-parity-mutations.py` 同一條紀律：
**一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。** #407 的第五輪
正是這個形狀——十三項驗收全綠，而把前一輪的原始缺陷做成 mutation 一跑，13/13
完整存活。

這支腳本自己也證明了它的價值：撰寫當下，第 5 項的兩個版本都被它判定為盲的。

  * 第一版：`'六值' in rule_txt`——檔案別處還有「六值」，所以改掉一處照樣綠。
  * 第二版（逐處比對）：相關性與數字宣稱都看剝引號後的文字，於是一行若把
    `VenueType` 寫在引號內（失敗史必然如此），整行被判為不相關而跳過，引號外的
    數字宣稱漏檢。

兩次都是先看到「沒紅」才知道謂詞有洞。

用法
====
    plugin/tests/rule-prose-guards-mutations.py

還原用整檔快照 ＋ sha256 驗證——反向編輯要求錨點唯一，而那是一個沒人檢查、
會安靜出錯的額外條件（同一個 issue 內踩過一次：還原字串在檔案更早處也出現，
於是改錯地方，後續三個 mutation 全跑在壞掉的檔案上而「看起來」只是沒紅）。
"""
import hashlib
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.abspath(os.path.join(HERE, '..'))
GUARD = os.path.join(HERE, 'rule-prose-guards.py')
RULE = os.path.join(PLUGIN, 'rules', 'assertions-must-be-measured.md')

SNAP = io.open(RULE, encoding='utf8').read()
SHA = hashlib.sha256(SNAP.encode()).hexdigest()


def run():
    return subprocess.run([sys.executable, GUARD], cwd=PLUGIN,
                          capture_output=True, text=True).stdout


def restore():
    io.open(RULE, 'w', encoding='utf8').write(SNAP)
    if hashlib.sha256(io.open(RULE, encoding='utf8').read().encode()).hexdigest() != SHA:
        sys.exit('✗ 還原失敗——請用 git 檢查規則檔')


def report(out, n, desc):
    restore()
    red = re.search(rf'^\[{n}\] FAIL', out, re.M) is not None
    print(f'{"✓" if red else "✗"} {desc} → 第 {n} 項 {"變紅" if red else "沒紅 ← 守衛對它是盲的"}')
    return red


def append(extra, n, desc):
    """在規則檔尾端追加一段違規散文。"""
    io.open(RULE, 'w', encoding='utf8').write(SNAP + '\n' + extra + '\n')
    return report(run(), n, desc)


def swap(old, new, n, desc):
    if SNAP.count(old) != 1:
        restore()
        sys.exit(f'✗ 錨點不唯一（{SNAP.count(old)} 次）：{desc}')
    io.open(RULE, 'w', encoding='utf8').write(SNAP.replace(old, new, 1))
    return report(run(), n, desc)


RESULTS = [
    append('見 [那條規則](.claude/rules/identity-is-judged-not-matched.md)。',
           1, '加一個可跟隨的 repo 連結（private repo 的 404 ＝ 假訊號）'),
    append('判準寫在 `.claude/rules/identity-is-judged-not-matched.md`。',
           2, '加一句未揭露取用限制的 repo 專屬路徑'),
    append('本規則採三分法。', 3, '把被打掉兩次的分類法用語加回來'),
    append('三筆都回傳了 volume／issue。', 4, '把被同段證據否證的假全稱句放回引號外'),
    swap('實測**六值**', '實測**三值**', 5, '把 VenueType 的數量宣稱改錯'),
]

print()
print(f'=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
print('還原後：', run().strip().split('\n')[-1])
sys.exit(0 if all(RESULTS) else 1)
