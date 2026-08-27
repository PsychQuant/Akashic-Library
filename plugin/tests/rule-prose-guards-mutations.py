#!/usr/bin/env python3
"""rule-prose-guards.py 的 negative control：證明每一項都會紅。

為什麼這支也要出貨
==================
與姊妹 harness 同一條紀律：**一個從沒紅過的檢查，和一個不存在的檢查，在報告上
長得一模一樣。** #407 的第五輪正是這個形狀——十三項驗收全綠，而把前一輪的原始
缺陷做成 mutation 一跑，13/13 完整存活。

這支腳本自己也證明了它的價值。撰寫至今，它抓到過四個謂詞的洞，每一個都是先看到
「沒紅」才知道：

  * 第 5 項第一版 `'六值' in rule_txt`——檔案別處還有「六值」，改掉一處照樣綠。
  * 第 5 項第二版：相關性與數字宣稱都看剝引號後的文字，於是一行若把 `VenueType`
    寫在引號內（失敗史必然如此），整行被判為不相關而跳過。
  * 第 5 項第三版：只驗值域的**數量**不驗**值**——把一個 case 改名（真缺陷）做成
    mutation，5/5 全綠。
  * 第 1 項：手寫了 REPO_ONLY 四種形狀中的兩種，指向另外兩種的可跟隨連結全綠。

**它 mutate 的是一份 copy，不是出貨檔**（#407 R7）
==================================================
前一版就地改寫版控中的規則檔——而規則檔是**公開 marketplace 的出貨物**，被注入的
內容是刻意造假的散文（「本規則採三分法」「三筆都回傳了 volume／issue」）。留在檔裡
就是把這條規則存在的理由反過來出貨。姊妹 harness 的同型缺陷在跨模型審查期間被**實際
觀察到**：兩分鐘內同一個 tracked 檔出現三種被注入的狀態。

三個缺口（無 finally／無鎖／無前置潔淨檢查）當時同時存在，而第三個讓失敗變成
**自我祝福**：第二個 process 讀到的「原檔」是已被注入的內容，快照算在壞檔上，
於是它的還原把 mutation 永久寫回，而 hash 比對通過。

**根治不是把三個缺口各補一塊，是不要碰原檔。** 現在整個 plugin 樹被複製到 tempdir，
mutation 只作用在 copy 上，守衛以 `--root <copy>` 指向它。

用法
====
    plugin/tests/rule-prose-guards-mutations.py
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.abspath(os.path.join(HERE, '..'))
GUARD = os.path.join(HERE, 'rule-prose-guards.py')
VENUE = os.path.abspath(os.path.join(PLUGIN, '..', 'Sources', 'AkashicCore', 'Venue.swift'))
RULE_REL = os.path.join('rules', 'assertions-must-be-measured.md')

SNAP = io.open(os.path.join(PLUGIN, RULE_REL), encoding='utf8').read()


# ── 遷移期：runner 跑的是 Swift 版，所以負控必須驗**它**（#433）──────────────
#
# 若這支仍只跑 `.py`，它驗的就是一個**不再被執行的實作**——負控全綠、runner 全綠，
# 而實際在跑的那一版沒有任何保證。那個缺口是遷移自己製造的，且它在對面兩支 harness 上
# 各抓到過真的翻譯遺漏。**兩版都跑並要求逐字一致**；刪掉 Python 版時把這一段拿掉即可。
#
# 這支不需要 source-injection 的豁免：mutation 只作用在 **copy 的 plugin 樹**上，
# 守衛自己（`GUARD` / binary）都在原位不被改寫。
GUARDS_BIN = os.path.abspath(os.path.join(PLUGIN, '..', '.build', 'debug', 'akashic-guards'))


def run(root):
    cmd = [sys.executable, GUARD, '--root', root]
    if os.path.isfile(VENUE):
        cmd += ['--venue', VENUE]
    r = subprocess.run(cmd, cwd=PLUGIN, capture_output=True, text=True)
    if os.path.exists(GUARDS_BIN):
        scmd = [GUARDS_BIN, 'rule-prose-guards', '--root', root]
        if os.path.isfile(VENUE):
            scmd += ['--venue', VENUE]
        rs = subprocess.run(scmd, cwd=PLUGIN, capture_output=True, text=True)
        if (rs.returncode, rs.stdout) != (r.returncode, r.stdout):
            raise SystemExit(
                f'✗ 遷移期兩版分岔：rule-prose-guards.py vs `akashic-guards rule-prose-guards`\n'
                f'  ── python rc={r.returncode}\n{r.stdout}\n'
                f'  ── swift  rc={rs.returncode}\n{rs.stdout}')
        return rs.returncode, rs.stdout       # 回傳**實際在跑的**那一版
    return r.returncode, r.stdout


def with_copy(mutated_rule):
    """複製整個 plugin 樹到 tempdir、換掉規則檔、跑守衛。出貨檔完全不碰。"""
    with tempfile.TemporaryDirectory(prefix='prose-mut-') as tmp:
        root = os.path.join(tmp, 'plugin')
        shutil.copytree(PLUGIN, root)
        io.open(os.path.join(root, RULE_REL), 'w', encoding='utf8').write(mutated_rule)
        return run(root)


def report(out, n, desc):
    """判準是**恰好**第 n 項紅，不是「第 n 項紅」。

    差別是鑑別力。一個注入若同時打紅第 n 與第 m 項，那麼「第 n 項紅」這個觀察
    就分不出「守衛 n 抓到了它」與「守衛 m 抓到了它、而 n 只是順帶」——它作為
    第 n 項的負控就不純。#407 R18 實測：四個宣告第 1 項的注入實際紅 [1, 2]，
    因為一個 markdown 連結同時是兩者的正例（可跟隨 ＋ 未揭露取用限制）。
    修法是讓那四格帶揭露詞，把它們收斂成只對第 1 項的正例。
    """
    reds = set(int(m) for m in re.findall(r'^\[(\d)\] FAIL', out, re.M))
    ok = reds == {n}
    if ok:
        print(f'✓ {desc} → 恰好第 {n} 項變紅')
    elif not reds:
        print(f'✗ {desc} → 第 {n} 項沒紅 ← 守衛對它是盲的')
    else:
        print(f'✗ {desc} → 宣告第 {n} 項，實際紅 {sorted(reds)} ← 注入不是外科手術式的')
    return ok


def append(extra, n, desc):
    _, out = with_copy(SNAP + '\n' + extra + '\n')
    return report(out, n, desc)


def swap(old, new, n, desc):
    if SNAP.count(old) != 1:
        sys.exit(f'✗ 錨點不唯一（{SNAP.count(old)} 次）：{desc}')
    _, out = with_copy(SNAP.replace(old, new, 1))
    return report(out, n, desc)


# baseline 必須先全綠——否則「注入後變紅」不代表任何事（R6 finding 11：前一版
# 從不檢查 baseline、也不看 return code，原守衛整片壞掉時它仍會 exit 0）。
_rc, _out = run(PLUGIN)
if _rc != 0:
    print(_out)
    sys.exit(f'✗ baseline 不是全綠（rc={_rc}）——先修守衛，negative control 在紅的 '
            f'baseline 上沒有意義')
print('baseline：5/5 ✓')
print()

RESULTS = [
    # **前四格都刻意帶「private／取不到」的揭露詞**——不是為了好看，是為了讓
    # 它們只當第 1 項的正例。不帶的話它們同時觸發第 2 項（提到 repo 路徑而未
    # 揭露），於是「第 1 項紅」分不出是誰抓到的（#407 R18 實測紅 [1, 2]）。
    append('見 [那條規則](.claude/rules/identity-is-judged-not-matched.md)（private repo，外部讀者取不到）。',
           1, '加一個可跟隨的 repo 連結（private repo 的 404 ＝ 假訊號）'),
    # 第 1 項先前只認四種形狀中的兩種——這一格注入的正是另外兩種之一。
    append('見 [那個型別](Sources/AkashicCore/Venue.swift)（private repo，外部讀者取不到）。',
           1, '加一個指向 Sources/ 的可跟隨連結（前一版的謂詞漏掉這種）'),
    # REPO_ONLY 有**四**個 alternation 分支，而這份負控先前只注入前兩個
    # （規則目錄與型別原始碼那兩種——這裡刻意不寫出路徑字面，那會觸發第 2 項）。
    # 它的 docstring 自己記載
    # 「手寫兩種形狀、另外兩種一路綠燈」發生過一次——而覆蓋率當時只修了一半：
    # 謂詞改成共用 REPO_ONLY 了，證明它四個分支都會紅的注入卻只有兩格。
    # 下面兩格補上第 3、4 個分支（#407 R18，跨模型審查指名）。
    append('見 [那份說明](docs/store-format.md)（private repo，外部讀者取不到）。',
           1, '加一個指向 docs/*.md 的可跟隨連結（REPO_ONLY 第 3 分支）'),
    append('見 [那一行](https://github.com/PsychQuant/Akashic-Library/blob/main/README.md)（private repo，取不到）。',
           1, '加一個 blob/ 深連結（REPO_ONLY 第 4 分支）'),
    append('判準寫在 `.claude/rules/identity-is-judged-not-matched.md`。',
           2, '加一句未揭露取用限制的 repo 專屬路徑'),
    # #407 R49：豁免只錨行首時，一條「宣告開頭 ＋ 後面還有別的東西」的行會逃掉
    # 揭露檢查卻不是真宣告。整行錨定之後它必須被擋回來。
    append('# trigger-coverage: reads plugin/rules/*.md, 順帶碰 .claude/rules/x.md',
           2, '偽裝成宣告的行（後面還有東西）不得逃掉揭露檢查'),
    append('本規則採三分法。', 3, '把被打掉兩次的分類法用語加回來'),
    append('三筆都回傳了 volume／issue。', 4, '把被同段證據否證的假全稱句放回引號外'),
    swap('實測**六值**', '實測**三值**', 5, '把 VenueType 的數量宣稱改錯'),
    # 只驗數量的謂詞對這一格全綠——R6 finding 27 指名的真缺陷。
    swap('`periodical`／`conference`／`publisher`／`database`／`socialMedia`／`website`',
         '`journal`／`conference`／`publisher`／`database`／`socialMedia`／`website`',
         5, '把值域裡的一個值改成已被更名的舊值'),
    # 第 6 項：把自我量測表裡「會長的數字」改回過期的值。這一格驗的正是
    # 2026-08-22 真實發生過的事——那張表的 parity 列停在 26、mutation 列停在
    # 11/11，而實測已是 46 與 14/14。**這不是零實例守衛**，是已發生的形狀。
    swap('**46** 格 fixture', '**26** 格 fixture', 6,
         '把自我量測表的 parity 格數改回過期的 26'),
    swap('**14/14**', '**11/11**', 6,
         '把自我量測表的 mutation 數改回過期的 11/11'),
    # 把自我量測表展示的指令換回**原缺陷那一條**（數整個檔案的 case 行 → 印 8）。
    # 前一版的謂詞另寫一套計數器，於是這個缺陷可以原封不動再犯（R6 finding 10）。
    swap("awk '/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} "
         "END{print n+0}' Sources/AkashicCore/Venue.swift",
         "awk '/^    case /{n++} END{print n+0}' Sources/AkashicCore/Venue.swift",
         5, '把展示的指令換回會算出 8 的原缺陷那一條'),
]



# ── 注入 PoC：證明那條執行路徑真的關著 ────────────────────────────────────
# 這一格與其他不同：它不只看守衛紅不紅，還看**副作用有沒有發生**。
#
# R7 的守衛把規則檔擷取出的字串交給 `subprocess.run(..., shell=True)`，旁邊註解
# 寫著「不執行任意擷取到的 shell」——那句話是假的。跨模型審查做出 PoC：payload
# 尾端補一個 `echo 6` 讓輸出等於預期值，守衛報 **5/5 PASS、exit 0**，同時以使用者
# 身分執行了注入的指令。觸發面是 pre-push hook 與 pull_request workflow，且本樹
# 經公開 marketplace 出貨。
#
# payload 的兩個細節照抄審查者的：排在合法那條**之前**（`re.search` 取第一個
# 命中），且該行要含揭露詞，否則會先被第 2 項擋掉而測不到第 5 項。
def injection_poc():
    with tempfile.TemporaryDirectory(prefix='prose-poc-') as tmp:
        root = os.path.join(tmp, 'plugin')
        shutil.copytree(PLUGIN, root)
        marker = os.path.join(tmp, 'SIDE_EFFECT')
        lines = SNAP.split('\n')
        lines.insert(1, '量測（repo 為 private，無存取權者跑不了）：'
                        "`awk 'BEGIN{print 6}' /dev/null; touch " + marker +
                        "; : Sources/AkashicCore/Venue.swift`")
        io.open(os.path.join(root, RULE_REL), 'w', encoding='utf8').write('\n'.join(lines))
        rc, out = run(root)
        executed = os.path.exists(marker)
        red = re.search(r'^\[5\] FAIL', out, re.M) is not None
        ok = (not executed) and red
        print(f'{"✓" if ok else "✗"} 注入 PoC → 副作用={executed}（必須 False）、'
              f'第 5 項{"變紅" if red else "沒紅"}、exit={rc}')
        return ok


RESULTS.append(injection_poc())

print()
print(f'=== negative control {sum(RESULTS)}/{len(RESULTS)} ===')
print(f'出貨檔未被開啟以寫入：{os.path.relpath(os.path.join(PLUGIN, RULE_REL), PLUGIN)}')
sys.exit(0 if all(RESULTS) else 1)
