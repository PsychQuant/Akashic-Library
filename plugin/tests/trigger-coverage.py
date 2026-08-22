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
import shlex
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
# **警告與缺口分開。** 警告是「請人看一眼」，缺口是「這裡壞了」——把兩者
# 混在同一個出口，會讓人對整份輸出一起打折扣（#407 R24，DA 席的 cry-wolf
# 論證在痕跡檢查上的同型應用）。
warnings = []


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

    ── 真實輸入集合的量測（2026-08-22，#407 R23e）──────────────────────
    本 repo 三個 workflow 的 19 行單行 `run:`，形狀只有兩類：

        13 行  <直譯器> <腳本>   （bash X／python3 X／swift X）
         6 行  run: |           （block scalar，本函式讀不到續行）
         1 行  swift --version  （唯一的純旗標形式）

    也就是說下面為 `||`／管線／`FOO=1 bash`／`cat X | bash`／同一支呼叫兩次
    ／`grep`・`shellcheck`・`chmod` 等寫的分支，**在本 repo 的真實輸入上一次
    都沒走過**——它們是為跨模型審查舉出的假想形式寫的。唯一在真實集合裡被
    修正的是 `--version`（R23b）。

    寫下來不是要刪掉它們（workflow 會改，而守衛的價值正是改動時仍正確），
    是為了讓下一個維護者知道**哪些路徑從未被真實輸入走過**——那些路徑的
    正確性只由負控保證，沒有生產環境的佐證。噪音率同輪量過：實際執行時
    只有 1 行 ℹ（block scalar 的彙總），`||` 揭露 0 次。

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
    conditional = []
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
        # **用 shlex 切 token，再按分隔符切段。**
        #
        # 前一版直接對字串 split，於是三種形式都錯（#407 R22c 量測）：
        #   · `cat x.txt | bash b.sh`  管線不在切分符裡 → b.sh 真的執行卻**零可見度**
        #   · `FOO=1 bash a.sh`        單段、head 不是直譯器 → 同上
        #   · `echo "見 a.sh && bash b.sh"`  引號內的 && 被當成分隔符 → **誤報**
        #
        # shlex 懂引號：第三種會變成 ['echo', '見 a.sh && bash b.sh'] 兩個 token，
        # 分隔符藏在字串裡不再被切開。切分符加上 `|`。
        #
        # 「單段未認出 ≠ 漏掉」那句話**先前寫得太寬**：它對 `echo "見 X.sh"` 成立，
        # 對 `FOO=1 bash X` 不成立。判準改為看 head 是不是明確的「不執行」命令。
        # `punctuation_chars=True` 讓 `;`／`|`／`&&`／`||` 成為**獨立 token**。
        # 沒有它的話 `bash a.sh; bash b.sh` 會被切成 `['bash','a.sh;',…]`——分號
        # 黏在檔名尾巴上，於是整行變成單段而兩支都認不出（#407 R22c 當場撞到，
        # 六格驗證裡就這一格紅）。
        try:
            lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            tokens = list(lex)
        except ValueError:
            tokens = cmd.split()          # 未閉合引號等——退回粗略切法
        # **記住每段前面的分隔符——`||` 的語意與其他三個不同。**
        #
        # `bash A || bash B` 的 B **只在 A 失敗時跑**。R22c 把 `||` 加進切分符
        # 時讓兩段同等對待，於是 B 被算成「執行了」——而在正常（綠）的 CI 狀態
        # 下它根本不跑。這是 regression：R21c 之前 `||` 不在切分符裡，B 是**漏報**
        # （安全方向，讓守衛紅）；R22c 之後變成**誤記**（守衛綠而它其實沒跑）。
        # 跨模型審查的 logic 席指名，量測確認（#407 R23）。
        segments, cur, sep = [], [], None
        for tok in tokens:
            if tok in ('&&', '||', ';', '|'):
                segments.append((sep, cur))
                cur, sep = [], tok
            else:
                cur.append(tok)
        segments.append((sep, cur))
        segments = [(s, c) for s, c in segments if c]
        # **認出「執行的形式」，不列舉「不執行的命令」。**
        #
        # 上一版維護一份 NON_EXEC 白名單（echo／printf／cat／…）。那是在用封閉
        # 列舉描述一個**開放集合**——實測 13 個常見 CI 命令全部觸發假警報：
        # `grep -n foo b.sh`、`shellcheck b.sh`、`wc -l b.sh`、`chmod +x b.sh`、
        # `git add b.sh`、`cp b.sh /tmp/`、`test -f b.sh`、`black --check b.py`…
        # 每加一個進白名單，下一個仍在外面（#407 R22d）。
        #
        # 反過來問：**這一段有沒有直譯器 token？** 沒有的話它不可能在跑腳本
        # （`grep`／`shellcheck`／`cp` 都不會），靜默即可。有的話它可能在跑，
        # 而我們認不出形式時才需要揭露。
        INTERP = ('bash', 'sh', 'python3', 'python', 'swift')
        for sep_before, st in segments:
            h = st[0]
            # **`||` 有兩種讀法，靜態判不出是哪一種**（#407 R23d，跨模型審查
            # 的 logic 席指名，實測確認）：
            #
            #   error-fallback：`main || handle_failure`      → RHS 只在失敗時跑
            #   **skip-flag**：`[ -f .done ] || bash setup.sh` → RHS **每次都跑**
            #
            # 第二種在 CI 裡同樣常見（`command -v x >/dev/null || bash install.sh`），
            # 而它的 LHS 通常為假——RHS 就是正常路徑。R23 把兩者都當成例外路徑，
            # 於是 skip-flag 形式的守衛會被誤報成「沒被執行」。
            #
            # 判不出來就**不假裝判得出來**：不計入覆蓋（保守，寧可假紅不可假綠
            # ——與本檔一貫立場一致），但訊息要說明它**可能是假警報**，由人裁決。
            if sep_before == '||':
                if any(x in INTERP or x.startswith('./') for x in st) or \
                        any(re.search(r'\S+\.(?:sh|py|swift)\b', x) for x in st):
                    conditional.append(' '.join(st))
                continue
            if h in INTERP:
                # 跳過旗標找腳本（`bash -x a.sh` 是常見的除錯形式）。
                # `-m` 例外：`python3 -m mod x.py` 跑的是模組，x.py 是它的引數。
                if '-m' not in st:
                    script = next((x for x in st[1:]
                                   if not x.startswith('-')
                                   and x.endswith(('.sh', '.py', '.swift'))), None)
                    if script:
                        found.add(os.path.basename(script))
                        continue
                # **直譯器單獨成段（或引數裡全是旗標）＝ 從 stdin 讀。**
                # `cat deploy.sh | bash` 是常見的 CI 部署慣用法，而它真的執行了
                # deploy.sh——先前這裡無條件 `continue`，於是零可見度（#407 R22e，
                # 跨模型審查指名）。管線來源在別的段裡，本函式看不出它是哪一支，
                # 所以揭露而不是猜。
                # **只有在管線下游才是 stdin 執行。**
                #
                # 判準是**位置**不是旗標列舉：`cat d.sh | bash` 的 bash 有來源，
                # `bash --version` 沒有。上一版問「引數裡有沒有非旗標的東西」，
                # 於是 `bash --version`／`python3 -V`／`swift --version` 這些
                # CI 極常見的環境檢查全部被當成 stdin 執行而印假警報（#407 R23b，
                # DA 席那題的量測答案）。
                #
                # 用旗標白名單修是錯的方向——那正是 R22d 剛從 NON_EXEC 拆掉的
                # 開放集合形狀（`--version`／`-V`／`--help`／`--check`… 列不完）。
                if sep_before == '|' and \
                        not any(x for x in st[1:] if not x.startswith('-')):
                    chained.append(' '.join(st))
                    continue
                # `-m` 或引數裡沒有腳本——它跑的不是我們關心的那種東西，靜默。
                continue
            if h.startswith('./') and h.endswith(('.sh', '.py', '.swift')):
                found.add(os.path.basename(h))
                continue
            # head 不是直譯器。只有當**段內**仍出現直譯器 token 時，才可能有
            # 一個我們看不到的執行（`FOO=1 bash a.sh`、`env bash a.sh`）。
            if any(x in INTERP for x in st[1:]):
                chained.append(' '.join(st))
    if conditional:
        # **逐筆具名，不彙總。**（#407 R24，DA 席的 cry-wolf 論證）
        #
        # 上一版印一則不指名的旁白，而主判定訊息（「不在任何 CI workflow 跑」）
        # 在「真的是例外路徑」與「skip-flag 幾乎必跑」兩種情況下**完全相同**。
        # 人看過幾次假警報之後，會學會對所有帶 ℹ 的判定一起打折扣——包括真正
        # 的缺口。免責聲明要能對上號才抵銷得了保守的代價。
        print(f'   ℹ `||` 後的段（語意靜態判不出，保守不計入覆蓋）：')
        for c in conditional:
            print(f'      · {c}')
        print(f'      ↑ 可能是例外路徑（`main || handle_failure`，缺口為真），'
              f'也可能是正常路徑（`[ -f flag ] || do_work`，LHS 通常為假 → '
              f'**缺口是假警報**）。逐筆確認上面那幾行，或改寫成 `&&`／分行')
    if chained:
        # `cd A && bash X` 這類串接：第一個 token 不是直譯器，所以認不出來。
        # **方向是漏報**（守衛會紅、不會假綠），但仍要印——R20c 才立下的原則是
        # 「寫在註解裡的已知限制，對讀輸出的人等於沒人知道」（#407 R20e）。
        print(f'   ℹ 有 {len(chained)} 個串接段帶著腳本檔名卻認不出執行形式'
              f'（變數展開、前置賦值等）——那些呼叫看不到（漏報，會讓守衛紅）')
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
# **這裡曾有一段自指排除，已退場（#407 R21）——但退場的理由當時寫寬了。**
#
# 當時 DECLARE 是裸子串，於是本檔（機制的實作者）因為錯誤訊息模板裡的字面
# 被算成「有宣告」。加特例排除之後，harness 又因為 case 描述裡的字面撞上同
# 一件事。收窄 DECLARE 為「整行就是宣告」之後兩者都消失，於是我寫下「收窄
# 才是根治」——**那句話過寬**（#407 R21d，DA 席指名）。
#
# 收窄真正解決的是「字面出現在**字串**裡」。它擋不住**獨立成行的教學範例**：
# 一行 `# trigger-coverage: reads plugin/rules/*.md` 寫在任何守衛的 docstring
# 裡，都會完整匹配。當時之所以沒再撞到，是因為我**手動**把本檔的範例改成了
# 佔位形式——那是一次性的遮蔽，不是機制。
#
# 現在的立場：**收窄**（機制，擋字串內的字面）＋ **佔位約定**（約定，擋教學
# 範例）＋ **痕跡檢查**（啟發式，見下方「宣告的目標，守衛自己得提過」）。
#
# **第三層原本寫的是「可見性」，那句話是假的**（#407 R22b）：攤開表的 ⟨宣⟩
# 只說「這來自宣告」，不說「這個宣告是對的」——一條編造的宣告印出來與正常
# 依賴逐字相同。要看出不對，讀者得**已經知道**那個守衛實際讀什麼，那不是可見。
# 換成痕跡檢查之後它至少是可否證的：宣告的目錄名必須在守衛原始碼裡留下痕跡。
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
    # **判準是結構的，不是比例的。**
    #
    # 上一版寫「命中超過受保護檔的一半」。那是比例判準，會隨集合形狀漂移：
    # 實測 `plugin/tests/*` 目前命中 6/16（安全），但守衛再長 5 支就會被判過寬
    # ——而它是一個**完全合法**的目錄宣告。把會變的東西當成恆定判準，正是這條
    # issue 反覆記過的形狀（#407 R21b）。
    #
    # 要擋的東西有結構性特徵：`*`／`*.sh` **沒有路徑成分**——它們說「凡是這種
    # 副檔名的」，不是「這個位置的」。有路徑成分的宣告（`plugin/tests/*`、
    # `plugin/rules/*.md`）是在指認位置，合法且不隨集合大小改變。
    #
    # 比例檢查保留，但收到無疑義的那一格：命中**全部**。
    for line in raw.split('\n'):
        m = DECLARE.match(line)
        if not m:
            continue
        # **判準是「第一段必須是字面」，不是「含有斜線」。**
        #
        # R21b 從比例判準換成結構判準時方向對了（不隨集合漂移），但判準取得
        # 太表面：`*/*.sh` 含斜線、命中 5/16，兩道檢查都放它過——而它與被擋掉
        # 的 `*.sh` **同樣不具體**，差別只是一個無意義的 `*/` 前綴（#407 R22，
        # DA 席那題的量測答案）。
        #
        # 「指認位置」的性質是：起點是一個**真的目錄名**。`plugin/tests/*` 從
        # `plugin` 出發，`*/*.sh` 從「任何地方」出發——後者沒有指認任何東西。
        first = m.group(1).split('/')[0]
        if '*' in first or '?' in first:
            fails.append(f'{os.path.basename(g)} 的宣告 `{m.group(1)}` 的第一段是'
                         f'萬用字元——那是在說「任何地方的這類檔案」，不是在指認'
                         f'依賴的位置；請從一個真的目錄名開始')
    decl_lines = [line for line in raw.split('\n') if DECLARE.match(line)]
    if len(decl_lines) > 1:
        # **這是約定，不是機制**，而且它有已知的誤擋風險：一個真的依賴兩個
        # 不相關路徑根的守衛需要兩條宣告，而沒有語法能把它們併成一條。目前
        # 零實例（沒有守衛需要兩條）。裁決保留，因為不對稱：誤擋是**可見且
        # 可逆**的（加宣告時被擋、看到訊息、改寫或回報），而漏掉教學範例是
        # **安靜的假依賴**（#407 R22b，requirements 席指名）。
        fails.append(f'{os.path.basename(g)} 有 {len(decl_lines)} 行宣告——一個守衛'
                     f'通常只需要一條；多出來的那行多半是教學範例，請改寫成佔位'
                     f'形式。若你**真的**需要兩條不同路徑根的宣告，這道檢查會擋'
                     f'錯——請改這裡並在 CHANGELOG 記下第一個實例')
    # **宣告的目標，守衛自己得提過。**
    #
    # 上一版說第三層是「可見性」——攤開表用 ⟨宣⟩ 標出宣告來源，「誤宣告會顯示
    # 成這個守衛讀了它其實不讀的東西」。**那句話是假的**（#407 R22b 實測）：
    # 一條格式完全正確、指向它不讀的東西的宣告，攤開表印出來與正常依賴**逐字
    # 相同**；要看出不對，讀者必須**已經知道**那個守衛實際讀什麼——那不是可見。
    #
    # 沒有便宜的機制能驗「宣告是否屬實」（那要執行或靜態分析）。但有一個便宜
    # 的**必要條件**：宣告存在的理由是補啟發式的漏（守衛用 glob 組路徑，所以
    # basename 不逐字出現），而那種守衛通常仍會提到**目錄名**。實測
    # `rule-coverage.sh` 去掉宣告行後仍提到 `rules` 兩次；一條編造的宣告則零次。
    #
    # 仍是啟發式，方向是**誤報**（極端動態的守衛會被擋）——而誤報可見可逆。
    body = '\n'.join(l for l in raw.split('\n') if not DECLARE.match(l))
    for line in decl_lines:
        glob_ = DECLARE.match(line).group(1)
        # **往前找第一個非萬用字元的段。** `Sources/*/*.swift` 的 dirname 是
        # `Sources/*`，取最後一段會得到 `*`，於是下面的萬用字元條件讓整條宣告
        # **跳過檢查**——而它的第一段是字面 `Sources`，前一道也放它過，於是
        # 完全不被驗（#407 R22e，跨模型審查指名）。
        # **宣告指向守衛自己所在的目錄 ⇒ 它補不了任何漏。**
        #
        # 宣告存在的理由是補啟發式的漏（守衛用 glob 組路徑，basename 不逐字
        # 出現）。而**同目錄**的東西啟發式本來就看得到，不需要宣告。更糟的是
        # 痕跡檢查對這一類**沒有鑑別力**：守衛住在 `plugin/tests/`，那個字串
        # 必然出現在它自己的註解裡，於是 `seg='tests'` 對**每一個守衛**都命中
        # ——實測一條編造的 `reads plugin/tests/*.py` 完全通過（#407 R23c）。
        decl_dir = os.path.dirname(glob_).rstrip('/')
        if decl_dir and os.path.dirname(g).rstrip('/') == decl_dir:
            # **這說的是「不必要」，不是「假的」——所以是警告不是缺口。**
            #
            # R23c 把它寫成 fail 並 `continue`，於是它與「編造的宣告」拿到同一
            # 種嚴重度、同一則訊息。跨模型審查指出反例（#407 R24）：GUARDS 只
            # 枚舉 `.sh`/`.py`，所以同目錄的**資料檔**（golden 快照、oracle 表）
            # 不在啟發式的視野裡；若守衛又以 runtime 組路徑讀它，那條同目錄宣告
            # 就是**真的且必要**的。把它當假的拒絕，是把兩件事混為一談。
            warnings.append(f'{os.path.basename(g)} 宣告讀 `{glob_}`，而那正是它'
                            f'自己所在的目錄——同目錄的**腳本**啟發式本來就看得到，'
                            f'這條宣告多半多餘；但同目錄的**資料檔**（非 .sh/.py）'
                            f'不在枚舉範圍內，那種依賴的宣告是必要的。請人確認')
            continue
        parts = [p for p in os.path.dirname(glob_).rstrip('/').split('/') if p]
        seg = next((p for p in reversed(parts)
                    if '*' not in p and '?' not in p), '')
        # **沒有目錄部分的 glob 跳過。** `*.sh` 的 dirname 是空字串，退化之後
        # seg 會變成 pattern 自己，而它當然不在原始碼裡——於是這條會跟「第一段
        # 是萬用字元」那條**同時**報，讓負控的鑑別力判準正確地判它不外科手術
        # （#407 R22b 當場撞到）。那類 glob 已由前一條負責，這裡不重複。
        # **詞邊界，不是子串。** `seg not in body` 會讓 `docs` 因為原始碼裡有
        # `docstring` 而算成有痕跡，`tests` 因為 `attests`／`protests`——巧合的
        # 字串重疊足以讓一條編造的宣告矇混過去（#407 R22f，跨模型審查的次要
        # 指名）。實測：詞邊界版正確區分 `docs`/`docstring`（無痕跡）與
        # `rules`/`$PLUGIN/rules`（有痕跡）。
        # **要在路徑脈絡裡出現，不只是一個詞。**
        #
        # 詞邊界擋掉了 `rulesets` 那種巧合子串（R22f），但擋不住**散文**：
        # `# TODO: add more tests` 裡的 `tests` 是完整的詞，於是一條編造的
        # `reads plugin/*/tests/*.py` 被算成有痕跡（#407 R23d，requirements
        # 席指名）。而 R22e 的 walk-back 讓這更容易發生——它退到的往往是
        # `tests`／`docs`／`scripts` 這種在散文裡很常見的短詞。
        #
        # 要求它出現在**看起來像路徑或賦值**的位置：前面是 `/`／引號／`$`／`=`，
        # 或後面接 `/`／引號。實測正確區分散文與真路徑。
        esc = re.escape(seg)
        traced = seg and re.search(
            rf'[/"\'$=]{esc}(?![A-Za-z0-9_-])|(?<![A-Za-z0-9_-]){esc}[/"\']',
            body)
        # **降為警告，不 fail。**（#407 R24，跨模型審查兩個方向各給一個反例）
        #
        # 這個檢查走過三版近似，每一版都被證明兩頭不對：
        #
        #   子串（R22b）    → `rulesets` 含 `rules`，巧合就矇混
        #   詞邊界（R22f）  → `# TODO: add more tests` 的 `tests` 是完整的詞
        #   路徑脈絡（R23d）→ 太鬆：`unit tests/integration tests` 仍匹配
        #                     太緊：`find Sources -name` 真的讀卻不匹配
        #
        # 最後兩個方向**本質上衝突**：放寬讓散文更容易矇混，收緊拒掉更多真實
        # 用法。字串脈絡判不出「這行在不在讀那個目錄」——那是靜態分析問題。
        #
        # 而真實輸入集合是 **1 條宣告**（R23e 量過），編造的宣告零實例。一個
        # 零實例、且已證明兩頭不準的檢查不該 fail-closed：它的誤拒會擋掉合法
        # 宣告，而那是**可見且惱人**的；它漏掉的編造宣告則從未出現過。
        #
        # 保留為警告：它仍指出「這條宣告沒有明顯痕跡」，由人判斷。
        if seg and '*' not in seg and '?' not in seg and not traced:
            warnings.append(f'{os.path.basename(g)} 宣告讀 `{glob_}`，但它的原始碼'
                            f'（扣掉宣告行本身）沒有明顯提到 `{seg}` 的痕跡'
                            f'——**這是啟發式，兩個方向都會錯**（見上方註解），'
                            f'請人確認這條宣告是否屬實')
    # **這一條目前不可獨立觸發，保留是有條件的。**
    #
    # 要命中全部 16 個受保護檔就得跨 `plugin/` 與 `Sources/` 兩個前綴，而那
    # 需要第一段是萬用字元——於是一定先被上面那條抓。實測：沒有任何「第一段
    # 字面 ＋ 命中全部」的 glob 存在（#407 R22）。
    #
    # 不刪的理由是它**條件性可達**：若日後 Sources 那兩個受保護檔退場、全部
    # 集中到 `plugin/` 底下，`plugin/**` 就會是「第一段字面 ＋ 命中全部」，
    # 那一刻這條就活過來。這與 no-compat-fallback 的「退場即刪」不同——那條
    # 管的是用途已歸零的相容路徑，這裡是用途取決於集合形狀。
    #
    # **負控裡沒有它的格子**，因為它現在不可獨立觸發：留一格假裝在測它，與
    # 沒有負控在報告上長得一樣。
    hits = declared(g)
    if hits and len(hits) == len(PROTECTED):
        fails.append(f'{os.path.basename(g)} 的宣告命中全部 {len(PROTECTED)} 個'
                     f'受保護檔——那不是宣告依賴，是在描述整個 repo')

print('每支守衛被判定讀了哪些受保護檔（啟發式，漏報方向——見 READS 上方註解）：')
for g in GUARDS:
    decl = declared(g)
    parts = []
    for x in sorted(READS[g]):
        if x == g:
            continue
        # 標出來源：宣告來的加 ⟨宣⟩。一個誤宣告（教學範例被當成宣告）會在這裡
        # 顯示成「這個守衛讀了它其實不讀的東西」——約定被違反時的可見性。
        parts.append(os.path.basename(x) + ('⟨宣⟩' if x in decl else ''))
    print(f'   {os.path.basename(g):<32} → {"、".join(parts) if parts else "（只有自己）"}')
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

if warnings:
    print(f'\n══ 待人確認 {len(warnings)}（啟發式警告，不構成缺口）══')
    for m in warnings:
        print(f'  ? {m}')
if fails:
    print(f'\n══ 缺口 {len(fails)} ══')
    for m in fails:
        print(f'  · {m}')
    sys.exit(1)
print('\n══ 觸發點覆蓋無缺口（逐對意義，非聯集）══')
