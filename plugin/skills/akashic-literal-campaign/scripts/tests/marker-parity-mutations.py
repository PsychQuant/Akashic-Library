#!/usr/bin/env python3
"""store-marker-parity.sh 的 negative control：證明它會紅。

為什麼這支也要出貨
==================
一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。#407 的第五輪就是
這個形狀：十三項驗收全綠，而把前一輪的**原始**缺陷做成 mutation 一跑，13/13 完整
存活——因為作者 mutate 的是那些檢查確實涵蓋的東西，不是那些檢查**宣稱**涵蓋的東西。

所以下面每個 mutation 都對應一個**被實測抓到過**的分歧形狀，不是想像出來的。

**它 mutate 的是一份 copy，不是出貨檔**（#407 R7）
==================================================
前一版就地改寫版控中的 `literal-census.sh`，再用快照還原。跨模型審查在**審查期間
實際觀察到**該檔出現三種被注入的狀態（15:12 `if False:` 取代 `n < 1` 守衛、15:13
`FileNotFoundError → unreadable`、同分鐘 parity 測試報 `未知頂層行` 那格紅）。量到
的注入窗口是總執行時間的約 87%。

三個缺口當時同時存在，而**第三個讓失敗變成自我祝福**：

  1. 無 `try/finally`／`atexit`／signal handler —— `run_test()` 期間 Ctrl-C 或任何
     例外傳播出去，還原永不執行；`RESULTS` 是 list literal，例外直接終止程序。
  2. 無並行互斥 —— 兩個 session 同時跑，注入窗口重疊。
  3. 無前置潔淨檢查 —— 第二個 process 讀到的「原檔」是**已被注入**的內容，
     `ORIGINAL_SHA` 算在壞檔上，於是它的還原把 mutation **永久寫回**，而 sha256
     比對**通過**。守衛被靜默關閉，兩支 harness 都回報成功。

**根治不是把三個缺口各補一塊，是不要碰原檔。** 現在 census 被複製到 tempdir，
mutation 只作用在 copy 上，parity 測試以 `--census <copy>` 指向它。三個缺口一次
消失：沒有鎖要拿，沒有還原要保證，沒有潔淨要檢查——因為出貨檔從頭到尾沒被開啟
以寫入。這也讓並行變成安全的（各自的 tempdir）。

用法
====
    plugin/skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py

需要先 `swift build`（parity 測試要拿真的 CLI 當 oracle）。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
CENSUS = os.path.join(HERE, '..', 'literal-census.sh')
TEST = os.path.join(HERE, 'store-marker-parity.sh')

ORIGINAL = io.open(CENSUS, encoding='utf8').read()


def run_test(census_path):
    r = subprocess.run(['bash', TEST, '--census', census_path],
                       cwd=REPO, capture_output=True, text=True)
    m = re.search(r'fail=(\d+)', r.stdout)
    return (int(m.group(1)) if m else -1), r.stdout


def mutate(work, old, new, desc, expect_case):
    """把 census 複製到 work/，改 copy，拿 copy 跑測試。出貨檔完全不碰。"""
    if ORIGINAL.count(old) != 1:
        sys.exit(f'✗ 注入點不唯一（{ORIGINAL.count(old)} 次）：{desc}')
    copy = os.path.join(work, 'literal-census.sh')
    io.open(copy, 'w', encoding='utf8').write(ORIGINAL.replace(old, new, 1))
    os.chmod(copy, 0o755)
    fails, out = run_test(copy)
    hit = re.search(rf'✗ {re.escape(expect_case)}', out) is not None
    ok = fails > 0 and hit
    print(f'{"✓" if ok else "✗"} 注入「{desc}」→ fail={fails}'
          f'{"，且該格變紅" if hit else "，但該格沒紅 ← 測試對它是盲的"}')
    return ok


MUTATIONS = [
    # 跳過不認識的頂層行 —— #112 關掉的毒化 marker 繞法
    ("            # grammar 不再跳過不認識的行。\n"
     "            return 'malformed', None, '(未知的頂層行)'",
     "            # grammar 不再跳過不認識的行。\n"
     "            continue",
     '跳過未知頂層行（meta: { 繞法）', '未知頂層行'),

    # 不檢查 n >= 1 —— 讀端對 format: 0 是 malformed
    ("        if n < 1:\n"
     "            return 'malformed', None, f'(format: {n}——版號須 >= 1)'",
     "        if False:\n"
     "            return 'malformed', None, '(unreachable)'",
     'format: 0 當成合法版號', 'format: 0'),

    # 重複的 format: 行 last-wins —— 讀端報歧義
    ("        if found is not None:\n"
     "            return 'malformed', None, '(第二個 format: 行——歧義)'",
     "        if False:\n"
     "            return 'malformed', None, '(unreachable)'",
     '重複 format: 行 last-wins', '第二個 format'),

    # 值後面的垃圾被當成帶註解的整數
    ("        if rest and not rest.startswith('#'):\n"
     "            return 'malformed', None, '(format: 值後面不是註解)'",
     "        if False:\n"
     "            return 'malformed', None, '(unreachable)'",
     '值後垃圾取前綴當真', 'format: 2.5'),

    # 非 UTF-8 直接 traceback —— 讀端明文 throw malformed
    ("    except UnicodeDecodeError:\n"
     "        # 讀端對此明文 throw malformed，訊息逐字是「(標記檔不是 UTF-8)」。\n"
     "        return 'malformed', None, '(標記檔不是 UTF-8)'",
     "    except UnicodeDecodeError:\n        raise",
     '非 UTF-8 直接 traceback', '非 UTF-8'),

    # 缺檔誤標成讀不到 —— 讀端：缺檔即 format 1
    ("    except FileNotFoundError:\n        return 'absent', 1, ''",
     "    except FileNotFoundError:\n        return 'unreadable', None, '(ENOENT)'",
     '缺檔誤標成讀不到', '缺檔'),

    # 縮排守衛。鑑別點是**縮排的 format 行**，不是「縮排的非註解行」——後者拿掉
    # 守衛後仍會落到「未知的頂層行」而照樣被拒。這個預期一開始寫錯，negative
    # control 於是報「測試對它是盲的」，而真正盲的是那行預期。
    ("        if line_raw[:1] and line_raw[0] in _WS:\n"
     "            return 'malformed', None, '(縮排的非註解行)'",
     "        if False:\n"
     "            return 'malformed', None, '(unreachable)'",
     '接受縮排的非註解行', '縮排的 format 行'),

    # ── 以下四個對應 R6 CRITICAL 2/4 與 HIGH 22（前一版的七個 mutation 全部
    #    繞開了數值解析這條唯一被承認仍分歧的路徑，所以 7/7 對現存缺陷零資訊）──

    # 認 Unicode 數字 —— Swift 的 Int() 只吃 ASCII
    ("            if ch not in '0123456789':",
     "            if not ch.isdigit():",
     '數值解析認 Unicode 數字', '全形數字'),

    # 不設 Int64 上界 —— Python 的 int 是任意精度
    ("        if n > 2 ** 63 - 1:\n"
     "            return 'malformed', None, '(format: 值超出 Int64——讀端的 Int() 回 nil)'",
     "        if False:\n"
     "            return 'malformed', None, '(unreachable)'",
     '不設 Int64 上界', 'Int64 溢位'),

    # tooNew 偵測拿掉 —— 一個沒有任何 binary 打得開的 store 印得跟健康 store 相同
    ("_too_new = fmt_state == 'read' and _supported is not None and fmt > _supported",
     "_too_new = False",
     '不偵測 tooNew', '版號太新'),

    # BOM 當成未知頂層行 —— 讀端吃掉 BOM，正常開啟
    ("        text = raw_bytes.decode('utf-8-sig')",
     "        text = raw_bytes.decode('utf-8')",
     'BOM 被當成未知頂層行', 'UTF-8 BOM'),
]

# baseline 必須先全綠——否則「注入後變紅」不代表任何事（R6 finding 11：前一版
# 從不檢查 baseline，原守衛整片壞掉時它仍會 exit 0）。
BASE_FAILS, BASE_OUT = run_test(os.path.abspath(CENSUS))
if BASE_FAILS != 0:
    print(BASE_OUT)
    sys.exit(f'✗ baseline 不是全綠（fail={BASE_FAILS}）——先修 parity 測試，'
             f'negative control 在紅的 baseline 上沒有意義')
print(f'baseline：fail=0 ✓（{len(MUTATIONS)} 個 mutation 待跑）')
print()

with tempfile.TemporaryDirectory(prefix='marker-mut-') as WORK:
    RESULTS = [mutate(WORK, *m) for m in MUTATIONS]

print()
print(f'=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
print(f'出貨檔未被開啟以寫入：{os.path.relpath(CENSUS, REPO)}')
sys.exit(0 if all(RESULTS) else 1)
