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


def run(root):
    cmd = [sys.executable, GUARD, '--root', root]
    if os.path.isfile(VENUE):
        cmd += ['--venue', VENUE]
    r = subprocess.run(cmd, cwd=PLUGIN, capture_output=True, text=True)
    return r.returncode, r.stdout


def with_copy(mutated_rule):
    """複製整個 plugin 樹到 tempdir、換掉規則檔、跑守衛。出貨檔完全不碰。"""
    with tempfile.TemporaryDirectory(prefix='prose-mut-') as tmp:
        root = os.path.join(tmp, 'plugin')
        shutil.copytree(PLUGIN, root)
        io.open(os.path.join(root, RULE_REL), 'w', encoding='utf8').write(mutated_rule)
        return run(root)


def report(out, n, desc):
    red = re.search(rf'^\[{n}\] FAIL', out, re.M) is not None
    print(f'{"✓" if red else "✗"} {desc} → 第 {n} 項 '
          f'{"變紅" if red else "沒紅 ← 守衛對它是盲的"}')
    return red


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
    append('見 [那條規則](.claude/rules/identity-is-judged-not-matched.md)。',
           1, '加一個可跟隨的 repo 連結（private repo 的 404 ＝ 假訊號）'),
    # 第 1 項先前只認四種形狀中的兩種——這一格注入的正是另外兩種之一。
    append('見 [那個型別](Sources/AkashicCore/Venue.swift)。',
           1, '加一個指向 Sources/ 的可跟隨連結（前一版的謂詞漏掉這種）'),
    append('判準寫在 `.claude/rules/identity-is-judged-not-matched.md`。',
           2, '加一句未揭露取用限制的 repo 專屬路徑'),
    append('本規則採三分法。', 3, '把被打掉兩次的分類法用語加回來'),
    append('三筆都回傳了 volume／issue。', 4, '把被同段證據否證的假全稱句放回引號外'),
    swap('實測**六值**', '實測**三值**', 5, '把 VenueType 的數量宣稱改錯'),
    # 只驗數量的謂詞對這一格全綠——R6 finding 27 指名的真缺陷。
    swap('`periodical`／`conference`／`publisher`／`database`／`socialMedia`／`website`',
         '`journal`／`conference`／`publisher`／`database`／`socialMedia`／`website`',
         5, '把值域裡的一個值改成已被更名的舊值'),
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
