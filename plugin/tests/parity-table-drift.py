#!/usr/bin/env python3
"""`mcp-cli-parity.md` 的封閉列舉 vs 程式碼實際有的東西。

**為什麼有這支**（#407 R50）：那條規則自帶一段「怎麼機械檢查這張表真的封閉」的稽核
程序——四個步驟、指令都寫好了——而**從來沒有任何東西執行它**。跨模型審查的完整性
批判把它列為「最可能讓真缺陷無聲出貨」的一格：新增一個 MCP tool 或 CLI subcommand
而忘了補表，15 支守衛全綠、`swift test` 全綠，封閉列舉的宣稱就安靜變假。

當下實測**兩側都同步**（MCP 30＝30 零差集、43 個 subcommand 全部出現在規則裡），
所以這是零實例守衛。裁決「寫」的理由：規則自己命令要稽核、指令現成、而失敗安靜。

**誠實邊界（三條）**：

  · **MCP 面是嚴格集合相等**（表的第一欄 vs `Tool(name:)`），兩個方向都驗。
  · **CLI 面只驗「命令名出現在規則檔裡」**，不驗它落在**哪一張**表、也不驗那一列的
    裁決內容對不對。理由：三張表的欄位形狀不同（命令名有時在第一欄、有時在「CLI 對應」
    欄、有時在劃掉的退場列裡），而把「哪一欄算數」寫死會比它要防的漂移更脆弱。
    **這比規則要求的弱**——規則要的是「落在某一張表的某一列」，本支只保證「被提到」。
  · **不驗裁決是否正確**（那要人判斷）。本支只擋「整個沒被提到」。
  · **②b 把第一欄反引號內容的第一個詞當命令名，這在編輯時可能誤擋**（#407 R54，
    跨模型審查指名的潛在情形）：`view`（list／show）那一列若被拆成兩列 `list`／`show`
    ——一次**純編輯**的精確化，`CLI.swift` 完全沒動——②b 會把兩者都當成「退場了卻沒
    劃掉」而報紅。**裁決：接受。** 失敗方向是**可見且可逆**的誤擋（改動當下就紅、
    訊息具名、改回或調整表即可），而收窄成「只看某一張表的某一欄」會比它要防的漂移
    更脆弱——這正是本檔第二條邊界的同一個理由。與規則檔自己記過的不對稱一致：
    誤擋可見可逆，漏報安靜。

# trigger-coverage: reads .claude/rules/mcp-cli-parity.md
# （該檔在 private repo，外部讀者取不到。）
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
RULE = '.claude/rules/mcp-cli-parity.md'
SERVER = 'Sources/akashic-mcp/Server.swift'
CLI = 'Sources/akashic/CLI.swift'


def _command_name(type_name, srcs):
    """抽某個 struct 的 `commandName`，**用大括號配對界定它自己的本體**。

    演化（兩步，都是被實測逼出來的）：

      R54  `struct T\\s*:.*?commandName:` ＋ DOTALL —— `T` 本體裡沒有 `commandName:`
           時（例如寫在 extension），非貪婪的 `.*?` 會走過 `T` 的定義綁到**下一個**
           struct 的值，靜默貼錯標籤。
      R54b 改成「到下一個 `struct ` 宣告為止」——**仍然不是 scope-aware**：實測
           `CreateEntryCmd` 的區段終止在它**自己巢狀的** `struct EntryDraft`（#407
           R55，跨模型審查指名）。今天無害（`commandName` 在巢狀型別之前），但把
           巢狀型別上移一行就會讓抽取回 `None`，而訊息會去怪稽核程序自己。
      R55  **大括號配對**：從 `T` 的 `{` 數到它的 `}`。巢狀型別、中間夾 `enum`、
           extension 都不再影響邊界。

    誠實邊界：字串／註解裡的大括號會讓計數失準。Swift 原始碼裡這在**宣告區**極少見，
    而失敗方向是區段過長或過短——過短會回 `None`（出聲），過長退化成上一版的行為。
    """
    m = re.search(r'struct\s+' + re.escape(type_name) + r'\b[^{]*\{', srcs)
    if not m:
        return None
    depth, i = 1, m.end()
    while i < len(srcs) and depth:
        if srcs[i] == '{':
            depth += 1
        elif srcs[i] == '}':
            depth -= 1
        i += 1
    return re.search(r'commandName:\s*"([^"]+)"', srcs[m.end():i])


def main():
    for p in (RULE, SERVER, CLI):
        if not os.path.exists(p):
            print(f'✗ 找不到 {p}——路徑變了還是檔案被搬走了？')
            return 1
    rule = io.open(RULE, encoding='utf8').read()
    fails = []

    # ① MCP：嚴格集合相等
    real = set(re.findall(r'Tool\(name: "(akashic_[a-z_]+)"',
                          io.open(SERVER, encoding='utf8').read()))
    listed = set(re.findall(r'^\| `(akashic_[a-z_]+)`', rule, re.M))
    if not real:
        fails.append('從 Server.swift 抽不到任何 `Tool(name:)`——抽取式與宣告寫法脫節了')
    for t in sorted(real - listed):
        fails.append(f'MCP tool `{t}` 在程式裡但**不在規則的 MCP 表**')
    for t in sorted(listed - real):
        fails.append(f'MCP 表列了 `{t}`，但程式裡**沒有這個 tool**')

    # ② CLI：subcommand 的 commandName 必須被規則提到
    cli = io.open(CLI, encoding='utf8').read()
    m = re.search(r'subcommands:\s*\[(.*?)\]', cli, re.S)
    if not m:
        fails.append('在 CLI.swift 找不到 subcommands 陣列——抽取式脫節了')
        types = []
    else:
        types = re.findall(r'([A-Za-z]+)\.self', m.group(1))
    srcs = '\n'.join(io.open(f, encoding='utf8', errors='replace').read()
                     for f in sorted(glob.glob('Sources/akashic/*.swift')))
    toks = set(re.findall(r'`([a-z][a-z0-9-]*)`', rule))
    unresolved = []
    for t in types:
        mm = _command_name(t, srcs)
        if not mm:
            # **抽不到要出聲，不可靜默跳過**——只在 happy path 正確的稽核，會在真正
            # 需要它時安靜少報一列（`mcp-cli-parity.md` 自己的 ② 記過同型：第一版
            # regex 只命中 11/30）。
            unresolved.append(t)
            continue
        if mm.group(1) not in toks:
            fails.append(f'CLI subcommand `{mm.group(1)}`（{t}）**規則檔裡完全沒提到**')
    for t in unresolved:
        fails.append(f'<未解析> {t} 抽不到 commandName——稽核程序自己壞了')

    # ②b **表 → 命令**方向（#407 R51，跨模型審查指名）。規則自己在 CLI-only 表下方
    #     寫了這個方向並附了觸發實例（#325 刪掉 `migrate-work-types`）：表裡提到的
    #     命令若已不存在，那一列**必須劃掉並標退場**，不得刪除（刪掉會丟失裁決史）。
    #     先前只做正向，於是一個**退場了卻沒劃掉**的孤兒列完全無聲。
    live = set()
    for t_ in types:
        mm = _command_name(t_, srcs)
        if mm:
            live.add(mm.group(1))
    # token 允許含空白與旗標（`export-tables --view`、`--library`）。上一版的
    # `[a-z][a-z0-9-]*` 在空白處斷掉，而 `^` ＋ MULTILINE 讓它每行只試一次——
    # 於是那些列**兩個失敗分支都看不到**（#407 R52，跨模型審查實測 `[]`）。
    # 取第一個詞當命令名；以 `-` 開頭的是橫切選項、不是 subcommand，跳過。
    for struck, raw in re.findall(r'^\|\s*(~~)?`([^`]+)`(?:~~)?', rule, re.M):
        name = raw.split()[0]
        # `akashic_*` 是 MCP tool 名（第一欄），由 ① 負責；`-` 開頭是橫切選項，
        # 由 ③ 負責。這裡只看 CLI subcommand。
        if name.startswith('-') or name.startswith('akashic_'):
            continue
        if struck and name in live:
            fails.append(f'表把 `{name}` 標成退場（劃掉），但它**仍註冊在 CLI.swift**')
        if not struck and name not in live:
            fails.append(f'表列了 `{name}` 而它**已不在 CLI.swift**——退場的列要劃掉'
                         f'並標明理由，不是留著不動')

    # ③ 橫切選項
    cross = set()
    for f in sorted(glob.glob('Sources/akashic/*.swift')):
        s = io.open(f, encoding='utf8', errors='replace').read()
        cross |= set(re.findall(r'struct ([A-Za-z]+):[^{]*\bParsableArguments\b', s))
    for c in sorted(cross):
        if c not in rule:
            fails.append(f'橫切 ParsableArguments `{c}` **不在規則的橫切選項表**')

    print(f'══ parity 表 vs 程式碼：MCP {len(real)}｜CLI {len(types)}｜橫切 {len(cross)} ══')
    for f in fails:
        print(f'  ✗ {f}')
    print(f'\n══ {"三面皆同步" if not fails else f"**{len(fails)} 處漂移**"} ══')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
