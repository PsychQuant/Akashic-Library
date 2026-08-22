#!/usr/bin/env python3
"""每個受保護的檔案，改動時真的會有讀它的守衛跑起來嗎？

為什麼存在
==========
`CLAUDE.md` 有一張手寫的觸發點表。手寫的表會與現實分岔，而分岔是安靜的——
這條 issue 已經記過三次同形狀（硬編的支數、硬編的計數、兩份必要欄位表）。

而這裡要驗的性質**不是聯集**。`census-parity.yml` 自己的檔頭寫著：

  > 兩個檔案的註解都寫「兩者合起來涵蓋五支」。那句話在「檔案集合的聯集」意義上
  > 成立，在「任一次變更」意義上不成立——而後者才是觸發點要保證的事。

所以判準是逐對的：對每個受保護檔案 f、每個讀 f 的守衛 g，必須存在一個 workflow
同時 (a) 在 f 改動時觸發、(b) 執行 g。

三個踩過的坑（都在寫這支腳本的當天，#407 R19）
================================================
1. **憑記憶寫路徑**：受保護清單裡寫了 `Sources/AkashicCore/StoreVersion.swift`，
   真實位置是 `Sources/AkashicStoreIO/`。現在每條路徑先驗存在，不存在即失敗——
   一個指不到東西的守衛比沒有守衛更糟，它讓人以為覆蓋過了。
2. **regex 漏掉 YAML anchor**：`paths: &parity_paths` 不匹配 `paths:$`，於是對
   census-parity.yml 回報 0 條觸發路徑，而它明明有 4 條。
3. **「讀取」的謂詞太寬**：拿整個檔案比 basename，於是「註解裡提到姊妹 harness」
   被算成「讀取它」，報出兩個不存在的缺口。現在先剝註解行。

用法
====
  python3 plugin/tests/trigger-coverage.py          # 全綠 exit 0
  python3 plugin/tests/trigger-coverage.py --root X # 指向一份 copy（負控用）
"""
import fnmatch
import glob
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
for i, a in enumerate(sys.argv):
    if a == '--root' and i + 1 < len(sys.argv):
        ROOT = os.path.abspath(sys.argv[i + 1])
os.chdir(ROOT)

# 生成器不是守衛——它由 hash-table-drift.sh 呼叫，自己不做斷言。
GENERATORS = {'derive-hash-extenders.swift'}

GUARDS = [g for g in sorted(
    glob.glob('plugin/tests/*.sh') + glob.glob('plugin/tests/*.py')
    + glob.glob('plugin/skills/*/scripts/tests/*.sh')
    + glob.glob('plugin/skills/*/scripts/tests/*.py')
    + glob.glob('plugin/skills/*/scripts/tests/*.swift'))
    if os.path.basename(g) not in GENERATORS]

# 守衛之外，還被守衛讀的東西。**每一條都必須存在**（坑 1）。
DATA = [
    'plugin/skills/akashic-literal-campaign/scripts/literal-census.sh',
    'plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt',
    'plugin/skills/akashic-literal-campaign/scripts/tests/derive-hash-extenders.swift',
    'plugin/rules/assertions-must-be-measured.md',
    'Sources/AkashicStoreIO/StoreVersion.swift',
    'Sources/AkashicCore/Venue.swift',
]

fails = []


def code_only(path):
    """剝掉整行註解與行尾註解（坑 3）。"""
    out = []
    for line in io.open(path, encoding='utf8', errors='replace'):
        s = line.lstrip()
        if s.startswith('#') or s.startswith('//'):
            continue
        out.append(line.split(' # ')[0] if path.endswith(('.sh', '.py')) else line)
    return '\n'.join(out)


def yaml_paths(yml):
    """`paths:` / `paths-ignore:` 底下的清單。anchor 形式也要認（坑 2）。"""
    text = io.open(yml, encoding='utf8').read()
    got = {}
    for key in ('paths', 'paths-ignore'):
        m = re.search(rf'^\s*{key}:\s*(?:&\w+)?\s*$((?:\n\s*(?:#.*|-.*))+)', text, re.M)
        got[key] = ([x.strip().strip('"') for x in
                     re.findall(r'^\s*-\s*(.+)$', m.group(1), re.M)] if m else [])
    return got


def matches(patterns, f):
    return any(fnmatch.fnmatch(f, p) or (p.endswith('/**') and f.startswith(p[:-2]))
               for p in patterns)


# ── 前置：清單自己不得含不存在的路徑 ────────────────────────────────
missing = [p for p in GUARDS + DATA if not os.path.exists(p)]
if missing:
    print('✗ 受保護清單裡有不存在的路徑（守衛指不到東西比沒有守衛更糟）：')
    for p in missing:
        print(f'    · {p}')
    sys.exit(1)

PROTECTED = sorted(set(GUARDS + DATA))
READS = {g: {g} | {f for f in PROTECTED if os.path.basename(f) in code_only(g)}
         for g in GUARDS}

WORKFLOWS = {}
for y in sorted(glob.glob('.github/workflows/*.yml')):
    text = io.open(y, encoding='utf8').read()
    WORKFLOWS[os.path.basename(y)] = (
        yaml_paths(y),
        set(os.path.basename(x) for x in
            re.findall(r'run:.*?([\w./-]+\.(?:sh|py|swift))', text)))

HOOK = io.open('.githooks/pre-push', encoding='utf8').read() \
    if os.path.exists('.githooks/pre-push') else ''

print(f'守衛 {len(GUARDS)} 支｜受保護 {len(PROTECTED)} 個｜'
      f'workflow {len(WORKFLOWS)} 份\n')

for f in PROTECTED:
    readers = [g for g in GUARDS if f in READS[g]]
    if not readers:
        continue
    covered = []
    for name, (paths, runs) in WORKFLOWS.items():
        if not paths['paths'] or not matches(paths['paths'], f):
            continue
        if matches(paths['paths-ignore'], f):
            continue
        covered += [g for g in readers if os.path.basename(g) in runs]
    gap = [g for g in readers if g not in covered]
    print(f'{"✓" if not gap else "✗"} {os.path.basename(f):<34} '
          f'讀它的守衛 {len(readers)}｜CI 未覆蓋 {len(gap)}')
    for g in gap:
        where = 'pre-push 有' if os.path.basename(g) in HOOK else 'pre-push 也沒有'
        fails.append(f'改 {os.path.basename(f)} 時 {os.path.basename(g)} '
                     f'不在任何 CI workflow 跑（{where}）')

# pre-push 是唯一目前真的會跑的路徑（CLAUDE.md 的觸發點表有量測），
# 所以它必須涵蓋全部守衛——這一條與上面的逐對檢查是不同的性質。
uncovered_hook = [g for g in GUARDS if os.path.basename(g) not in HOOK]
print(f'\n{"✓" if not uncovered_hook else "✗"} pre-push 涵蓋 '
      f'{len(GUARDS) - len(uncovered_hook)}/{len(GUARDS)} 支守衛')
for g in uncovered_hook:
    fails.append(f'{os.path.basename(g)} 不在 pre-push 裡')

if fails:
    print(f'\n══ 缺口 {len(fails)} ══')
    for m in fails:
        print(f'  · {m}')
    sys.exit(1)
print('\n══ 觸發點覆蓋無缺口（逐對意義，非聯集）══')
