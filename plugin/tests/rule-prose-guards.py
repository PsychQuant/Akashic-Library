#!/usr/bin/env python3
"""plugin/ 散文的機械守衛：可跟隨的懸空連結、未揭露的 repo 專屬路徑、假的自我量測。

為什麼這支要出貨
================
#407 的驗收前五輪都跑在一個**只存在於作者 scratchpad 的腳本**裡。跨模型審查點名了
這件事（R5 finding 44：「整套十三項守衛不在版控裡」）——一個沒進版控的守衛，下一個人
不會知道它存在、不會跑它、改壞了也不會有人發現。

同一輪還證明了另一件更難堪的事：那十三項**全綠**，而把前一輪的原始缺陷做成 mutation
一跑，13/13 完整存活。所以這裡只保留**驗證過會紅**的那幾項，並刪掉三項被證明是空的：

  * 「census 的標籤與讀端一致」—— 三個謂詞全壞（一個對整檔做子串比對、一個檢查
    「那句宣稱有沒有被印出來」而非它是否為真、一個被 `or True` 中和且從未進入斷言）。
    **已由 tests/store-marker-parity.sh 取代**：那支拿真的 CLI 當 oracle，不看字串。
  * census 分支的輸出不變式 —— 同樣由 parity 測試涵蓋。
  * 「恰 N 個 skill 引用」—— 硬編計數，已由 tests/rule-coverage.sh 取代。

用法
====
    plugin/tests/rule-prose-guards.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.abspath(os.path.join(HERE, '..'))
RULE = os.path.join(PLUGIN, 'rules', 'assertions-must-be-measured.md')

# repo 專屬路徑 ＝ 讀者要有那個 repo 才找得到的東西。三種形狀。
REPO_ONLY = re.compile(
    r'\.claude/rules/|Sources/Akashic\w+/|(?<!\w)docs/[a-z-]+\.md|'
    r'Akashic-Library/blob/')
# 揭露 ＝ 讓讀者知道自己可能取不到
DISCLOSE = re.compile(r'private|存取權|取不到|讀不到|跑不了|拿不到')

results = []


def check(n, desc, actual, expected):
    ok = actual == expected
    results.append(ok)
    print(f'[{n}] {"PASS" if ok else "FAIL"}  {desc}')
    if not ok:
        print(f'      期望 {expected!r}')
        print(f'      實際 {actual!r}')


def files(root):
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(('.md', '.sh', '.py')):
                yield os.path.join(dp, fn)


# 兩個路徑檢查都只涵蓋**散文**：markdown 的每一行，以及 .sh/.py 的**註解行**。
# 可執行的程式碼行不算——`"$REPO/Sources/.../StoreVersion.swift"` 這種用法沒有
# 東西可以「跟隨」，它要嘛跑得動要嘛報錯；而一個 negative control 腳本必須能把
# 違規字面寫成字串常數，否則它沒辦法注入。
#
# 這個收窄是刻意的，而且是被實測逼出來的：不收窄的話，本檔自己的 regex 定義會被
# 第 2 項 flag（第一版就是），本目錄的 mutation 腳本會被第 1 項 flag（第二版就是）。
# 兩次的替代方案都是「加一份豁免清單」——而豁免清單才是真正會長出漏洞的東西。
def prose_lines(fp):
    md = fp.endswith('.md')
    for i, line in enumerate(open(fp, encoding='utf8', errors='replace'), 1):
        if md or line.lstrip().startswith('#'):
            yield i, line


# ── 1. repo 專屬路徑不得以「可跟隨的連結」出現 ─────────────────────────────
#    點下去會 404，而 private repo 的 404 與「已刪除／從不存在」不可區分：
#    等於把缺訊號換成假訊號。主要讀者是未認證的 agent。
followable = []
for fp in files(PLUGIN):
    for i, line in prose_lines(fp):
        if re.search(r'\]\([^)]*(?:\.claude/rules/|Akashic-Library/blob/)', line):
            followable.append(f'{os.path.basename(fp)}:{i}')
check(1, 'repo 專屬路徑以可跟隨連結出現', followable, [])

# ── 2. 每一處提到 repo 專屬路徑，都要在**同一行**揭露讀者可能取不到 ────────
#    刻意不用 ±N 行的視窗：曾經有一行借用了兩行外、針對**另一個路徑**的揭露而
#    假通過——而那正是上一輪具名、本輪宣稱修好卻沒修的那一處。鄰近不等於
#    「這個揭露在講這個路徑」。
undisclosed = []
for fp in files(PLUGIN):
    for i, line in prose_lines(fp):
        if REPO_ONLY.search(line) and not DISCLOSE.search(line):
            undisclosed.append(f'{os.path.basename(fp)}:{i}')
check(2, '提到 repo 專屬路徑卻未在同一行揭露取用限制', undisclosed, [])

rule_txt = open(RULE, encoding='utf8').read()

# ── 3. 規則檔不得回到分類法形式 ────────────────────────────────────────────
#    前兩版都是分類法，兩版都被跨模型審查打掉，原因相同：每條分類邊界本身
#    就是一個關於命題世界的斷言。
taxonomy = [w for w in ('三分法', '封閉列舉，只有三類', '軸 A', '軸 B') if w in rule_txt]
check(3, '規則檔殘留分類法用語', taxonomy, [])

# ── 4. 規則檔不得再出現被同段證據否證的假全稱句 ────────────────────────────
#    「三筆都回傳了 volume／issue」——而同句括號印著第一筆 vol=None。
#    掃描前剝掉「…」：**引述**一句假話不等於斷言它（失敗史必須引述得了它）。
def unquoted(s):
    return re.sub(r'「[^」]*」', '', s)


false_all = [l for l in rule_txt.split('\n')
             if '都回傳了 volume' in unquoted(l) or '三筆都帶著 volume' in unquoted(l)]
check(4, '規則檔殘留「三筆都…volume」的假全稱句', false_all, [])

# ── 5. 規則檔自陳的量測指令，跑出來要是它宣稱的數字 ────────────────────────
#    上一版出貨的指令跑出來是 8 而非 6（它數整個檔案的 case 行，而括號裡寫著
#    「取 enum VenueType 區塊」）。旗艦主張的自我量測，第一列就不成立。
#    謂詞不是「`六值` 這個字串在不在」——第一版是那樣寫的，而 negative control
#    立刻證明它是盲的：把其中一處改成「三值」，其他地方還有「六值」，檢查照樣綠。
#    要驗的是**每一處關於 VenueType 的數量宣稱都正確**，不是某一處正確。
#    引號內的不算：失敗史必須引述得了那句假話（「`VenueType` 是封閉三值」）。
CJK_NUM = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6,
           '七': 7, '八': 8, '九': 9, '十': 10}
venue_src = os.path.join(PLUGIN, '..', 'Sources', 'AkashicCore', 'Venue.swift')
if os.path.isfile(venue_src):
    body = open(venue_src, encoding='utf8', errors='replace').read()
    seg = body.split('enum VenueType')[1].split('\n}')[0]
    n_case = len(re.findall(r'^\s+case \w+$', seg, re.M))
    wrong = []
    for ln, line in enumerate(rule_txt.split('\n'), 1):
        # 相關性看**整行**、數字宣稱只看**剝引號後**的部分。兩者都用 bare 的話，
        # 一行若把 VenueType 寫在引號內（失敗史必然如此），整行會被判為不相關而
        # 跳過——引號外的數字宣稱就漏檢了。negative control 抓到的。
        bare = unquoted(line)
        if 'VenueType' not in line and '值域' not in line:
            continue
        for m in re.finditer(r'([一二三四五六七八九十])值', bare):
            if CJK_NUM[m.group(1)] != n_case:
                wrong.append(f'第 {ln} 行宣稱 {m.group(0)}，實測 {n_case}')
    check(5, f'規則對 VenueType 的每一處數量宣稱都與實測一致（實測 {n_case}）',
          wrong, [])
else:
    print('[5] SKIP  取不到 Venue.swift（plugin 單獨安裝——repo 為 private）')

print()
print(f'=== {sum(results)}/{len(results)} PASS ===')
sys.exit(0 if all(results) else 1)
