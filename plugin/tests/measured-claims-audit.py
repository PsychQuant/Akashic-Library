#!/usr/bin/env python3
"""`assertions-must-be-measured.md` 第 2 題那張五列判準表的現查。

那張表的主題是「一個真的查詢，被用來支撐一個那個查詢沒問的性質」，而它自己的
五列也是五個可否證的宣稱。這支腳本逐列跑出它們的依據。

**第三列刻意不計數**：前三次量它時用了三種計數方式（`grep -c`、全格 `re.findall`、
逐格解析），得到三個不同的答案（#407 R25i）。現在直接列出行號與函式名——
計數是把多個事實壓成一個數字，而壓縮的方式正是出錯的地方；列舉沒有壓縮。

用法：python3 plugin/tests/measured-claims-audit.py
"""
import io, re, subprocess, sys
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout.strip()

fails = []


def check(ok, msg):
    """**印 ✓／✗ 而永遠 exit 0，與沒有這支腳本對 CI 是同一件事。**

    R26b 出貨的第一版正是那樣（四列全是 print、零個 assert、rc 恆 0）——
    而「驗收套件對它宣稱要檢查的東西是盲的」是本 issue 最早記下的失敗之一
    （見規則檔失敗表）。#407 R26e 由跨模型審查指名。
    """
    if not ok:
        fails.append(msg)
    return '✓' if ok else '✗'




print('逐列現查（每列問「我跑的指令，回答的是不是正好這句話」）\n')

# ① 三個 commit 是純新增
print('① 「實測三個是純新增」')
for h in ['41bd3d8', '848939a', '3eda486']:
    d = sh(f"git show {h} --format='' --numstat -- plugin/ | awk '{{d+=$2}} END{{print d+0}}'")
    print(f'     {h} 刪除行數 {d}  {check(d == "0", f"{h} 不是純新增（刪除 {d} 行）")}')

# ② git 的欄位
print('② 「git 證立時序，證立不了有檢查」')
# **這一列走過三版，前兩版都不可否證**（#407 R26g）：
#   R26b  寫死 `✓`                      → 字串常數
#   R26f  掃 `git log --help` 的 placeholder → placeholder 是 `%an`／`%ct` **縮寫**，
#                                            結構上不可能含 `review` 這個英文字
# 把「寫死」換成「查詢」不等於變成可否證——**那個查詢問的東西必須有可能命中**。
#
# 這一版問 commit **物件本身**的欄位名（`git cat-file -p`），那是 git 物件格式的
# 一部分：`tree` / `parent` / `author` / `committer` / 空行 / message。欄位名是
# **真的單字**，所以 review 類字樣有可能出現——若 git 日後加了那種欄位，這裡會紅。
# **縮寫也要列**（#407 R26i）：`REVIEW_ISH` 原本只有英文單字，而 commit 欄位名裡
# 有縮寫——`gpgsig` 是最接近的一個。這是同一個坑的第三次（R26f 掃 placeholder
# 縮寫找英文單字；R26g 改問欄位名以為解決了，而欄位名裡也有縮寫）。
#
# **但 `gpgsig` 不算**，而理由要寫清楚：它證明**簽署**（這是誰寫的），不證明
# **審查**（有人檢查過內容）。兩者的差別正是第 ② 列的主題。所以它列進 KNOWN
# 而非 REVIEW_ISH——**列進去是為了讓「我看過它並判定它不算」這件事可查**，
# 而不是靠清單漏掉它來蒙混。
REVIEW_ISH = ('review', 'approv', 'signoff', 'sign-off', 'verdict', 'attest')
# 已知且判定「不是審查證據」的欄位（含縮寫）。出現在這裡＝看過、判過。
#
# **清單怎麼來的**（#407 R26l——上一版是憑印象列的，漏了 `gpgsig-sha256`，
# 由跨模型審查指名）：直接從 git binary 的字串常數窮舉，不用猜——
#
#     strings $(command -v git) | grep -oE '^(tree|parent|author|committer|gpgsig[a-z0-9-]*|mergetag|encoding)$' | sort -u
#
# 當次輸出（2026-08-23，`git version 2.55.0` / darwin-arm64）：
#     author
#     committer
#     encoding
#     gpgsig
#     gpgsig-sha256
#     mergetag
#     parent
#     tree
# **下面這張表就是那八個**，一個不多一個不少。**版號寫出來**是因為別的
# git build 可能不同——那時這張表要重新導出，而不是照抄（#407 R26q）。
KNOWN_NOT_REVIEW = {
    'tree': '內容指標', 'parent': '前驅', 'author': '誰寫的', 'committer': '誰提交的',
    'gpgsig': '**簽署**不是審查——它證明身分，不證明有人檢查過內容',
    'gpgsig-sha256': '同 gpgsig，SHA-256 物件格式的 repo 用這個欄位名',
    'mergetag': '被合併的 tag 物件', 'encoding': 'message 的字元編碼',
}
# **多行 header 的續行以空格開頭**（RFC 式折疊）——`gpgsig` 的 PGP 簽章就是那樣。
# 上一版對每一行取 `split()[0]`，於是 signed commit 抽出 **19 個「欄位」**，其中
# 15 個是 base64 片段（#407 R26k，實測 `32ebc301`）。**HEAD 剛好不是 signed
# commit，所以本機全綠**——它在有 GPG 的環境會炸，而那是常態。
header = sh("git cat-file -p HEAD | sed -n '1,/^$/p'")
fields = sorted({l.split()[0] for l in header.split('\n')
                 if l.strip() and not l.startswith(' ')})
hit = [f for f in fields if any(w in f.lower() for w in REVIEW_ISH)]
# trailer 是第二個可能的載體（commit message 尾註）。
#
# **只問 review 類 token，不是「有沒有 trailer」**（2026-08-24，#407 後續）。上一版
# 斷言 HEAD **完全沒有** trailer，而那個前提是「HEAD 不會是 GitHub 的 merge commit」
# ——它從來沒被寫下來，也從來沒被測過，因為 pre-push 永遠在 merge **之前**跑
# （merge 發生在 GitHub 端），所以 HEAD 從來不是 merge commit。
#
# GitHub 的 merge commit body 會回音 PR 的 commit 標題：
#
#     Merge pull request #405 from PsychQuant/idd/pages-shape-guard
#
#     feat: pages 欄位的形狀守衛——三筆實測缺陷裡有兩筆完全不會出聲
#
# 而 `feat: …` 正好符合 git 的 trailer 文法（`token: value`），於是 `%(trailers)`
# 把它當 trailer 回報。**實測最近 20 個 merge commit 有 11 個會踩到這一格。**
#
# 這是假陽性：本列的宣稱是「git 沒有出現 **review 類**載體」，而一個
# conventional-commit 標題不是那個東西。修法不是把 merge commit 整格跳過（那會製造
# 盲點——真的 `Reviewed-by:` 掛在 merge commit 上就抓不到了），是**讓 trailer 與
# header 問同一個問題**：token 是不是 review 類。兩邊共用 `REVIEW_ISH`，於是這裡
# 不會再長出第二套判準。
def _review_ish_trailers(raw):
    """從 `%(trailers)` 的輸出取出 review 類的 token。空回傳＝乾淨。"""
    out = []
    for line in raw.split('\n'):
        if ':' not in line:
            continue
        token = line.split(':', 1)[0].strip().lower()
        if any(w in token for w in REVIEW_ISH):
            out.append(line.strip())
    return out


_trailers_raw = sh("git log -1 --format='%(trailers)' HEAD").strip()
trailers = _review_ish_trailers(_trailers_raw)
unknown = [f for f in fields if f not in KNOWN_NOT_REVIEW]
# **不只驗 HEAD**：HEAD 剛好不是 signed commit 時，續行的坑看不出來（R26k）。
# 本 repo 有 signed commit（GitHub 的 web merge），所以順帶對第一個 signed
# commit 跑同一個抽取式——**兩種形狀都要對，才叫這個檢查有意義**。
# **偵測式要錨定在 header 且錨定行首**（#407 R26o，自己撞到）：
# 上一版寫 `head -6 | grep -q gpgsig`，兩個錯——(a) header 只有 4–5 行，
# `head -6` 會越過空行進入 **message**；(b) `grep -q` 不錨行首，message 裡
# 提到那個字就命中。於是它抓到了 **R26l 那個 commit**（標題正是「漏了
# gpgsig-sha256」）——**我寫的那句話讓偵測式抓到了它自己**。
# 正解：只看 header（`sed '/^$/q'`）並錨定行首（`^gpgsig`）。
#
# **`^gpgsig` 是前綴，所以 SHA-256 repo 的 `gpgsig-sha256` 也會被抓到**——那不是
# 巧合而是 grep 的自然行為，但日後有人「修正」成 `^gpgsig `（加空格）就會漏掉那種
# repo。上一版只把這句寫成註解（#407 R26r），**而註解不會在它變假時發出聲音**
# ——現在改成出貨的斷言（#407 R26s，DA 席指名）。
# **不經 shell**（#407 R26s 當場踩到）：上一版用 `printf … | grep -c`，而 `\n` 的
# 展開取決於**轉義層數**——出貨腳本裡碰巧展成兩行（印 2／1 通過），我的獨立驗證
# 腳本用了不同轉義卻得到 1／1。**斷言通過，但通過的理由不是我寫的理由。**
# Python 的 `re` 沒有轉義層，直接做。
_LINES = ['gpgsig -----BEGIN', 'gpgsig-sha256 -----BEGIN']
# **pattern 只有一份**（#407 R26u，DA 席指名）：上一版的 fixture 自己寫了
# `re.match(r'^gpgsig', …)`，而真偵測式用的是 shell 的 `grep -q '^gpgsig'`
# ——**兩份獨立的 pattern**。有人把偵測式改成 `^gpgsig ` 時，fixture 那格照樣綠：
# **斷言存在，但它守的不是被守的那個東西**（本 repo 反覆記過的「一份規格的兩個
# 副本必然分岔」）。現在從本檔原始碼抽出偵測式實際用的 regex 再跑 fixture。
# **抽取要排除註解，並要求恰好一處**（#407 R26x，DA 席指名）：上一版用
# `re.search`（取第一個命中），而檔案裡有**兩處**符合——行 116 的**註解**與
# 真偵測式。目前兩者字面相同所以看起來正確，但有人改壞偵測式而註解沒跟著改時，
# 斷言仍讀註解、仍然綠——**與 R26u 修掉的「兩份 pattern」同病，只是這次其中
# 一份在註解裡**。現在先剝註解行，再要求命中恰好一處（多於一處＝又有副本了）。
_SRC_CODE = '\n'.join(l for l in io.open(__file__, encoding='utf8')
                      if not l.lstrip().startswith('#'))
_ms = re.findall(r"grep -q '(\^gpgsig[^']*)'", _SRC_CODE)
_pat = _ms[0] if len(_ms) == 1 else None
_hit_prefix = sum(1 for l in _LINES if _pat and re.match(_pat, l))
print(f'     偵測式實際用的 pattern：{_pat!r}（從原始碼抽出，非另寫一份）')
print(f'     它對 gpgsig／gpgsig-sha256 命中 {_hit_prefix}／2  '
      f'{check(_pat is not None and _hit_prefix == 2, f"抽出 {len(_ms)} 個 pattern（須恰好 1）或它只命中 {_hit_prefix}／2——SHA-256 repo 會被漏掉")}')
signed = sh("git rev-list --all | while read h; do "
            "git cat-file -p $h | sed '/^$/q' | grep -q '^gpgsig' "
            "&& echo $h && break; done")
if signed:
    sh_hdr = sh(f"git cat-file -p {signed} | sed -n '1,/^$/p'")
    sf = sorted({l.split()[0] for l in sh_hdr.split('\n')
                 if l.strip() and not l.startswith(' ')})
    su = [f for f in sf if f not in KNOWN_NOT_REVIEW]
    print(f'     signed commit {signed[:8]} 的欄位：{sf}  '
          f'{check(not su, f"signed commit 抽出未判定欄位：{su[:3]}")}')
else:
    # **靜默是最糟的形式**（本 repo 的 lossless-intake 執行細節 3）。找不到
    # signed commit 時整段跳過而不出聲，會讓「這個形狀沒被測」與「測過且乾淨」
    # 在輸出上長得一樣——而這正是 R26k 的修法要驗的那個形狀（#407 R26q）。
    # 淺 clone（CI 常見的 `fetch-depth: 1`）也會走到這裡。
    print('     ⚠ 找不到 signed commit——**本形狀未測**（淺 clone？）。'
          'mergetag fixture 仍會跑，但真實 gpgsig 續行沒有被驗證')
# **本 repo 沒有 mergetag 的 commit，所以那個形狀用構造的測**（#407 R26o）。
# git 合併一個 signed tag 時，會把**整個 tag 物件**內嵌成 mergetag 的續行——
# 其中有 `type`／`tag`／`tagger` 這些看起來像欄位名的行。舊抽取式對它抽出
# **7 個未判定欄位**；濾掉續行之後是 0。
MERGETAG_FIXTURE = (
    'tree abc\nparent def\nparent 123\nauthor X <x@y> 1 +0000\n'
    'committer X <x@y> 1 +0000\nmergetag object 456\n type commit\n tag v1.0\n'
    ' tagger X <x@y> 1 +0000\n \n Release v1.0\n -----BEGIN PGP SIGNATURE-----\n'
    ' iQEcBAAB\n -----END PGP SIGNATURE-----')
mt_fields = sorted({l.split()[0] for l in MERGETAG_FIXTURE.split('\n')
                    if l.strip() and not l.startswith(' ')})
mt_unknown = [f for f in mt_fields if f not in KNOWN_NOT_REVIEW]
print(f'     mergetag fixture（構造，本 repo 無實例）：{mt_fields}  '
      f'{check(not mt_unknown, f"mergetag 續行沒被濾掉：{mt_unknown[:3]}")}')
# **回歸 fixture：merge commit 的 body 回音 vs 真的 review trailer**（2026-08-24）。
# 兩個方向都要釘——只釘「不誤報」會讓人把整個檢查改成 `return []` 也照樣綠。
_MERGE_BODY_TRAILER = 'feat: pages 欄位的形狀守衛——三筆實測缺陷裡有兩筆完全不會出聲'
_REAL_REVIEW_TRAILER = 'Reviewed-by: Someone <s@example.com>'
_fp = _review_ish_trailers(_MERGE_BODY_TRAILER)
_tp = _review_ish_trailers(_REAL_REVIEW_TRAILER)
print(f'     merge-body 回音不誤報：{_fp or "無"}  '
      f'{check(not _fp, f"conventional-commit 標題被當成 review 載體：{_fp}")}')
print(f'     真的 review trailer 仍抓得到：{_tp}  '
      f'{check(len(_tp) == 1, "Reviewed-by 沒被抓到——檢查被改壞成永遠回空")}')
print(f'     commit 物件的欄位：{fields}')
print(f'     其中 review 類：{hit or "無"}｜未判定過的欄位：{unknown or "無"}｜'
      f'HEAD 的 review 類 trailer：{trailers or "無"}'
      f'（原始 trailer：{_trailers_raw.replace(chr(10), " / ") or "無"}）')
# **訊息先算好，不要塞進 f-string 的巢狀引號＋跨行運算式**——那是 PEP 701（Python
# 3.12+）才允許的寫法，而 pre-push 與 CI 拿到的 `python3` 未必是 3.12：本機 PATH 上
# 是 3.13，系統的 `/usr/bin/python3` 是 **3.9**，在後者這一段直接 SyntaxError、整支
# 守衛跑不起來（#407 R40，由 `PrePushHookTests` 的受限 PATH 抓到）。
_msg = f'git 出現了 review 類載體或未判定過的欄位：{hit}／{trailers}／{unknown}'
print(f'     {check(not hit and not trailers and not unknown, _msg)}')

# ③ 那三格全是 warn_case——直接列，不用計數
print('③ 「3 格全是 warn_case（行 209／246／315）」')
src = io.open('plugin/tests/trigger-coverage-mutations.py', encoding='utf8').read().split('\n')
for i, l in enumerate(src, 1):
    if "'一次都沒出現過')" in l:
        fn = next((src[j].strip().split('(')[0] for j in range(i - 2, max(0, i - 14), -1)
                   if src[j].lstrip().startswith(('case(', 'warn_case('))), '?')
        print(f'     行 {i}: {fn}  {check(fn == "warn_case", f"行 {i} 是 {fn}，不是 warn_case")}')

# ④ 19 = 13 + 6
print('④ 「run: 的分類：總數 ＝ 單行 ＋ block」')
print('     刻意不寫死 19／13——R26b 加一個 CI 步驟就變 20／14；驗的是恆等式')
tot = sh("grep -hcE '^\\s*(-\\s*)?run:' .github/workflows/*.yml | awk '{s+=$1} END{print s}'")
sg = sh("grep -hE '^\\s*(-\\s*)?run: [^|]' .github/workflows/*.yml | wc -l")
bl = sh("grep -hE '^\\s*(-\\s*)?run: \\|' .github/workflows/*.yml | wc -l")
print(f'     總 {tot}｜單行 {sg}｜block {bl} → {int(sg)+int(bl)}  '
      f'{check(int(sg)+int(bl) == int(tot), f"總數 {tot} ≠ 單行 {sg} + block {bl}")}')


print()
# ⑤ 時態（#394 verify R8）
print('⑤ 「差的是時態，不是內容」')
# 前四列的形狀是「查詢問的不是那個性質」;這一列的查詢問的**正是**那個性質,
# 只是它還沒回答完。所以現查方式也不同——不是重跑一個 grep,而是確認這一列
# **有沒有被人悄悄刪掉或改寫成不可否證的形式**。
#
# **刻意不寫死那個 SHA**：寫死的話,它終於推上去之後這裡就永遠綠,而那正好讓這一列
# 失去意義（本檔第 ② 列走過同一條路:R26b 寫死 `✓`、R26f 換成一個結構上不可能命中的
# 查詢,兩版都不可否證）。
_rule = open('plugin/rules/assertions-must-be-measured.md', encoding='utf8').read()
_r5 = [l for l in _rule.split('\n') if 'No commit found' in l and l.startswith('|')]
print(f'     第 5 列在場且恰一列：{len(_r5)} '
      f'{check(len(_r5) == 1, "第 5 列不見了或重複")}')
# 那一列必須同時具名「時態」與一個**可否證的觀察**（422／No commit found）,
# 否則它會退化成一句感想。
_ok5 = len(_r5) == 1 and '時態' in _r5[0] and '422' in _r5[0]
print(f'     它具名了時態與可否證的觀察：'
      f'{check(_ok5, "第 5 列被改寫成沒有可否證觀察的形式——那會讓它退化成感想")}')
# 表頭宣稱的列數必須與**那一張表**的實際列數一致（本檔記過的計數分岔形狀）。
# **範圍要收在那張表上**——第一版掃全檔所有表格得到 47，那是在量別的東西。
_lines = _rule.split('\n')
_start = next(i for i, l in enumerate(_lines) if l.startswith('| 我跑的 |'))
_n = 0
for l in _lines[_start + 2:]:              # +2 跳過表頭與分隔列
    if not l.startswith('|'):
        break
    _n += 1
_hdr = [l for l in _lines if '都不是假指令' in l]
_words = {3: '三個', 4: '四個', 5: '五個', 6: '六個', 7: '七個'}
# **那一句裡有兩個計數詞**（「N 個都不是假指令，N 個都不是假數字」），所以用 `in`
# 檢查會被另一個的存在救起來——負控實測:只改前半,`in` 照樣命中而守衛不紅。
# 改成**抽出全部計數詞、要求每一個都對**。
import re as _re
_cnts = _re.findall(r'([一二三四五六七八九十]個)都不是', _hdr[0]) if len(_hdr) == 1 else []
_want = _words.get(_n)
print(f'     散文計數與表一致：表 {_n} 列，散文說 {_cnts or "?"} '
      f'{check(bool(_cnts) and all(c == _want for c in _cnts),
               f"散文的計數詞 {_cnts} 與實際 {_n} 列不符")}')



if fails:
    print(f'══ {len(fails)} 個宣稱不成立 ══')
    for m in fails:
        print(f'  ✗ {m}')
    sys.exit(1)
print('══ 五列全部現查成立 ══')
