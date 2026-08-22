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
    """判準有三段，第三段是 #407 R20d 補的。

    前兩段（守衛變紅、訊息指名了它）不足以說這格**鑑別**了它具名的缺陷：
    一個注入若順帶打壞別的東西，紅的原因就分不出來。姊妹 harness
    （plugin/tests/rule-prose-guards-mutations.py）在 R18b 已經吃過這個虧
    ——四格宣告「第 1 項」的注入實際紅 [1, 2]。

    所以第三段要求**每一條被報出來的缺口都屬於它指名的那一類**。實測八格
    全部「其他 0」，這條斷言在寫下時即為真，而它防的是日後新增的不純注入。
    """
    rc, out = with_copy(edits)
    hit = expect_substr in out
    gaps = re.findall(r'^  · (.+)$', out, re.M)
    stray = [g for g in gaps if expect_substr not in g]
    ok = rc != 0 and hit and not stray
    if ok:
        print(f'✓ {desc} → rc={rc}，指名了它'
              + (f'（缺口 {len(gaps)} 條全屬同類）' if gaps else ''))
    elif not hit:
        print(f'✗ {desc} → rc={rc}，但沒指名 ← 訊息對它是盲的')
    elif stray:
        print(f'✗ {desc} → rc={rc}，但另有 {len(stray)} 條無關缺口 '
              f'← 注入不是外科手術式的：{stray[:2]}')
    else:
        print(f'✗ {desc} → rc={rc}')
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
         # **指名側別**：缺口模板是「改 {f} 時 {g} 不在…」，裸檔名會同時吞下
         # f 側與 g 側。這一格宣告的是「把該檔從 paths 拿掉」，期望 f 側。
         '改 hash-merging-ranges.txt 時'),
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
    # 同一個 echo 但用 `./` 形式。R20 只修了直譯器那半邊（`bash X`），
    # `./X` 分支照舊掃全行——這一格是那個殘留的負控（#407 R20c）。
    case('把 run: 換成印出 ./ 形式檔名的 echo（R20 修法的殘留半邊）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: echo "見 ./plugin/tests/rule-coverage.sh 的說明"')},
         'rule-coverage.sh'),
    # 宣告機制若被「統一」成走 code_only()，宣告行（是註解）會被剝掉、機制
    # 整個失效——而守衛本來**不會紅**（只是少考慮幾個 pair，沉默地）。R20b
    # 把它變成會紅的，這一格證明那件事。
    case('把 declared() 改成走 code_only()（宣告行是註解，會被剝掉）',
         {'plugin/tests/trigger-coverage.py': lambda t: t.replace(
             "    for line in io.open(path, encoding='utf8', errors='replace'):\n"
             "        m = DECLARE.search(line)",
             "    for line in code_only(path).split('\\n'):\n"
             "        m = DECLARE.search(line)")},
         '宣告機制失效了'),
    # **這一格曾是「拿掉自指排除」，已隨那個特例一起退場**（#407 R21）：
    # DECLARE 收窄為「整行就是宣告」之後，實作者自己不再被誤認，特例沒有東西
    # 可保護、這一格也證明不了任何事。留著一個永遠綠的負控，與沒有負控在報告
    # 上長得一樣——那正是本 harness 存在的理由。
    #
    # 取而代之的兩格，來自同輪跨模型審查：
    # 兩條規則各一格，**刻意不用 `reads *`**：那個 glob 同時觸發兩條（無路徑
    # 成分 ＋ 命中全部），於是它證明不了是哪一條抓到的——第三段鑑別力判準會
    # 正確地把它判成不外科手術（實測過，#407 R21b）。
    #
    # `*.sh` 命中 5/16——**比例判準放它過**，結構判準擋下。這一格是判準從
    # 比例改成結構之後才抓得到的東西。
    # 切段之後，`bash A && bash B` 的 B 也認得出來——這一格證明那件事：
    # 把真的執行 B 的那一段改成 echo，B 才該從 found 消失（#407 R21c）。
    case('把 run 改成 `bash setup.sh && bash <守衛>` 再把後半換成 echo',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: bash scripts/setup.sh && echo "見 plugin/tests/rule-coverage.sh"')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    case('把宣告改成 `reads *.sh`（比例判準會放過，結構判準擋下）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads *.sh')},
         '沒有路徑成分'),
    # `*/*` 有路徑成分（結構判準放它過）但命中全部 16/16——證明全覆蓋那條
    # 檢查不是被結構判準遮蔽的死碼。
    case('把宣告改成 `reads */*`（有路徑成分但命中全部）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads */*')},
         '在描述整個 repo'),
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
