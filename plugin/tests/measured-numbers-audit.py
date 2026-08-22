#!/usr/bin/env python3
"""規則檔裡的 `實測 <數字>` 必須有時間錨，或旁邊有可重跑的指令。

**為什麼有這支**（#407 R36）：跨模型審查指出一個沒有守衛涵蓋的類別——某條規則裡的
`實測 N` 隨語料變動而安靜過期。當輪先量類別大小而不急著造守衛；量到 15 個這種數字，
而其中一個是 `entity-backlink-completeness.md` 的「實測 6 筆」——**重跑得 31 筆，
該規則自己寫的兩個「重新裁決」觸發條件都早已成立而沒有人發現**。所以這不是零實例。

**判準（三選一即算有背書）**：

  1. 同一行有時間錨（`2026-08-23`／`當日`／`立案當時`／`#NNN`）
  2. 所在**小節的標題到該行之間**有時間錨——這些文件的日期常寫在小節開頭
  3. 前 4 行至後 8 行內有**可重跑的指令**——不只是工具名：還要含路徑分隔／管線／
     旗標／命令替換其中之一（#407 R39 收緊）

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
# **工具名不算配方**（#407 R39，跨模型審查指名）：前一版只要 backtick 裡出現關鍵字
# 就算有指令，於是 `` `akashic validate` `` ——一個沒有 store 路徑、沒有 filter、
# 貼進 shell 也重現不出那個數字的**工具名**——把一個會漂移的計數判成有背書。現在
# 另外要求它長得像**可貼進 shell 的一行**：含路徑分隔、管線、旗標、或命令替換。
# **反引號要在同一行內配對**（#407 R40，跨模型審查指名）：`[^`]*` 不排除換行，於是
# 一個沒有關鍵字的 inline code 的**收尾**反引號會被當成新的開頭，一路吃過表格好幾列，
# 直到下一個反引號——中間的中文散文含「通過 validate」與 markdown 的 `|`，於是整段被
# 判成「有可重跑的指令」。實測 `zero-instance-guards.md:22` 就這樣憑空產生一個
# 540→943 的 match。加 `\n` 到排除集合即讓它只在單行內配對。
_TOOL = r'(?:grep|awk|sed|git |gh |python3|swift|bash|jq|wc |find |validate)'
_RUNNABLE = r'[|/$-]'
# ① 同一行內的 inline code
CMD_INLINE = re.compile(r'`[^`\n]*' + _TOOL + r'[^`\n]*' + _RUNNABLE + r'[^`\n]*`')
# ② 圍籬區塊。**必須支援**：兩個真的可重跑的配方就寫在 ```bash 裡，而 inline 那條
#    看不到它們——先前它們「通過」靠的是①跨行誤配對出來的假 match（#407 R40）。
CMD_FENCE = re.compile(r'^[ \t>]*```[a-z]*\n(.*?)^[ \t>]*```', re.S | re.M)


def has_cmd(window):
    if CMD_INLINE.search(window):
        return True
    return any(re.search(_TOOL, b) and re.search(_RUNNABLE, b)
               for b in CMD_FENCE.findall(window))


def _unquote(line):
    """剝掉前導空白與 markdown 引用符，讓引用式圍籬也能被辨識。"""
    return re.sub(r'^[\s>]*', '', line)


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
        in_fence = False
        for i, line in enumerate(lines):
            # **引用式圍籬也要認**（#407 R47）：`lstrip()` 只剝空白，不剝 `>`，
            # 於是 `> ```bash` 這種寫法完全不切換狀態，區塊內容被當成散文。
            # 本檔掃描的兩個 rules 目錄現在**零實例**，但 CLAUDE.md 用過兩次，
            # 而失敗方向是**假陽性**（把有錨的數字報成裸的）——那會讓人去「修」
            # 一個不存在的問題，或乾脆停用守衛。成本一行，所以現在補。
            if _unquote(line).startswith('```'):
                in_fence = not in_fence
                continue
            # 圍籬區塊裡的行**本身就在配方中**（那個數字是指令旁的註解）。窗式偵測
            # 看不到它——窗從區塊中間開始時抓不到開頭的柵欄（#407 R40 實測：
            # `mcp-cli-parity.md` 的「實測：恰 30」就寫在 ```bash 內的註解行）。
            if in_fence:
                continue
            if line.startswith('#'):
                sec = i
            for m in NUM.finditer(line):
                if re.match(r'20\d\d', m.group(1)):      # 日期，不是計數
                    continue
                total += 1
                anchored = (MARK.search(line)
                            or MARK.search('\n'.join(lines[sec:i + 1]))
                            or has_cmd('\n'.join(lines[max(0, i - 4):i + 8])))
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
