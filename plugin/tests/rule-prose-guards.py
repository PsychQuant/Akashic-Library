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
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.abspath(os.path.join(HERE, '..'))
VENUE = None

# --root <dir> / --venue <path>：讓 negative control 能對**一份 copy** 跑，
# 而不是就地改寫出貨檔。前一版的 harness 改的是版控中的規則檔，而跨模型審查在
# 審查期間實際觀察到姊妹 harness 把 tracked 的 census 改壞三次。改成 copy 之後，
# 鎖／finally／前置潔淨檢查三個缺口一次消失——原檔不再被碰。
_args = sys.argv[1:]
while _args:
    if _args[0] == '--root':
        PLUGIN = os.path.abspath(_args[1]); _args = _args[2:]
    elif _args[0] == '--venue':
        VENUE = os.path.abspath(_args[1]); _args = _args[2:]
    else:
        sys.exit(f'✗ 未知參數：{_args[0]}')

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
        # 謂詞用**同一個** REPO_ONLY，不另寫一份縮寫版。前一版這裡手寫了它四種
        # 形狀中的兩種，於是把一個指向另外兩種的可跟隨連結注入進去，5/5 全綠。
        # **一份規格的兩個副本必然分岔**——這是本 issue 反覆的主題，而這裡是它在
        # 守衛自己身上的實例。
        #
        # 註解刻意不逐字寫出那兩種形狀：寫了就會被第 2 項 flag（實測過三次），
        # 而替代方案是加一份豁免清單——豁免清單才是真正會長出漏洞的東西。
        if re.search(r'\]\([^)]*', line) and REPO_ONLY.search(
                line[line.find(']('):] if '](' in line else ''):
            followable.append(f'{os.path.basename(fp)}:{i}')
check(1, 'repo 專屬路徑以可跟隨連結出現', followable, [])

# ── 2. 每一處提到 repo 專屬路徑，都要在**同一行**揭露讀者可能取不到 ────────
#    刻意不用 ±N 行的視窗：曾經有一行借用了兩行外、針對**另一個路徑**的揭露而
#    假通過——而那正是上一輪具名、本輪宣稱修好卻沒修的那一處。鄰近不等於
#    「這個揭露在講這個路徑」。
undisclosed = []
for fp in files(PLUGIN):
    for i, line in prose_lines(fp):
        # **`trigger-coverage` 的宣告行豁免**（#407 R48）：那條檢查與 `DECLARE`
        # 結構性衝突——DECLARE 要求宣告行在 glob 之後**不得有任何東西**，而本檢查
        # 要求同一行揭露取用限制。一條指向 private repo 路徑的宣告因此**無法同時
        # 滿足兩者**。豁免是對的那一邊：本檢查的目的是「讀者跟著路徑走不會撞上
        # 看不懂的 404」，而宣告行不是給人跟隨的連結，是給 `trigger-coverage.py`
        # 讀的機器宣告。揭露改寫在它**上一行**的註解裡（實地做法）。
        # **豁免要與 DECLARE 逐字同寬**（#407 R49，跨模型審查指名）：上一版只錨行首，
        # 於是 `# trigger-coverage: reads X, 順帶碰 <私有路徑>` 逃得掉揭露檢查卻**不是**
        # 真宣告（DECLARE 要求 glob 之後只能有空白）。謂詞比它要豁免的東西寬——本 issue
        # 反覆記過的形狀，這次出現在**豁免**而不是**檢查**上。
        if re.match(r'^\s*(?:#|//)\s*trigger-coverage:\s*reads\s+(\S+)\s*$', line):
            continue
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
venue_src = VENUE or os.path.join(PLUGIN, '..', 'Sources', 'AkashicCore', 'Venue.swift')
if os.path.isfile(venue_src):
    body = open(venue_src, encoding='utf8', errors='replace').read()
    if 'enum VenueType' not in body:
        # `--venue` 指到一個不含該 enum 的檔（打錯路徑、上游改名）→ 走「未涵蓋」
        # 出口，不是崩潰。前一版直接 `split(...)[1]`，於是拋未捕捉的 IndexError
        # ——而本檔自己寫好的 SKIP 分支就在下面沒被用到（R6 finding 62）。
        print(f'[5] SKIP  {venue_src} 裡找不到 `enum VenueType`——**本項未執行**')
        print()
        print(f'=== {sum(results)}/{len(results)} PASS，但第 5 項未涵蓋 ===')
        sys.exit(2 if all(results) else 1)
    seg = body.split('enum VenueType')[1].split('\n}')[0]
    cases = re.findall(r'^\s+case (\w+)$', seg, re.M)
    n_case = len(cases)
    wrong = []
    for ln, line in enumerate(rule_txt.split('\n'), 1):
        bare = unquoted(line)
        if 'VenueType' not in line and '值域' not in line:
            continue
        for m in re.finditer(r'([一二三四五六七八九十])值', bare):
            if CJK_NUM[m.group(1)] != n_case:
                wrong.append(f'第 {ln} 行宣稱 {m.group(0)}，實測 {n_case}')
    # **也要驗值，不只驗數量**（R6 finding 27）：把一個 case 改名（真缺陷）
    # 做成 mutation，只驗數量的謂詞 5/5 全綠。凡是逐一列出值域的那一行，
    # 列出的每個名字都必須真的存在於 enum 裡。
    for ln, line in enumerate(rule_txt.split('\n'), 1):
        if line.count('`／`') < 2:      # 只看逐一列舉值域的行
            continue
        listed = re.findall(r'`(\w+)`(?=／|）|\)|、|$)', line)
        if len(listed) >= 3:
            for name in listed:
                if name not in cases and name[0].islower():
                    wrong.append(f'第 {ln} 行列出 `{name}`，而 enum 裡沒有這個 case')
    # **也要真的跑規則檔展示的那條指令**（R6 finding 10）。守衛要驗的是「讀者照著
    # 跑會拿到什麼」，不是它自己另算一套。
    #
    # **但絕不執行來自散文的字串。** 上一版寫 `subprocess.run(擷取到的字串,
    # shell=True)`，旁邊註解著「只接受以 awk 開頭的指令，不執行任意擷取到的 shell」
    # ——那句話是假的：regex 只管開頭與結尾，中間的 `;` `|` `$( )` 換行全部放行。
    # 跨模型審查做出 PoC：payload 尾端補一個 `echo 6` 讓輸出等於預期值，守衛報
    # **5/5 PASS、exit 0**，同時以使用者身分執行了注入的指令（R7 兩個 CRITICAL）。
    # 觸發面是同一輪接上的 pre-push hook 與 pull_request workflow，且本樹經公開
    # marketplace 出貨。
    #
    # 現在的作法：指令是**這裡的常數**，規則檔必須逐字展示它，執行的是常數本身、
    # 以參數陣列（shell=False）跑。要驗的性質完全保住，而散文不再有任何執行路徑。
    CANONICAL_CMD = (
        "awk '/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} "
        "END{print n+0}' Sources/AkashicCore/Venue.swift"
    )
    if f'`{CANONICAL_CMD}`' not in rule_txt:
        wrong.append('規則檔展示的計數指令與守衛內建的那條不逐字相同'
                     '（守衛只執行內建的那條——不執行來自散文的字串）')
    # 檔案裡**每一條**同型指令都必須是那一條。安全性質（不執行散文）已由上面的
    # 常數化保證；這一條管的是**散文完整性**：一個讀者可能複製到別的那條。
    # 注入 PoC 的 payload 正是這個形狀——它不再被執行，但它仍是一句假的量測。
    for other in re.findall(r'`(awk\b[^`]*Venue\.swift)`', rule_txt):
        if other != CANONICAL_CMD:
            wrong.append(f'規則檔另外展示了一條同型的計數指令，而它不是 canonical '
                         f'那條：{other[:60]!r}…')
    if f'`{CANONICAL_CMD}`' in rule_txt:
        argv = ['awk',
                '/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} '
                'END{print n+0}',
                venue_src]
        try:
            r = subprocess.run(argv, capture_output=True, text=True, timeout=20)
            got = r.stdout.strip() if r.returncode == 0 else f'(exit {r.returncode})'
        except Exception as e:            # noqa: BLE001 —— 任何失敗都要說出來
            got = f'(執行失敗：{e})'
        if got != str(n_case):
            wrong.append(f'規則檔展示的指令印出 {got!r}，而實測是 {n_case}')

    check(5, f'規則對 VenueType 的數量與值一致，且它展示的指令真的印出該數字'
             f'（實測 {n_case}：{"／".join(cases)}）',
          wrong, [])
else:
    # **未涵蓋不得冒充通過**（本 repo 的 zero-instance-guards 第 3 列）。
    # 前一版在這裡只 print 一行 SKIP，於是 plugin 單獨安裝時輸出「4/4 PASS」
    # 並 exit 0——「沒被檢查」與「檢查過且乾淨」在輸出上完全一樣。
    print(f'[5] SKIP  取不到 Venue.swift（{venue_src}）——**本項未執行**')
    print()
    print(f'=== {sum(results)}/{len(results)} PASS，但第 5 項未涵蓋 ===')
    print('   plugin 單獨安裝時取不到 Akashic repo 的原始碼（該 repo 為 private）。')
    print('   這不是通過：用 --venue <path> 指向 Venue.swift，或在 repo 內跑。')
    sys.exit(2 if all(results) else 1)


# ── [6] 規則檔自我量測表裡「會長的數字」是否還等於當下實測 ────────────────
#
# 那張表是本規則的旗艦論證（「我說的每句話都量過」）。2026-08-22 重量八列，
# **兩列已過期**——parity 26→46、mutation 11→14。過期的正是兩個「會長」的數字：
# 每輪加 fixture 就變，而表格把它們寫得跟「VenueType 是六值」一樣像恆定事實。
#
# 這一項只做**靜態計數**（數 fixture 定義與 mutation 項目），不跑那兩支腳本
# ——parity 需要 swift build、mutation 要數分鐘。實測靜態計數與實跑一致
# （46/46、14/14），而會漂的是計數本身，不是通過率。
PARITY = os.path.join(PLUGIN, 'skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh')
MUTS = os.path.join(PLUGIN, 'skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py')
stale = []
if os.path.exists(PARITY) and os.path.exists(MUTS):
    n_fix = len(re.findall(r'^check ', open(PARITY, encoding='utf8').read(), re.M))
    mt = open(MUTS, encoding='utf8').read()
    mm = re.search(r'MUTATIONS\s*=\s*\[(.*?)\n\]', mt, re.S)
    n_mut = len(re.findall(r'^\s{4}\(', mm.group(1), re.M)) if mm else -1
    if n_mut < 0:
        stale.append('數不到 MUTATIONS 的項目數——抽取式已與宣告寫法脫節')
    # **proxy 的有效前件也要驗**（#407 R20 指名）：`^check ` 只認 column 0。
    # 若有人把一個 check 移進 if／函式區塊，實跑的 fixture 數不變而靜態計數
    # 少一——散文若跟著改成那個錯的數字，這一項會綠而表格已與實際不符。
    # 目前縮排的 check 是 0 個；出現即報，因為那一刻起 proxy 不再成立。
    indented = len(re.findall(r'^\s+check ', open(PARITY, encoding='utf8').read(), re.M))
    if indented:
        stale.append(f'store-marker-parity.sh 有 {indented} 個縮排的 check——'
                     f'靜態計數（只認 column 0）不再等於實跑的 fixture 數，'
                     f'本項的 proxy 前件失效')
    # 表格裡標 ↗ 的那兩列必須帶當下的數字。
    if f'**{n_fix}** 格 fixture' not in rule_txt:
        stale.append(f'自我量測表的 parity 列不是當下的 {n_fix} 格')
    if f'**{n_mut}/{n_mut}**' not in rule_txt:
        stale.append(f'自我量測表的 mutation 列不是當下的 {n_mut}/{n_mut}')
    check(6, f'自我量測表裡會長的數字仍等於實測（parity {n_fix} 格、mutation {n_mut}）',
          stale, [])
else:
    print('[6] SKIP  取不到 parity／mutation 腳本——**本項未執行**')
    print()
    print(f'=== {sum(results)}/{len(results)} PASS，但第 6 項未涵蓋 ===')
    sys.exit(2 if all(results) else 1)

# ── 考慮過但**不加**的檢查：「散文裡的 repo 路徑必須存在」 ────────────────
#
# 憑記憶寫路徑是本 issue 反覆踩到的形狀（#407 R19 的坑 (a)），所以自然會想到
# 「掃散文裡所有 backtick 路徑，不存在就紅」。**實測後裁決不加**：14 個 backtick
# 路徑裡 3 個不存在，而三個全是假陽性，且各有不同的排除理由——
#
#   · `.claude-plugin/plugin.json`     → 相對於 **plugin 根**，不是 repo 根
#   · `.claude-plugin/marketplace.json`→ 是**別的 repo**（marketplace）的路徑
#   · CHANGELOG 裡那個型別原始碼的路徑 → **刻意引述的錯誤路徑**，它必須不存在，
#     那正是該句的內容（這裡不寫出字面——寫出來會觸發本檔第 2 項，而那正是
#     它該做的事：本註解是第三次被自己抓到）
#
# 三個排除規則都需要判斷，機械化必然失真。一個 100% 假陽性的檢查比沒有檢查更糟：
# 它訓練讀者忽略輸出，而下一個真缺陷就混在被忽略的那批裡。
#
# **真正防住那個坑的是別的東西**：trigger-coverage.py 對它的受保護清單逐條驗
# 存在——那份清單是**程式碼**（會被執行），不是散文，所以謂詞可以是精確的。

print()
print(f'=== {sum(results)}/{len(results)} PASS ===')
sys.exit(0 if all(results) else 1)
