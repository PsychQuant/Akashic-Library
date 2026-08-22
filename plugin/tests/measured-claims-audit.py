#!/usr/bin/env python3
"""`assertions-must-be-measured.md` 第 2 題那張四列判準表的現查。

那張表的主題是「一個真的查詢，被用來支撐一個那個查詢沒問的性質」，而它自己的
四列也是四個可否證的宣稱。這支腳本逐列跑出它們的依據。

**第三列刻意不計數**：前三次量它時用了三種計數方式（`grep -c`、全格 `re.findall`、
逐格解析），得到三個不同的答案（#407 R25i）。現在直接列出行號與函式名——
計數是把多個事實壓成一個數字，而壓縮的方式正是出錯的地方；列舉沒有壓縮。

用法：python3 plugin/tests/measured-claims-audit.py
"""
import io, re, subprocess
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout.strip()

print('逐列現查（每列問「我跑的指令，回答的是不是正好這句話」）\n')

# ① 三個 commit 是純新增
print('① 「實測三個是純新增」')
for h in ['41bd3d8', '848939a', '3eda486']:
    d = sh(f"git show {h} --format='' --numstat -- plugin/ | awk '{{d+=$2}} END{{print d+0}}'")
    print(f'     {h} 刪除行數 {d}  {"✓" if d == "0" else "✗"}')

# ② git 的欄位
print('② 「git 證立時序，證立不了有檢查」')
print(f'     commit 欄位：{sh("git log -1 --format=%an|%ae|%ct|%s HEAD")[:60]}…')
print('     → 無 review 欄位 ✓（結構性，不需指令）')

# ③ 那三格全是 warn_case——直接列，不用計數
print('③ 「3 格全是 warn_case（行 209／246／315）」')
src = io.open('plugin/tests/trigger-coverage-mutations.py', encoding='utf8').read().split('\n')
for i, l in enumerate(src, 1):
    if "'一次都沒出現過')" in l:
        fn = next((src[j].strip().split('(')[0] for j in range(i - 2, max(0, i - 14), -1)
                   if src[j].lstrip().startswith(('case(', 'warn_case('))), '?')
        print(f'     行 {i}: {fn}')

# ④ 19 = 13 + 6
print('④ 「19 行 run: ＝ 13 單行 ＋ 6 block」')
tot = sh("grep -hcE '^\\s*(-\\s*)?run:' .github/workflows/*.yml | awk '{s+=$1} END{print s}'")
sg = sh("grep -hE '^\\s*(-\\s*)?run: [^|]' .github/workflows/*.yml | wc -l")
bl = sh("grep -hE '^\\s*(-\\s*)?run: \\|' .github/workflows/*.yml | wc -l")
print(f'     總 {tot}｜單行 {sg}｜block {bl} → {int(sg)+int(bl)}  {"✓" if int(sg)+int(bl) == int(tot) else "✗"}')
