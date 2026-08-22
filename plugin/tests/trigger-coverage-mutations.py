#!/usr/bin/env python3
"""negative control：trigger-coverage.py 真的會在觸發點被拆掉時變紅嗎？

一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。

**mutate 的是一份 copy**，出貨檔完全不碰（#407 R7 的教訓：前一版就地改寫版控中
的檔案，跨模型審查在審查期間實際觀察到出貨檔出現三種被注入的狀態）。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GUARD_REL = 'plugin/tests/trigger-coverage.py'
BEFORE = os.path.getmtime(os.path.join(ROOT, GUARD_REL))


def run(root):
    r = subprocess.run([sys.executable, os.path.join(root, GUARD_REL), '--root', root],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def with_copy(edits):
    """複製整個 repo 的相關子樹，套用 edits（相對路徑 → 轉換函式），跑守衛。"""
    with tempfile.TemporaryDirectory(prefix='trig-mut-') as tmp:
        for sub in ('plugin', '.github', '.githooks', 'Sources'):
            src = os.path.join(ROOT, sub)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(tmp, sub))
        for rel, fn in edits.items():
            p = os.path.join(tmp, rel)
            # **先讀完，再開寫。** 寫成一行的話 Python 會先求值 io.open(p,'w')
            # ——那一步就截斷了檔案——才求參數裡的 read()，於是讀到空字串、
            # 寫回空字串。#407 R19 當場踩到：守衛的 copy 是 0 bytes，於是它
            # 零輸出、rc=0，而**前三格仍然「紅」**——紅的原因是檔案被清空，
            # 不是它們宣稱的注入。一個因錯誤理由變紅的負控，等於不存在。
            before = io.open(p, encoding='utf8').read()
            after = fn(before)
            if after == before:
                raise SystemExit(f'✗ 注入對 {rel} 沒有造成任何改動——'
                                 f'注入式已與被注入的內容脫節')
            io.open(p, 'w', encoding='utf8').write(after)
        return run(tmp)


def warn_case(desc, edits, expect_substr):
    """斷言**警告**出現（rc 不變）。

    #407 R24 把三個啟發式檢查（痕跡、同目錄）從 fail 降為 warning——它們說的是
    「請人看一眼」而不是「這裡壞了」。負控要跟著分兩種判準：把 warning 當 fail
    測，會逼人把啟發式維持在 fail-closed，而那正是 R24 判定不該做的事。
    """
    rc, out = with_copy(edits)
    warns = re.findall(r'^  \? (.+)$', out, re.M)
    gaps = re.findall(r'^  · (.+)$', out, re.M)
    # **綁定到被 mutate 的那個守衛**（#407 R24e，跨模型審查指名）。
    #
    # 上一版只問「輸出裡有沒有 expect_substr」——那與「哪一個守衛觸發的」無關。
    # 若某個 mutation 不再觸發警告，而**別的**守衛在未 mutate 的狀態下剛好產生
    # 匹配的警告，這一格仍會綠。警告訊息的模板對每個守衛都一樣，所以這不是
    # 假想：同目錄那條的尾巴（「那正是它自己所在的目錄」）逐字相同。
    # **為什麼只有 warn_case 綁定、`case` 不綁**（#407 R24g，量過才寫）：
    #
    #   warn_case 的六格全部 edit **守衛檔本身**，而警告訊息指名的就是那個守衛
    #             ——被改的與被指名的是同一個東西，綁得起來。
    #   case      **14/17 格** edit `.yml`／hook，而缺口訊息指名的是**守衛**
    #             （「改 X 時 Y 不在任何 CI 跑」）——被改的與被指名的不同，
    #             同樣的綁定會誤殺它們。
    #
    # **另 3 格是可以綁的**（#407 R24i 修正——上一版把「多數」寫成了「一律」）：
    # 它們 edit `rule-coverage.sh` 本身，而缺口訊息也指名該守衛，只是
    # `expect_substr` 沒包含檔名。要綁得每格額外宣告「這一格的訊息該指名誰」
    # ——**成本高於收益**：那 3 格的 expect（「行宣告」「第一段是萬用字元」）
    # 已經夠獨特，不會被別的守衛的訊息碰巧滿足。
    #
    # 所以 `case` 維持靠 expect_substr ＋ stray 檢查。**這是取捨，不是「綁不了」**。
    # **單檔才綁得住。**（#407 R24h，跨模型審查指名這個「休眠的角」）
    #
    # 綁定是「警告行含 `expect_substr` **且**含某個被 edit 的檔名」。若 edits
    # 有兩個 key，那個「某個」變成**聯集**——A 的警告消失而 B 恰好有一條文字
    # 相符的既有警告時，這一格仍會綠。目前六格都是單檔（量過），但函式本身
    # 沒有攔它，所以在這裡攔：多檔的 warn_case 要嘛拆成兩格，要嘛改寫綁定。
    if len(edits) != 1:
        raise SystemExit(f'✗ warn_case 目前只支援單檔 edits（收到 {len(edits)} 個）'
                         f'——綁定會退化成聯集，見上方註解')
    targets = {os.path.basename(k) for k in edits}
    named = [w for w in warns
             if expect_substr in w and any(tg in w for tg in targets)]
    stray = [w for w in warns if w not in named]
    # 三段判準，與 case() 對齊（#407 R24b，跨模型審查指出 warn_case 少了兩段）：
    #   1. rc **必須是 0**——警告不改變 exit code，那正是「降為 warning」的意思。
    #      若某個注入意外觸發別的 fail，上一版仍會過。
    #   2. 指名的警告出現。
    #   3. 鑑別力：不得有無關的警告，也不得有任何缺口（有缺口就不是純警告情境）。
    ok = rc == 0 and named and not stray and not gaps
    if ok:
        print(f'✓ {desc} → 警告出現（rc=0，警告 {len(warns)} 條全屬同類）')
    elif rc != 0:
        print(f'✗ {desc} → rc={rc} ← 警告不該改變 exit code；缺口：{gaps[:2]}')
    elif not named:
        print(f'✗ {desc} → 警告沒出現 ← 檢查對它是盲的')
    else:
        print(f'✗ {desc} → 另有 {len(stray)} 條無關警告 ← 注入不是外科手術式的')
    return ok


def case(desc, edits, expect_substr):
    """判準有三段，第三段是 #407 R20d 補的。

    前兩段（守衛變紅、訊息指名了它）不足以說這格**鑑別**了它具名的缺陷：
    一個注入若順帶打壞別的東西，紅的原因就分不出來。姊妹 harness
    （plugin/tests/rule-prose-guards-mutations.py）在 R18b 已經吃過這個虧
    ——四格宣告「第 1 項」的注入實際紅 [1, 2]。

    所以第三段要求**每一條被報出來的缺口都屬於它指名的那一類**。實測八格
    全部「其他 0」，這條斷言在寫下時即為真，而它防的是日後新增的不純注入。
    """
    rc, out = with_copy(edits)
    hit = expect_substr in out
    gaps = re.findall(r'^  · (.+)$', out, re.M)
    stray = [g for g in gaps if expect_substr not in g]
    ok = rc != 0 and hit and not stray
    if ok:
        print(f'✓ {desc} → rc={rc}，指名了它'
              + (f'（缺口 {len(gaps)} 條全屬同類）' if gaps else ''))
    elif not hit:
        print(f'✗ {desc} → rc={rc}，但沒指名 ← 訊息對它是盲的')
    elif stray:
        print(f'✗ {desc} → rc={rc}，但另有 {len(stray)} 條無關缺口 '
              f'← 注入不是外科手術式的：{stray[:2]}')
    else:
        print(f'✗ {desc} → rc={rc}')
    return ok


base_rc, base_out = run(ROOT)
if base_rc != 0:
    sys.exit(f'✗ baseline 不是全綠（rc={base_rc}）——負控在紅的 baseline 上沒有意義\n{base_out}')
print('baseline：無缺口 ✓\n')

RESULTS = [
    case('從 pre-push 拿掉一支守衛',
         {'.githooks/pre-push': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n', '')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    case('從 workflow 的 paths 拿掉 census 的資料依賴',
         {'.github/workflows/census-parity.yml': lambda t: t.replace(
             '      - "plugin/skills/akashic-literal-campaign/scripts/hash-merging-ranges.txt"\n', '')},
         # **指名側別**：缺口模板是「改 {f} 時 {g} 不在…」，裸檔名會同時吞下
         # f 側與 g 側。這一格宣告的是「把該檔從 paths 拿掉」，期望 f 側。
         '改 hash-merging-ranges.txt 時'),
    case('從 workflow 拿掉一個 run 步驟（守衛還在版控，只是不再被執行）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh', 'run: true  # 被拿掉了')},
         'rule-coverage.sh'),
    # 下面兩格是 #407 R20 跨模型審查實測到的**假陰性**——修法之前這兩種狀態
    # 都讓守衛報綠而它宣稱的性質為假。
    case('把 pre-push 的一支守衛換成只提到它的註解',
         {'.githooks/pre-push': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n',
             '# TODO: 之後再接 plugin/skills/akashic-literal-campaign/'
             'scripts/tests/store-marker-parity.sh\n')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    case('把 workflow 的一個 run: 換成只印檔名的 echo',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: echo "見 plugin/tests/rule-coverage.sh 的說明"')},
         'rule-coverage.sh'),
    # 同一個 echo 但用 `./` 形式。R20 只修了直譯器那半邊（`bash X`），
    # `./X` 分支照舊掃全行——這一格是那個殘留的負控（#407 R20c）。
    # #407 R23b：`bash --version` 是 CI 極常見的環境檢查。判準若問「引數裡有
    # 沒有非旗標的東西」，它會被當成 stdin 執行而印假警報。改成問**位置**
    # （只有管線下游才是 stdin 執行）之後靜默——這一格用一個真的管線執行
    # 證明揭露仍然會發生，兩者的差別就是那個位置。
    case('把 run: 換成 `cat <守衛> | bash`（管線下游的裸直譯器）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: bash --version && cat plugin/tests/rule-coverage.sh | bash')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    # **這一格的敘述先前是錯的**（#407 R23d）：它寫「`||` 後的段在正常狀態下
    # 不執行」，並用 `test -f /nonexistent || bash <守衛>` 當例子——而那個 LHS
    # **永遠失敗**，所以守衛**每次都跑**。跨模型審查的 logic 席指出這一點，
    # 實測確認（`bash -c 'test -f /nonexistent || echo RHS'` 印出 RHS）。
    #
    # `||` 的語意靜態判不出（error-fallback vs skip-flag），守衛的立場是保守
    # 不計入覆蓋並說明它可能是假警報。這一格保留，但改為斷言**那段說明出現**
    # ——而不是斷言「守衛應該報它沒被執行」那個可能為假的期望。
    case('把守衛掛到 `||` 之後（語意判不出，守衛須說明而非斷言）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: test -f /nonexistent || bash plugin/tests/rule-coverage.sh')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    # #407 R23d：詞邊界擋得住 `rulesets` 那種巧合子串，擋不住**散文**——
    # `# TODO: add more tests` 裡的 `tests` 是完整的詞。加上路徑脈絡要求後
    # 才擋得下來。
    # **釘住「誤殺不得回來」**（#407 R24f）：一個守衛用純 glob 讀宣告的目錄、
    # 從不寫出目錄名——那正是宣告機制的目標使用者。R24d 的三級化把它判成
    # 「可證偽的假陳述」而 fail；退回兩級之後它是警告（請人確認），不是缺口。
    warn_case('守衛用純 glob 讀宣告的目錄、從不寫目錄名（宣告為真，不得誤殺）',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md\n'
             'for f in "$(dirname "$0")"/../*/*.md; do :; done', 1)},
         '一次都沒出現過'),
    warn_case('編造宣告 + 一句含該目錄名的散文（有提到但非路徑脈絡）',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n# trigger-coverage: reads Sources/AkashicCore/*.swift\n'
             '# 註：本檔不碰 AkashicCore，只重建審查者的失敗情境。', 1)},
         '有出現但不在路徑脈絡裡'),
    # #407 R22e：`cat X | bash` 是常見的 CI 部署慣用法，它真的執行 X——先前
    # 直譯器單獨成段時無條件靜默，於是零可見度。
    case('把 run: 換成 `cat <守衛> | bash`（直譯器從 stdin 讀）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: cat plugin/tests/rule-coverage.sh | bash')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    # #407 R23c：痕跡檢查問「守衛提過這個目錄嗎」，而守衛提到**自己所在的
    # 目錄**是必然的（路徑字串出現在它自己的註解裡）——於是 `seg='tests'`
    # 對每一個守衛都命中，一條編造的 `reads plugin/tests/*.py` 完全通過。
    warn_case('宣告指向守衛自己所在的目錄（可能多餘、也可能必要）',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash', '#!/bin/bash\n# trigger-coverage: reads plugin/tests/*.py', 1)},
         '那正是它自己所在的目錄'),
    # #407 R22f：痕跡檢查若用**子串**比對，巧合的字串重疊足以讓編造的宣告
    # 矇混過去。這一格給一個不含 `rules` 的守衛同時注入 (a) 一條指向
    # `plugin/rules/*.md` 的編造宣告 (b) 一行含 `rulesets` 的註解——`rules`
    # 是 `rulesets` 的子串但不是它的詞，所以子串版放過、詞邊界版擋下。
    warn_case('編造宣告 + 巧合子串（`rulesets` 含 `rules`，非路徑脈絡）',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md\n'
             '# 說明：本檔不處理 rulesets，只重建審查者的失敗情境。', 1)},
         '有出現但不在路徑脈絡裡'),
    # #407 R22e：`Sources/*/*.swift` 的 dirname 末段是 `*`，先前讓痕跡檢查
    # 整條跳過，而第一段字面 `Sources` 又讓前一道放它過——完全不被驗。
    warn_case('宣告用中間萬用字元（`Sources/*/*.swift`）——痕跡走回 `Sources`',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads Sources/*/*.swift')},
         '一次都沒出現過'),
    # #407 R22d：把守衛的呼叫換成一個**不執行它**的命令（shellcheck 只做靜態
    # 檢查）。判準若還是「列舉不執行的命令」，這一格會因為 shellcheck 不在
    # 白名單而報成「有東西看不到」——那是假警報不是缺口。現在的判準是「段內
    # 有沒有直譯器」，所以它靜默，而覆蓋缺口由 rule-coverage.sh 不再被執行
    # 這件事本身報出來。
    case('把 run: 換成 shellcheck（靜態檢查，不執行守衛）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: shellcheck plugin/tests/rule-coverage.sh')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    # #407 R22c 量測到的兩個零可見度形式。管線先前完全不在切分符裡，於是
    # `cat x | bash <守衛>` 的守衛既不進 found 也不進 chained。
    case('把 run: 改成管線形式（`cat x | bash <守衛>` 後半換成 echo）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: cat /dev/null | echo "見 plugin/tests/rule-coverage.sh"')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    case('把 run: 換成印出 ./ 形式檔名的 echo（R20 修法的殘留半邊）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: echo "見 ./plugin/tests/rule-coverage.sh 的說明"')},
         'rule-coverage.sh'),
    # 宣告機制若被「統一」成走 code_only()，宣告行（是註解）會被剝掉、機制
    # 整個失效——而守衛本來**不會紅**（只是少考慮幾個 pair，沉默地）。R20b
    # 把它變成會紅的，這一格證明那件事。
    case('把 declared() 改成走 code_only()（宣告行是註解，會被剝掉）',
         {'plugin/tests/trigger-coverage.py': lambda t: t.replace(
             "    for line in io.open(path, encoding='utf8', errors='replace'):\n"
             "        m = DECLARE.search(line)",
             "    for line in code_only(path).split('\\n'):\n"
             "        m = DECLARE.search(line)")},
         '宣告機制失效了'),
    # **這一格曾是「拿掉自指排除」，已隨那個特例一起退場**（#407 R21）：
    # DECLARE 收窄為「整行就是宣告」之後，實作者自己不再被誤認，特例沒有東西
    # 可保護、這一格也證明不了任何事。留著一個永遠綠的負控，與沒有負控在報告
    # 上長得一樣——那正是本 harness 存在的理由。
    #
    # 取而代之的兩格，來自同輪跨模型審查：
    # 兩條規則各一格，**刻意不用 `reads *`**：那個 glob 同時觸發兩條（無路徑
    # 成分 ＋ 命中全部），於是它證明不了是哪一條抓到的——第三段鑑別力判準會
    # 正確地把它判成不外科手術（實測過，#407 R21b）。
    #
    # `*.sh` 命中 5/16——**比例判準放它過**，結構判準擋下。這一格是判準從
    # 比例改成結構之後才抓得到的東西。
    # 切段之後，`bash A && bash B` 的 B 也認得出來——這一格證明那件事：
    # 把真的執行 B 的那一段改成 echo，B 才該從 found 消失（#407 R21c）。
    case('把 run 改成 `bash setup.sh && bash <守衛>` 再把後半換成 echo',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash plugin/tests/rule-coverage.sh',
             'run: bash scripts/setup.sh && echo "見 plugin/tests/rule-coverage.sh"')},
         'rule-coverage.sh 不在任何 CI workflow 跑'),
    # DA 席指名（#407 R21d）：收窄 DECLARE 擋不住**獨立成行的教學範例**——
    # 一行真實格式的示範會完整匹配。當時沒再撞到是因為我手動把本檔的範例改成
    # 佔位形式，那是一次性遮蔽不是機制。這一格證明「一個守衛只該有一條宣告」
    # 那道防線會接住它。
    case('在真宣告旁邊多寫一行教學範例（DA 指名的類別）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads plugin/rules/*.md\n'
             '# trigger-coverage: reads plugin/rules/*.md')},
         '行宣告'),
    # requirements 席指名（#407 R22b）：一條格式**完全正確**、指向它不讀的
    # 東西的宣告，先前完全通過——而攤開表印出來與正常依賴逐字相同。所謂
    # 「可見性」要求讀者已經知道守衛實際讀什麼，那不是可見。痕跡檢查把它
    # 變成可否證的：宣告的目錄名必須在守衛原始碼裡留下痕跡。
    warn_case('給一個不讀 rules/ 的守衛加一條格式正確的誤宣告',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash', '#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md', 1)},
         '一次都沒出現過'),
    case('把宣告改成 `reads *.sh`（比例判準會放過，結構判準擋下）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads *.sh')},
         '第一段是萬用字元'),
    # `*/*.sh` 含斜線、命中 5/16——**「含斜線」與「命中全部」兩道都放它過**，
    # 而它與 `*.sh` 同樣不具體。這一格是判準從「含斜線」收到「第一段必須是
    # 字面」之後才抓得到的（#407 R22，DA 席那題的量測答案）。
    case('把宣告改成 `reads */*.sh`（含斜線但第一段是萬用字元）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads */*.sh')},
         '第一段是萬用字元'),
    # **這裡曾有一格 `reads */*` 測「命中全部」，已移除**（#407 R22）：判準從
    # 「含斜線」收到「第一段必須是字面」之後，`*/*` 同時觸發兩條，於是它證明
    # 不了是哪一條抓到的——第三段鑑別力判準正確地把它判成不外科手術。
    #
    # 而「命中全部」那條**目前沒有任何 glob 能單獨觸發**（要命中全部就得跨
    # plugin/ 與 Sources/ 兩個前綴 → 第一段必為萬用字元 → 先被前一條抓）。
    # 留一格假裝在測它，與沒有負控在報告上長得一樣。該檢查的可達性條件寫在
    # trigger-coverage.py 它自己旁邊。
    case('把受保護檔案的路徑改成不存在的（憑記憶寫路徑的那個坑）',
         {GUARD_REL: lambda t: t.replace(
             "'Sources/AkashicStoreIO/StoreVersion.swift'",
             "'Sources/AkashicCore/StoreVersion.swift'")},
         '不存在的路徑'),
]

# 出貨檔不得被開啟以寫入。
assert os.path.getmtime(os.path.join(ROOT, GUARD_REL)) == BEFORE, \
    '✗ 出貨檔被改動了'
print(f'\n=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
print(f'出貨檔未被開啟以寫入：{GUARD_REL}')
sys.exit(0 if all(RESULTS) else 1)
