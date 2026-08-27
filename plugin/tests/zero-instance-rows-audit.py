#!/usr/bin/env python3
"""`zero-instance-guards.md` 的裁決表：每一列裁決「寫」的守衛，程式裡真的有嗎？

**為什麼有這支**（#407 R55）：那份規則的表是**一列一列裁決出來的**封閉列舉，而
**沒有任何東西**在確認「裁決寫了守衛的那些列，守衛真的存在」。第三次完整性批判把它
列為下一格——與 `mcp-cli-parity`（已由 `parity-table-drift.py` 守）和
`entity-backlink-completeness`（已由 `backlink-field-ratchet.py` 守）**同一個形狀**。

**判準**：表裡每一列都引一個 issue 編號（`#253`／`#254`／`#326`／`#367`）。裁決是
✅「寫」的列，那個編號必須出現在 `Sources/` 底下——也就是那個守衛真的被實作了。

**誠實邊界（三條）**：

  · **只驗編號在場，不驗守衛做的事對不對**（那要人判斷，正是該規則保留給人的部分）。
  · **編號可能因別的理由出現在 Sources**（例如某個註解提到它）。這是弱檢查——它擋的是
    「加了一列卻沒實作」與「實作被刪了而列還在」，不是「實作偏離了裁決」。
  · 裁決不是 ✅ 的列（若日後出現「不寫」的裁決）**不要求編號在場**——那正是它的意思。

**宣告要與它真的 glob 的那條一致**（#407 R55）：本支讀 `Sources/**/*.swift`，
上一版宣告成 `Sources/AkashicCore/*.swift`——雖然解析得到（`Venue.swift` 在
PROTECTED 裡），但守衛的痕跡檢查會警告，因為原始碼裡根本沒有 `AkashicCore` 這個詞。

# trigger-coverage: reads Sources/*/*.swift
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
RULE = '.claude/rules/zero-instance-guards.md'


def main():
    if not os.path.exists(RULE):
        print(f'✗ 找不到 {RULE}')
        return 1
    rule = io.open(RULE, encoding='utf8').read()
    # **排除由腳本生成的測試資料檔**（#433）：`AuditGuardsMutationsData.swift` 等是把
    # negative-control 的 mutation 字串資料化的產物，住在 `Sources/` 只因為 SwiftPM 要它
    # 在那裡才編得到——它們**不是實作**。
    #
    # 不排除的話這支必然誤判：其中一個 mutation 的內容正是「一個刻意不存在於 Sources 的
    # 編號」（`#9999`），資料化之後那個編號就真的出現在 `Sources/` 裡了，於是守衛說
    # 「找得到實作」而它其實只找到自己的測試資料。這不是理論邊界——它在資料化的當天就
    # 讓這一格從綠變紅。
    #
    # **判準是結構的**（檔頭的生成標記），不是列舉檔名——列舉會與下一個生成檔分岔。
    def _is_generated(text):
        return '本檔由腳本生成' in text[:600]
    _srcs = []
    for f in glob.glob('Sources/**/*.swift', recursive=True):
        _t = io.open(f, encoding='utf8', errors='replace').read()
        if not _is_generated(_t):
            _srcs.append(_t)
    src = '\n'.join(_srcs)
    rows = re.findall(r'^\| (\d+) \| (.*?) \| (.*?) \|', rule, re.M)
    if not rows:
        print('✗ 裁決表一列都沒讀到——抽取式與表的寫法脫節了')
        return 1

    fails = []
    for num, body, verdict in rows:
        issues = re.findall(r'#(\d{2,4})', body)
        if not issues:
            fails.append(f'第 {num} 列沒有引用任何 issue 編號——無從查證它是否被實作')
            continue
        if '✅' not in verdict:
            continue                      # 裁決不是「寫」→ 不要求實作在場
        absent = [i for i in issues if f'#{i}' not in src]
        if len(absent) == len(issues):
            fails.append(f'第 {num} 列裁決「寫」，但它引用的編號 '
                         f'{"／".join("#" + i for i in issues)} **在 Sources/ 裡都找不到**'
                         f'——守衛實作了嗎，還是被刪了而列還在？')

    print(f'══ zero-instance 裁決表：{len(rows)} 列 ══')
    for f in fails:
        print(f'  ✗ {f}')
    print(f'\n══ {"每一列裁決「寫」的都找得到實作" if not fails else f"**{len(fails)} 列有問題**"} ══')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
