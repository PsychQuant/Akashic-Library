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

# 兩個目錄都要宣告——程式 glob 的是兩個，而上一版只宣告了一個，於是
# `.claude/rules/*.md` 那半邊的依賴從未被覆蓋檢查看見（#407 R48，跨模型審查指名）。（private repo，外部讀者取不到））
# trigger-coverage: reads plugin/rules/*.md
# 第二條指向 `.claude/rules/*.md`（private repo，外部讀者取不到）。
# （該目錄在 private repo，外部讀者取不到。）
# trigger-coverage: reads .claude/rules/*.md
# trigger-coverage: reads CLAUDE.md
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


# ── 標題宣稱的列數 vs 表的實際列數（#407 R67d）────────────────────────────────
# 規則檔常在標題裡寫「封閉列舉——現有 N 列，一列不多一列不少」。那個 N 與下方的表
# **是兩份會分岔的規格**——本檔要求「實測數字要有錨」，而這是同一個病的另一種形式：
# 數字寫在標題裡，錨就是它正下方那張表，而沒有東西在比對。
#
# **實測抓到的實例**：`zero-instance-guards.md` 宣稱「現有 3 列」而表有 5 列——它在
# 表長到第 4 列時就已經過期，沒有任何跡象。所以這不是零實例守衛，不必進那份裁決表。
#
# **前件是量出來的，不是想出來的**（該規則第 2 列的教訓）：寬版謂詞（任何行的
# 「只有 N 條」）在 9 處宣稱裡報 2 個不符，其中 1 個是誤傷——`mcp-cli-parity.md` 的
# 散文「只有一條」被 10 行外的表誤配。收窄成**只認標題行**後：3 處受檢、1 處不符、
# 零誤傷。標題是宣告表的邊界的地方，散文不是。
_COUNT = re.compile(r'(現有|恰|共)\s*([0-9０-９一二三四五六七八九十]+)\s*(列|項|條|格)')
_CN = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8,
       '九': 9, '十': 10, '十一': 11, '十二': 12, '十三': 13, '十四': 14, '十六': 16}


def _num(s):
    s = s.translate(str.maketrans('０１２３４５６７８９', '0123456789'))
    return int(s) if s.isdigit() else _CN.get(s)


def _rows_after(lines, i):
    """i 之後最近的 markdown 表有幾個資料列（找不到回 None——不是 0）。

    回 None 而不是 0，是因為「標題後沒有表」與「表有 0 列」是兩件事，而把它們
    折成同一個值會讓前者被當成不符。`lossless-intake` 的「靜默是最糟的形式」。
    """
    for j in range(i, min(i + 40, len(lines))):
        if re.match(r'^\|[-\s|:]+\|\s*$', lines[j]):
            k, rows = j + 1, 0
            while k < len(lines) and lines[k].lstrip().startswith('|'):
                rows += 1
                k += 1
            return rows
    return None


def declared_counts(files, root):
    out = []
    for fp in files:
        lines = io.open(fp, encoding='utf8').read().splitlines()
        for i, line in enumerate(lines):
            if not line.lstrip().startswith('#'):
                continue
            for m in _COUNT.finditer(line):
                n = _num(m.group(2))
                if n is None:
                    continue
                rows = _rows_after(lines, i)
                out.append((os.path.relpath(fp, root), i + 1, m.group(0), n, rows))
    return out


def main():
    # 刻意**不收** root 參數。ROOT 由 `__file__` 推出，所以 negative control 跑 copy
    # 裡的那一份時它自然指向 copy——不需要參數。加一個沒有呼叫端的參數就是假接口
    # （本 issue 具名過的 `derive-hash-extenders.swift --check` 同型），而假接口的
    # 退場方式是刪掉，不是留著（`no-compat-fallback` 的「退場即刪」）。
    root = ROOT
    # **CLAUDE.md 也要掃**（#407 R67g）：它是每個 session 都被自動注入的檔案，所以
    # 一個過期的實測數字在那裡的影響面比任何規則檔都大——它會出現在往後每一輪的
    # context 裡，而讀者沒有理由懷疑它。實測缺口很小（2 處「實測 <數字>」、1 處裸），
    # 但小不是不掃的理由：小才表示現在補的成本低。
    # **逐來源檢查，不看聯集**（#407 R67g）：加入 CLAUDE.md 之後，原本那個
    # 「一個都沒找到就報錯」的檢查會被它撐著——兩個 rules 目錄整個消失時聯集仍非空，
    # 於是路徑打錯或規則被搬走**不會有任何跡象**。這與 `trigger-coverage` 當初從
    # 「聯集」改成「逐對」是同一個修正：聯集會掩蓋掉個別來源的歸零。
    sources = {
        '.claude/rules/*.md': glob.glob(os.path.join(root, '.claude/rules/*.md')),
        'plugin/rules/*.md': glob.glob(os.path.join(root, 'plugin/rules/*.md')),
        'CLAUDE.md': glob.glob(os.path.join(root, 'CLAUDE.md')),
    }
    empty = [k for k, v in sources.items() if not v]
    if empty:
        for k in empty:
            print(f'✗ 在 {root} 底下 `{k}` 一個檔都沒找到——路徑錯了還是被搬走了？')
        return 1
    files = sorted(f for v in sources.values() for f in v)

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
    counts = declared_counts(files, root)
    drift = [c for c in counts if c[4] is not None and c[3] != c[4]]
    noflag = [c for c in counts if c[4] is None]
    print(f'\n══ 標題宣稱的列數：共 {len(counts)} 處 ══')
    for rel, i, txt, n_, rows in drift:
        print(f'  ✗ {rel}:{i} 標題說「{txt}」而下方的表有 {rows} 列')
    for rel, i, txt, n_, rows in noflag:
        print(f'  ✗ {rel}:{i} 標題說「{txt}」但其後 40 行內找不到表——錨不存在')
    if not drift and not noflag:
        print(f'  {len(counts)} 處全部與其下方的表相符')

    print(f'\n══ {"無裸數字" if not bare else f"**{len(bare)} 個裸數字**"}'
          f'｜{"列數宣稱皆相符" if not (drift or noflag) else f"**{len(drift) + len(noflag)} 處列數不符**"} ══')
    return 1 if (bare or drift or noflag) else 0


if __name__ == '__main__':
    sys.exit(main())
