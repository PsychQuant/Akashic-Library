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
KNOWN_NOT_REVIEW = {
    'tree': '內容指標', 'parent': '前驅', 'author': '誰寫的', 'committer': '誰提交的',
    'gpgsig': '**簽署**不是審查——它證明身分，不證明有人檢查過內容',
    'mergetag': '被合併的 tag 物件', 'encoding': 'message 的字元編碼',
}
header = sh("git cat-file -p HEAD | sed -n '1,/^$/p'")
fields = sorted({l.split()[0] for l in header.split('\n') if l.strip()})
hit = [f for f in fields if any(w in f.lower() for w in REVIEW_ISH)]
# trailer 是第二個可能的載體（commit message 尾註）。
trailers = sh("git log -1 --format='%(trailers)' HEAD").strip()
unknown = [f for f in fields if f not in KNOWN_NOT_REVIEW]
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
