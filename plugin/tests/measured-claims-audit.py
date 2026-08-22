#!/usr/bin/env python3
"""`assertions-must-be-measured.md` 第 2 題那張四列判準表的現查。

那張表的主題是「一個真的查詢，被用來支撐一個那個查詢沒問的性質」，而它自己的
四列也是四個可否證的宣稱。這支腳本逐列跑出它們的依據。

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
trailers = sh("git log -1 --format='%(trailers)' HEAD").strip()
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
print(f'     commit 物件的欄位：{fields}')
print(f'     其中 review 類：{hit or "無"}｜未判定過的欄位：{unknown or "無"}｜'
      f'HEAD 的 trailer：{trailers or "無"}')
print(f'     {check(not hit and not trailers and not unknown, "git 出現了 review 類載體或未判定過的欄位："
                    f"{hit}／{trailers}／{unknown}")}')

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
if fails:
    print(f'══ {len(fails)} 個宣稱不成立 ══')
    for m in fails:
        print(f'  ✗ {m}')
    sys.exit(1)
print('══ 四列全部現查成立 ══')
