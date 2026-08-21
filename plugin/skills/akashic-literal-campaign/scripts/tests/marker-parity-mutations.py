#!/usr/bin/env python3
"""store-marker-parity.sh 的 negative control：證明它會紅。

為什麼這支也要出貨
==================
一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。#407 的第 5 輪就是
這個形狀：作者寫了 13 項驗收、跑三個 mutation、報「3/3 通過」，而跨模型審查把前一輪
的**原始**缺陷做成 mutation 一跑，13/13 完整存活——因為作者 mutate 的是那些檢查確實
涵蓋的東西，不是那些檢查**宣稱**涵蓋的東西。

所以下面每個 mutation 都對應一個**被實測抓到過**的分歧形狀，不是想像出來的。

用法
====
    plugin/skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py

需要先 `swift build`（parity 測試要拿真的 CLI 當 oracle）。

兩個實作紀律
============
**還原用整檔快照，不用反向編輯。** 第一版用 `t.replace(new, old, 1)` 還原，而其中一個
mutation 的還原字串在檔案裡更早就出現過，於是它改掉第一個命中——parser 從此對每個
註解行回 malformed，後面三個 mutation 全跑在一個已經壞掉的檔案上，結論全部無效
（而它們「看起來」只是沒紅）。反向編輯要求錨點唯一，那是一個沒人檢查、會安靜出錯的
額外條件；快照沒有這個條件，而且可以用 hash 驗證。

**注入點必須唯一。** `count(old) != 1` 直接中止並還原——一個命中兩處的錨點會讓
mutation 的語意變成「改了其中一個」，而是哪一個沒人知道。
"""
import hashlib
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
CENSUS = os.path.join(HERE, '..', 'literal-census.sh')
TEST = os.path.join(HERE, 'store-marker-parity.sh')

ORIGINAL = io.open(CENSUS, encoding='utf8').read()
ORIGINAL_SHA = hashlib.sha256(ORIGINAL.encode()).hexdigest()


def run_test():
    r = subprocess.run(['bash', TEST], cwd=REPO, capture_output=True, text=True)
    m = re.search(r'fail=(\d+)', r.stdout)
    return (int(m.group(1)) if m else -1), r.stdout


def restore():
    io.open(CENSUS, 'w', encoding='utf8').write(ORIGINAL)
    now = hashlib.sha256(io.open(CENSUS, encoding='utf8').read().encode()).hexdigest()
    if now != ORIGINAL_SHA:
        sys.exit('✗ 還原後 hash 不符——請用 git 檢查 literal-census.sh')


def mutate(old, new, desc, expect_case):
    if ORIGINAL.count(old) != 1:
        restore()
        sys.exit(f'✗ 注入點不唯一（{ORIGINAL.count(old)} 次）：{desc}')
    io.open(CENSUS, 'w', encoding='utf8').write(ORIGINAL.replace(old, new, 1))
    fails, out = run_test()
    hit = re.search(rf'✗ {re.escape(expect_case)}', out) is not None
    restore()
    ok = fails > 0 and hit
    print(f'{"✓" if ok else "✗"} 注入「{desc}」→ fail={fails}'
          f'{"，且該格變紅" if hit else "，但該格沒紅 ← 測試對它是盲的"}')
    return ok


RESULTS = [
    # 跳過不認識的頂層行 —— #112 關掉的毒化 marker 繞法
    mutate("            # grammar 不再跳過不認識的行。\n"
           "            return 'malformed', None, '(未知的頂層行)'",
           "            # grammar 不再跳過不認識的行。\n"
           "            continue",
           '跳過未知頂層行（meta: { 繞法）', '未知頂層行'),

    # 不檢查 n >= 1 —— 讀端對 format: 0 是 malformed
    mutate("        if n < 1:\n"
           "            return 'malformed', None, f'(format: {n}——版號須 >= 1)'",
           "        if False:\n"
           "            return 'malformed', None, '(unreachable)'",
           'format: 0 當成合法版號', 'format: 0'),

    # 重複的 format: 行 last-wins —— 讀端報歧義
    mutate("        if found is not None:\n"
           "            return 'malformed', None, '(第二個 format: 行——歧義)'",
           "        if False:\n"
           "            return 'malformed', None, '(unreachable)'",
           '重複 format: 行 last-wins', '第二個 format'),

    # 值後面的垃圾被當成帶註解的整數
    mutate("        if rest and not rest.startswith('#'):\n"
           "            return 'malformed', None, '(format: 值後面不是註解)'",
           "        if False:\n"
           "            return 'malformed', None, '(unreachable)'",
           '值後垃圾取前綴當真', 'format: 2.5'),

    # 非 UTF-8 直接 traceback —— 讀端明文 throw malformed
    mutate("    except UnicodeDecodeError:\n"
           "        # 讀端對此明文 throw malformed，訊息逐字是「(標記檔不是 UTF-8)」。\n"
           "        return 'malformed', None, '(標記檔不是 UTF-8)'",
           "    except UnicodeDecodeError:\n        raise",
           '非 UTF-8 直接 traceback', '非 UTF-8'),

    # 缺檔誤標成讀不到 —— 讀端：缺檔即 format 1
    mutate("    except FileNotFoundError:\n        return 'absent', 1, ''",
           "    except FileNotFoundError:\n        return 'unreadable', None, '(ENOENT)'",
           '缺檔誤標成讀不到', '缺檔'),

    # 縮排守衛拿掉。鑑別點是**縮排的 format 行**，不是「縮排的非註解行」——後者拿掉
    # 守衛後仍會落到「未知的頂層行」而照樣被拒。這個預期一開始寫錯，negative control
    # 於是報「測試對它是盲的」，而真正盲的是那行預期。
    mutate("        if line_raw[:1] and line_raw[0] in _WS:\n"
           "            return 'malformed', None, '(縮排的非註解行)'",
           "        if False:\n"
           "            return 'malformed', None, '(unreachable)'",
           '接受縮排的非註解行', '縮排的 format 行'),
]

print()
print(f'=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
AFTER, _ = run_test()
print(f'還原後 fail={AFTER}（原檔 sha256 {ORIGINAL_SHA[:12]}）')
sys.exit(0 if all(RESULTS) and AFTER == 0 else 1)
