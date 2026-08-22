#!/usr/bin/env python3
"""規則檔裡的 `實測 <數字>` 必須有時間錨，或旁邊有可重跑的指令。

**為什麼有這支**（#407 R36）：跨模型審查指出一個沒有守衛涵蓋的類別——某條規則裡的
`實測 N` 隨語料變動而安靜過期。當輪先量類別大小而不急著造守衛；量到 15 個這種數字，
而其中一個是 `entity-backlink-completeness.md` 的「實測 6 筆」——**重跑得 31 筆，
該規則自己寫的兩個「重新裁決」觸發條件都早已成立而沒有人發現**。所以這不是零實例。

**判準（三選一即算有背書）**：

  1. 同一行有時間錨（`2026-08-23`／`當日`／`立案當時`／`#NNN`）
  2. 所在**小節的標題到該行之間**有時間錨——這些文件的日期常寫在小節開頭
  3. 前 4 行至後 8 行內有可重跑的指令（`grep`／`git`／`swift`…）

**誠實邊界（三條，都量過）**：

  · **觸發詞只認「實測」。** 換個寫法（「掃出」「目前有」「共 N 筆」）就逃掉。這是
    heuristic 不是覆蓋保證——本檔不主張它抓得到所有會過期的數字。
  · **它驗「有沒有時間錨」，不驗「數字對不對」。** 後者要重跑那些指令，而自動執行
    規則散文裡擷取出來的字串已經是本 issue 記過的缺陷（R7 的 `shell=True`）。
    entity-backlink 那個 31 筆是**人**重跑發現的，本支抓不到它。
  · **四位數年份不算數字**（`2026-08-12 的實測` 裡的 2026 是日期）。

# trigger-coverage: reads plugin/rules/*.md
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NUM = re.compile(r'實測[^。\n]{0,24}?(\d[\d,./]*)')
MARK = re.compile(r'20\d\d-\d\d-\d\d|20\d\d 年|當日|立案當時|#\d{2,4}')
CMD = re.compile(r'`[^`]*(?:grep|awk|sed|git |gh |python3|swift|bash|jq|wc |find |validate)[^`]*`')


def main():
    # 刻意**不收** root 參數。ROOT 由 `__file__` 推出，所以 negative control 跑 copy
    # 裡的那一份時它自然指向 copy——不需要參數。加一個沒有呼叫端的參數就是假接口
    # （本 issue 具名過的 `derive-hash-extenders.swift --check` 同型），而假接口的
    # 退場方式是刪掉，不是留著（`no-compat-fallback` 的「退場即刪」）。
    root = ROOT
    files = sorted(glob.glob(os.path.join(root, '.claude/rules/*.md'))
                   + glob.glob(os.path.join(root, 'plugin/rules/*.md')))
    if not files:
        print(f'✗ 在 {root} 底下一個規則檔都沒找到——路徑錯了還是規則被搬走了？')
        return 1

    total = 0
    bare = []
    for f in files:
        lines = io.open(f, encoding='utf8').read().split('\n')
        sec = 0
        for i, line in enumerate(lines):
            if line.startswith('#'):
                sec = i
            for m in NUM.finditer(line):
                if re.match(r'20\d\d', m.group(1)):      # 日期，不是計數
                    continue
                total += 1
                anchored = (MARK.search(line)
                            or MARK.search('\n'.join(lines[sec:i + 1]))
                            or CMD.search('\n'.join(lines[max(0, i - 4):i + 8])))
                if not anchored:
                    bare.append((os.path.relpath(f, root), i + 1,
                                 m.group(1), line.strip()[:60]))

    print(f'══ 規則檔的 `實測 <數字>`：共 {total} 個（{len(files)} 個檔）══')
    for rel, i, n, s in bare:
        print(f'  ✗ {rel}:{i} 「{n}」——沒有時間錨也沒有可重跑的指令\n     {s}')
    if not bare:
        print('  全部都有時間錨或可重跑的指令')
    print(f'\n══ {"無裸數字" if not bare else f"**{len(bare)} 個裸數字**"} ══')
    return 1 if bare else 0


if __name__ == '__main__':
    sys.exit(main())
