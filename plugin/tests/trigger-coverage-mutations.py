#!/usr/bin/env python3
"""negative control：trigger-coverage.py 真的會在觸發點被拆掉時變紅嗎？

一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。

**mutate 的是一份 copy**，出貨檔完全不碰（#407 R7 的教訓：前一版就地改寫版控中
的檔案，跨模型審查在審查期間實際觀察到出貨檔出現三種被注入的狀態）。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GUARD_REL = 'plugin/tests/trigger-coverage.py'
BEFORE = os.path.getmtime(os.path.join(ROOT, GUARD_REL))


def run(root):
    r = subprocess.run([sys.executable, os.path.join(root, GUARD_REL), '--root', root],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def with_copy(edits):
    """複製整個 repo 的相關子樹，套用 edits（相對路徑 → 轉換函式），跑守衛。"""
    with tempfile.TemporaryDirectory(prefix='trig-mut-') as tmp:
        for sub in ('plugin', '.github', '.githooks', 'Sources'):
            src = os.path.join(ROOT, sub)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(tmp, sub))
        for rel, fn in edits.items():
            p = os.path.join(tmp, rel)
            # **先讀完，再開寫。** 寫成一行的話 Python 會先求值 io.open(p,'w')
            # ——那一步就截斷了檔案——才求參數裡的 read()，於是讀到空字串、
            # 寫回空字串。#407 R19 當場踩到：守衛的 copy 是 0 bytes，於是它
            # 零輸出、rc=0，而**前三格仍然「紅」**——紅的原因是檔案被清空，
            # 不是它們宣稱的注入。一個因錯誤理由變紅的負控，等於不存在。
            before = io.open(p, encoding='utf8').read()
            after = fn(before)
            if after == before:
                raise SystemExit(f'✗ 注入對 {rel} 沒有造成任何改動——'
                                 f'注入式已與被注入的內容脫節')
            io.open(p, 'w', encoding='utf8').write(after)
        return run(tmp)


def case(desc, edits, expect_substr):
    rc, out = with_copy(edits)
    hit = expect_substr in out
    ok = rc != 0 and hit
    print(f'{"✓" if ok else "✗"} {desc} → rc={rc}'
          f'{"，且指名了它" if hit else "，但沒指名 ← 訊息對它是盲的"}')
    return ok


base_rc, base_out = run(ROOT)
if base_rc != 0:
    sys.exit(f'✗ baseline 不是全綠（rc={base_rc}）——負控在紅的 baseline 上沒有意義\n{base_out}')
print('baseline：無缺口 ✓\n')

RESULTS = [
    case('從 pre-push 拿掉一支守衛',
         {'.githooks/pre-push': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n', '')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    case('從 workflow 的 paths 拿掉 census 的資料依賴',
         {'.github/workflows/census-parity.yml': lambda t: t.replace(
             '      - "plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt"\n', '')},
         'hash-merging-ranges.txt'),
    case('從 workflow 拿掉一個 run 步驟（守衛還在版控，只是不再被執行）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh', 'run: true  # 被拿掉了')},
         'rule-coverage.sh'),
    # 下面兩格是 #407 R20 跨模型審查實測到的**假陰性**——修法之前這兩種狀態
    # 都讓守衛報綠而它宣稱的性質為假。
    case('把 pre-push 的一支守衛換成只提到它的註解',
         {'.githooks/pre-push': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n',
             '# TODO: 之後再接 plugin/skills/akashic-literal-campaign/'
             'scripts/tests/store-marker-parity.sh\n')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    case('把 workflow 的一個 run: 換成只印檔名的 echo',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: echo "見 plugin/tests/rule-coverage.sh 的說明"')},
         'rule-coverage.sh'),
    case('把受保護檔案的路徑改成不存在的（憑記憶寫路徑的那個坑）',
         {GUARD_REL: lambda t: t.replace(
             "'Sources/AkashicStoreIO/StoreVersion.swift'",
             "'Sources/AkashicCore/StoreVersion.swift'")},
         '不存在的路徑'),
]

# 出貨檔不得被開啟以寫入。
assert os.path.getmtime(os.path.join(ROOT, GUARD_REL)) == BEFORE, \
    '✗ 出貨檔被改動了'
print(f'\n=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
print(f'出貨檔未被開啟以寫入：{GUARD_REL}')
sys.exit(0 if all(RESULTS) else 1)
