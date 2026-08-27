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
        # `.claude` 也要複製：`measured-numbers-audit.py` 宣告它讀 `.claude/rules/*.md`，（private repo，外部讀者取不到）
        # 而那些檔案現在在 PROTECTED 裡（#407 R48）。沒複製的話 temp 樹裡那條宣告
        # 解析不到，**每一個 case 都多報一條與注入無關的缺口**——R35 對根目錄檔案
        # 踩過完全同型的一次。
        for sub in ('plugin', '.github', '.githooks', 'Sources'):
            src = os.path.join(ROOT, sub)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(tmp, sub))
        # **`.claude` 只複製 `rules/`**（#433，與 `audit-guards-mutations.py` 同一個修正）：
        # 整個 `.claude` 是 2.0 GB／25,519 個檔，其中 `.claude/worktrees/` 佔 2.0 GB
        # （IDD 的隔離工作樹）；守衛要的只有規則檔（144 KB；private repo，外部讀者取不到）。
        # 全樹複製 16.5 秒一次 × 每個 case，而正確答案完全落在那個小目錄裡。
        rules_src = os.path.join(ROOT, '.claude', 'rules')
        if os.path.isdir(rules_src):
            os.makedirs(os.path.join(tmp, '.claude'), exist_ok=True)
            shutil.copytree(rules_src, os.path.join(tmp, '.claude', 'rules'))
        # **根目錄的受保護檔也要複製。** 它們不是子樹，上面那個迴圈看不到——
        # 漏掉時守衛在 temp 樹裡找不到 DATA 的成員，於是**每一個** case 都因為
        # 同一個與注入無關的理由變紅（#407 R27 當場踩到：加了 `CLAUDE.md` 進
        # DATA 之後 14/14 全紅，而紅的原因是檔案不存在）。
        for f in ('CLAUDE.md',):
            s = os.path.join(ROOT, f)
            if os.path.isfile(s):
                shutil.copy2(s, os.path.join(tmp, f))
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
    # **注入目標隨守衛清單搬家**（#432）：守衛行已從 `.githooks/pre-push` 移進
    # `.githooks/run-guards.sh`（hook 與 CI 共用同一份）。本 harness 在搬家那一刻
    # 立刻報「注入式已與被注入的內容脫節」——**它檢查注入本身有沒有改到東西**，
    # 而不是注入完跑一次、紅了就算過。那個性質是這裡最該保住的。
    case('從守衛清單拿掉一支守衛',
         {'.githooks/run-guards.sh': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n', '')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    # **改注入 `plugin-guards.yml`**（#432）：合併之後那個 workflow 的 `plugin/**`
    # 覆蓋了 census 的資料依賴，所以從 `census-parity.yml` 拿掉那一行**不再產生缺口**
    # ——實測 rc=0。那不是 harness 壞了，是合併讓一個 workflow 涵蓋了另一個的角色。
    #
    # 這一格要測的是「從 paths 拿掉一個受保護檔會不會被發現」，所以目標換成
    # 現在真的承擔涵蓋責任的那個。
    case('從 workflow 的 paths 拿掉一個受保護檔',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             '      - "plugin/**"\n', '')},
         # **指名側別**：缺口模板是「改 {f} 時 {g} 不在…」，裸檔名會同時吞下
         # f 側與 g 側。這一格宣告的是「把該檔從 paths 拿掉」，期望 f 側。
         '不在任何 CI workflow 跑'),
    # **合併之後這一格的語意變了**（#432）：CI 只剩一個 step，拿掉它等於停用
    # **整批** 21 支，而不是一支。所以期望從「具名某一支」改成「每一條缺口都是
    # CI 涵蓋缺口」——`case()` 仍然要求全部同類，鑑別力沒有降低，只是類別變粗。
    #
    # **這是合併的真實代價，寫出來而不是假裝沒發生**：先前「一支守衛從 CI 掉了」
    # 與「整個守衛階段掉了」是兩種可分辨的故障，現在它們在 CI 側無法區分。
    # 換來的是 hook 與 CI 不再有兩份會分岔的清單。
    case('從 workflow 拿掉守衛階段（整批不再被執行）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh', 'run: true  # 被拿掉了')},
         '不在任何 CI workflow 跑'),
    # 下面兩格是 #407 R20 跨模型審查實測到的**假陰性**——修法之前這兩種狀態
    # 都讓守衛報綠而它宣稱的性質為假。
    case('把守衛清單裡的一支換成只提到它的註解',
         {'.githooks/run-guards.sh': lambda t: t.replace(
             'bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n',
             '# TODO: 之後再接 plugin/skills/akashic-literal-campaign/'
             'scripts/tests/store-marker-parity.sh\n')},
         'store-marker-parity.sh 不在 pre-push 裡'),
    case('把 workflow 的一個 run: 換成只印檔名的 echo',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: echo "見 .githooks/run-guards.sh 的說明"')},
         '不在任何 CI workflow 跑'),
    # 同一個 echo 但用 `./` 形式。R20 只修了直譯器那半邊（`bash X`），
    # `./X` 分支照舊掃全行——這一格是那個殘留的負控（#407 R20c）。
    # #407 R23b：`bash --version` 是 CI 極常見的環境檢查。判準若問「引數裡有
    # 沒有非旗標的東西」，它會被當成 stdin 執行而印假警報。改成問**位置**
    # （只有管線下游才是 stdin 執行）之後靜默——這一格用一個真的管線執行
    # 證明揭露仍然會發生，兩者的差別就是那個位置。
    case('把 run: 換成 `cat <守衛> | bash`（管線下游的裸直譯器）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: bash --version && cat .githooks/run-guards.sh | bash')},
         '不在任何 CI workflow 跑'),
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
             'run: bash .githooks/run-guards.sh',
             'run: test -f /nonexistent || bash plugin/tests/rule-coverage.sh')},
         '不在任何 CI workflow 跑'),
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
             'run: bash .githooks/run-guards.sh',
             'run: cat .githooks/run-guards.sh | bash')},
         '不在任何 CI workflow 跑'),
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
    # #407 R27：整行就是宣告卻**少了註解標記** → DECLARE 不匹配、宣告完全啞掉，
    # 而輸出與「這個守衛沒有宣告任何依賴」逐字相同。實地踩到（decision-matrix-drift
    # 的宣告寫在 docstring 裡沒加 `#`，覆蓋表照樣印全綠）。既有的「有宣告但解析不到」
    # 那條擋不住這種——它的前件就是 DECLARE 匹配。
    case('啞宣告①：少了註解標記',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\ntrigger-coverage: reads plugin/rules/*.md', 1)},
         '這一行是啞的'),
    # #407 R28：另外三種同樣安靜的啞法。上一版的謂詞只認第①種。
    case('啞宣告②：行尾多一句註記（DECLARE 要求行尾就結束）',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md  # 新增', 1)},
         '這一行是啞的'),
    case('啞宣告③：沒給 glob',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash', '#!/bin/bash\n# trigger-coverage: reads', 1)},
         '這一行是啞的'),
    # #407 R30：標記多一個字元就對兩個謂詞同時隱形。`///` 是 Swift 慣用的 doc
    # comment，而 GUARDS 含 `.swift`——不是杜撰的邊界。
    case('啞宣告⑤：Swift 的 `///` doc comment',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n/// trigger-coverage: reads plugin/rules/*.md', 1)},
         '這一行是啞的'),
    case('啞宣告⑥：shell 的段標 `##`',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n## trigger-coverage: reads plugin/rules/*.md', 1)},
         '這一行是啞的'),
    case('啞宣告④：關鍵字打成 read',
         {'plugin/tests/review-claim-audit.sh': lambda t: t.replace(
             '#!/bin/bash',
             '#!/bin/bash\n# trigger-coverage: read plugin/rules/*.md', 1)},
         '這一行是啞的'),
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
    # #407 R43：把單行 `run:` 改成 block scalar 之後，守衛仍須看得到那個呼叫。
    # 先前只讀單行形式（並以揭露交代），而揭露擋不住它咬人——實地把一個步驟改成
    # 區塊形式處理 exit 2，覆蓋表立刻報 11 個缺口，而呼叫就寫在區塊裡。
    case('把某個守衛改成 block scalar 形式呼叫（續行要讀得到）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: |\n          set -e\n          echo 開始\n'
             '          python3 plugin/tests/DELETED-numbers-audit.py', 1)},
         '不在任何 CI workflow 跑'),
    # #407 R44：heredoc 主體是**寫進檔案的字面文字**，不是被執行的命令。不擋的話
    # 會產生**假綠**（方向與本函式其餘刻意選的漏報相反）。
    case('把守衛名字藏進 heredoc 主體（不得算成有跑）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             "run: |\n          cat > /tmp/w.sh <<'EOF'\n"
             "          python3 plugin/tests/measured-numbers-audit.py\n"
             "          EOF\n          chmod +x /tmp/w.sh", 1)},
         '不在任何 CI workflow 跑'),
    # #407 R45：heredoc 的結束字帶非字元（`SETUP-EOF`）時，上一版只抓到 `SETUP`，
    # 於是結束行永遠對不上、其後整段被吞——**真的呼叫因此隱形**。這個 case 把一個
    # 守衛的呼叫放在這種 heredoc **之後**，它必須仍然被看見。
    case('heredoc 結束字帶連字號，其後的真呼叫不得被吞掉',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             "run: |\n          cat > /tmp/s.sh <<SETUP-EOF\n          echo hi\n"
             "          SETUP-EOF\n"
             "          python3 plugin/tests/DELETED-numbers-audit.py", 1)},
         '不在任何 CI workflow 跑'),
    case('把 run: 換成 shellcheck（靜態檢查，不執行守衛）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: shellcheck plugin/tests/rule-coverage.sh')},
         '不在任何 CI workflow 跑'),
    # #407 R22c 量測到的兩個零可見度形式。管線先前完全不在切分符裡，於是
    # `cat x | bash <守衛>` 的守衛既不進 found 也不進 chained。
    case('把 run: 改成管線形式（`cat x | bash <守衛>` 後半換成 echo）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: cat /dev/null | echo "見 plugin/tests/rule-coverage.sh"')},
         '不在任何 CI workflow 跑'),
    case('把 run: 換成印出 ./ 形式檔名的 echo（R20 修法的殘留半邊）',
         {'.github/workflows/plugin-guards.yml': lambda t: t.replace(
             'run: bash .githooks/run-guards.sh',
             'run: echo "見 ./.githooks/run-guards.sh 的說明"')},
         '不在任何 CI workflow 跑'),
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
             'run: bash .githooks/run-guards.sh',
             'run: bash scripts/setup.sh && echo "見 plugin/tests/rule-coverage.sh"')},
         '不在任何 CI workflow 跑'),
    # DA 席指名（#407 R21d）：收窄 DECLARE 擋不住**獨立成行的教學範例**——
    # 一行真實格式的示範會完整匹配。當時沒再撞到是因為我手動把本檔的範例改成
    # 佔位形式，那是一次性遮蔽不是機制。這一格證明「一個守衛只該有一條宣告」
    # 那道防線會接住它。
    case('在真宣告旁邊多寫一行教學範例（DA 指名的類別）',
         {'plugin/tests/rule-coverage.sh': lambda t: t.replace(
             '# trigger-coverage: reads plugin/rules/*.md',
             '# trigger-coverage: reads plugin/rules/*.md\n'
             '# trigger-coverage: reads plugin/rules/*.md')},
         # R48 起判準從「多於一行」換成「重複的樣式」——`measured-numbers-audit.py`
         # 真的需要兩條（兩個路徑根），而教學範例最可能的形狀就是把既有那條再抄一次。
         '重複的宣告樣式'),
    # R48：兩條**不同**路徑根的宣告是合法的（第一個真實例）。這一格證明放寬之後
    # 它不再被誤擋——**須綠**，所以用 warn_case 的反面：直接斷言基線仍然無缺口。

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
