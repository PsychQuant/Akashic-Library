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
    """剝掉整行註解與行尾註解（坑 3）。

    **`.swift` 的行尾 `//` 先前不剝**，而這句 docstring 說剝——一句沒被量測過
    的斷言，出現在一支為了防那件事而寫的腳本裡（#407 R20 跨模型審查指名）。
    量測顯示當下零實例（兩支 .swift 的行尾註解都不含受保護檔名），但成本是
    一個分支，而「零實例、成本一行、前件精確」在本 repo 的 zero-instance-guards
    第 1 列是「寫」。
    """
    out = []
    for line in io.open(path, encoding='utf8', errors='replace'):
        s = line.lstrip()
        if s.startswith('#') or s.startswith('//'):
            continue
        if path.endswith(('.sh', '.py')):
            line = line.split(' # ')[0]
        elif path.endswith('.swift'):
            line = line.split(' // ')[0]
        out.append(line)
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


def invoked(text):
    """workflow 裡**真的被執行**的腳本檔名。

    判準是**命令位置**，不是同一行出現。上一版寫
    `re.findall(r'run:.*?([\\w./-]+\\.(?:sh|py|swift))', text)`——它匹配
    `run:` 之後同一行的任何檔名，於是

        run: echo "見 plugin/tests/rule-coverage.sh 的說明"

    會讓 `rule-coverage.sh` 被算成「這個 workflow 執行了它」。實測（#407 R20）：
    把一個真的 run 步驟換成上面那行 echo，守衛照樣報綠。

    現在只認直譯器後面緊跟的那一個引數（`bash X` / `python3 X` / `swift X`）
    與直接執行（`./X`）。**這仍是啟發式**——一個包在 shell 變數或多行 `run: |`
    裡的呼叫會被漏掉（方向是漏報，比誤報安全），而漏報會讓守衛紅、不會讓它假綠。
    """
    found = set()
    blocks = []
    chained = []
    for line in text.split('\n'):
        m = re.match(r'\s*(?:-\s*)?run:\s*(.+)$', line)
        if not m:
            continue
        cmd = m.group(1).strip()
        if cmd == '|' or cmd.startswith('|'):
            blocks.append(line)          # block scalar——見下方揭露
            continue
        # **只認第一個 token。** 上一版對 `./X` 分支仍掃全行，於是
        # `run: echo "見 ./rule-coverage.sh"` 照樣被算成執行了它——同一個修法
        # 只修了直譯器那半邊（#407 R20c，跨模型審查指名；今天第二次同型：
        # code_only() 先前也只用在 READS 不用在 HOOK）。
        # 代價是 `cd A && bash X` 這種會漏——**方向是漏報**，讓守衛紅而非假綠。
        toks = cmd.split()
        if not toks:
            continue
        head = toks[0]
        # **串接偵測不看 head。** 上一版要求 head 不是直譯器，於是
        # `bash A && bash B` 短路成 False——B 既不進 found（只認 toks[1]＝A）
        # 也不進 chained，**零可見度**；而 `cd A && bash B`（head 不是直譯器）
        # 至少會被揭露。同一個缺口因為 head 的形式不同而有無揭露，是不對稱
        # 的假保證（#407 R21，跨模型審查指名）。
        # 判準改為：這一行含 && 或 ;，而且它提到的腳本檔名多於我們認出來的
        # 那一個——那就有東西被漏掉。
        named = re.findall(r'\S+\.(?:sh|py|swift)\b', cmd)
        recognised = 1 if (head in ('bash', 'sh', 'python3', 'python', 'swift')
                           and len(toks) > 1
                           and toks[1].endswith(('.sh', '.py', '.swift'))) \
            or head.startswith('./') else 0
        if re.search(r'&&|;', cmd) and len(named) > recognised:
            chained.append(cmd)
        if head in ('bash', 'sh', 'python3', 'python', 'swift') and len(toks) > 1 \
                and toks[1].endswith(('.sh', '.py', '.swift')):
            found.add(os.path.basename(toks[1]))
        elif head.startswith('./') and head.endswith(('.sh', '.py', '.swift')):
            found.add(os.path.basename(head))
    if chained:
        # `cd A && bash X` 這類串接：第一個 token 不是直譯器，所以認不出來。
        # **方向是漏報**（守衛會紅、不會假綠），但仍要印——R20c 才立下的原則是
        # 「寫在註解裡的已知限制，對讀輸出的人等於沒人知道」（#407 R20e）。
        print(f'   ℹ 有 {len(chained)} 個串接式 run（含 && 或 ; 且提到守衛檔名），'
              f'本函式只認第一個 token——那些呼叫看不到（漏報，會讓守衛紅）')
    if blocks:
        # 多行 `run: |` 的實際命令在**續行**上，本函式看不到（#407 R20c）。
        # 不靜默：印出來。目前用它的只有 ci.yml，而 ci.yml 的 paths-ignore
        # 排除 plugin/**、也不跑這些守衛——所以當下不影響，但那是巧合不是設計。
        print(f'   ℹ 有 {len(blocks)} 個 `run: |` 區塊，本函式只讀單行形式——'
              f'若守衛改用區塊形式呼叫，這裡會看不到它（漏報，會讓守衛紅）')
    return found


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
# **這是啟發式，而它的失敗方向是漏報**（#407 R20 指名）：一個把路徑組出來的
# 守衛（`DIR + 'literal' + '-census.sh'`、環境變數、glob）不會讓 basename 逐字
# 出現，於是那條依賴**整個不被考慮**——不報缺口、不印任何東西。靜態分析救不了
# 這件事（要執行才知道），所以改為把它**攤開來**：下面印出每個守衛被判定讀了
# 什麼，讓漏掉的那條在人眼前缺席，而不是在沉默裡缺席。
# **整行就是宣告**——行首是註解標記、行尾沒有別的東西。
#
# 上一版是裸的 `trigger-coverage:\s*reads\s+(\S+)`，它認不出「這是宣告」與
# 「這是在談論宣告」：一個把該字面寫進**字串**（測試描述、錯誤訊息模板）或
# docstring 說明的檔案，都會被算成有宣告。實測（#407 R21）：先修 docstring、
# 再排除實作者自己，然後 harness 又因為 case 描述裡的字面被命中——**特例排除
# 追不上，因為每個談論它的地方都會再撞一次**。收窄謂詞才是根治。
DECLARE = re.compile(r'^\s*(?:#|//)\s*trigger-coverage:\s*reads\s+(\S+)\s*$')


def declared(path):
    """守衛可以顯式宣告它讀什麼，補上啟發式看不見的依賴。

    寫法（放在守衛自己的註解裡，這一行**刻意不剝**）：

        #<空白>trigger-coverage:<空白>reads<空白><glob>

    **上面那行刻意寫成佔位形式，不是排版潔癖**：本檔的 DECLARE regex 認不出
    「這是宣告」與「這是在說明宣告怎麼寫」。先前這裡寫的是可直接匹配的字面，
    於是本檔自己被當成有宣告——一份文件因為**描述**了某個語法而被當成**使用**
    了它（#407 R21）。目前不出錯只因為 declared() 用同一個 regex、兩邊一致；
    一旦那個範例的 glob 不匹配任何受保護檔，「有宣告就必須解析得到」那條斷言
    會對一份根本沒宣告的檔案報紅。真實用例見 rule-coverage.sh。

    存在的理由是一個實測到的漏報：`rule-coverage.sh` 用 glob `"$RULES"/*.md`
    定位規則檔，從不寫出任何 basename，於是啟發式把它判成「只讀自己」——
    而它的整個職責就是驗那些規則檔（#407 R20，由攤開表讓它現形）。

    **這裡刻意讀 raw file，不經 `code_only()`——那不是漏改，是必要的。**
    宣告只能寫在註解裡（寫在程式碼裡它就會被執行），所以讀宣告必須看得到註解；
    而 `code_only()` 服務的是另一個判定（「這個 basename 是真的被讀，還是只是
    在註解裡被提到」），那裡剝註解才對。兩個函式對註解的態度相反是設計，
    把它們「統一」會讓宣告機制整個失效。
    """
    out = set()
    for line in io.open(path, encoding='utf8', errors='replace'):
        m = DECLARE.search(line)
        if m:
            out |= {f for f in PROTECTED if fnmatch.fnmatch(f, m.group(1))}
    return out


READS = {g: ({g} | declared(g)
             | {f for f in PROTECTED if os.path.basename(f) in code_only(g)})
         for g in GUARDS}

WORKFLOWS = {}
for y in sorted(glob.glob('.github/workflows/*.yml')):
    text = io.open(y, encoding='utf8').read()
    WORKFLOWS[os.path.basename(y)] = (yaml_paths(y), invoked(text))

# **也要剝註解。** 上一版這裡讀 raw text，而 code_only() 就在同一個檔案裡、
# 正是為了修「坑 3」而寫的——READS 用了它，這裡沒用。**修了一半。** 實測
# （#407 R20）：把一支守衛從 pre-push 拿掉、只留一行 `# TODO: 之後再接 …`，
# 守衛照樣報「涵蓋 N/N」。同型缺陷成對出現而只修先被看見的那個，是本 repo
# 的 no-compat-fallback 記過的形狀。
HOOK = code_only('.githooks/pre-push') if os.path.exists('.githooks/pre-push') else ''

print(f'守衛 {len(GUARDS)} 支｜受保護 {len(PROTECTED)} 個｜'
      f'workflow {len(WORKFLOWS)} 份\n')

# **有宣告就必須解析得到。** 若有人把 declared() 「統一」成走 code_only()，
# 宣告行（是註解）會被剝掉、機制整個失效——而守衛**不會紅**：它只是少考慮
# 幾個 pair，沉默地。所以在這裡把它變成會紅的（#407 R20b）。
# **`realpath` 不是 `abspath`。** macOS 的 tempdir 是 `/var/folders/…`，而
# `/var` 是 `/private/var` 的 symlink——`__file__` 保留 `/var`，`os.chdir` 之後
# 的 cwd 卻已解析成 `/private/var`，於是 abspath 兩邊永遠不相等，自指排除在
# mutation 環境下靜默失效（實測 8 格掉到 2 格，#407 R21）。
# **這裡曾有一段自指排除，已退場（#407 R21）。** 當時 DECLARE 是裸子串，
# 於是本檔（機制的實作者）因為錯誤訊息模板裡的字面被算成「有宣告」。加特例
# 排除之後，harness 又因為 case 描述裡的字面撞上同一件事——**特例追不上，
# 因為每個談論它的地方都會再撞一次**。收窄 DECLARE 為「整行就是宣告」才是
# 根治，而根治之後特例就該刪（no-compat-fallback 的退場即刪）：留著它會看
# 起來像在保護什麼。實測拿掉後仍全綠。
for g in GUARDS:
    raw = io.open(g, encoding='utf8', errors='replace').read()
    # **用同一個謂詞。** 裸子串會把「談論宣告」算成「有宣告」——那正是上面
    # DECLARE 收窄要解決的事，而存在性檢查若還用舊謂詞，兩者就會分岔。
    has_decl = any(DECLARE.match(line) for line in raw.split('\n'))
    if has_decl and not declared(g):
        fails.append(f'{os.path.basename(g)} 有 `# trigger-coverage: reads` 宣告，'
                     f'但 declared() 解析不到任何受保護檔——宣告機制失效了')
    # **「解析得到」不等於「解析到對的東西」**（#407 R21，DA 席指名）：
    # `reads *` 或 `reads *.sh` 幾乎保證命中一堆守衛，斷言通過而宣告文不對題
    # ——那比宣告落空更難發現，因為覆蓋表會印出一個看似合理的讀取關係。
    # 這裡不猜「對的東西」是什麼（那要人判斷），只擋掉明顯過寬的：一個宣告
    # 命中超過受保護檔的一半，它就不是在指認依賴，是在描述整個 repo。
    hits = declared(g)
    if len(hits) > len(PROTECTED) // 2:
        fails.append(f'{os.path.basename(g)} 的 `trigger-coverage: reads` 宣告命中 '
                     f'{len(hits)}/{len(PROTECTED)} 個受保護檔——過寬的 glob 不是'
                     f'宣告依賴，是在描述整個 repo；請指名到具體路徑或目錄')

print('每支守衛被判定讀了哪些受保護檔（啟發式，漏報方向——見 READS 上方註解）：')
for g in GUARDS:
    others = sorted(os.path.basename(x) for x in READS[g] if x != g)
    print(f'   {os.path.basename(g):<32} → {"、".join(others) if others else "（只有自己）"}')
print()

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
