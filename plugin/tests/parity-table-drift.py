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


def _struct_body(type_name, srcs):
    """回傳 `struct T` 的本體區段，**大括號配對時跳過字串與註解**。

    演化（三步，每一步都由實測逼出）：

      R54  `struct T\\s*:.*?commandName:` ＋ DOTALL → 沒有 `commandName:` 時走過 T。
      R54b 到下一個 `struct ` 宣告為止 → 終止在 T **自己巢狀的** struct。
      R55  大括號配對 → **仍然壞**：字串字面裡的 `"{"`／`"}"` 也被算進去。實測
           `CreateEntryCmd` 的區段長 **90,902** 字元，而
           `CreateEntryCommand.swift` 全檔只有 15,061——區段衝出檔案外六倍
           （#407 R58，跨模型審查指名；R55 的 docstring 自己預測過「失敗方向是
           區段過長」，而那句話當時已經是**現行事實**，不是預測）。
      R58  跳過 `"..."`（含跳脫）、`//` 到行尾、`/* */`，再數大括號。

    誠實邊界：**多行字串有處理**——上一版的 docstring 寫「六個命令檔目前都沒有」，
    而把那句話做成斷言時**當場被否證：實測 4 處**。原始字串（`#"…"#`）不處理，
    實測 **0 處**，由 `_no_exotic_strings` 守住（#407 R58）。
    的斷言）。
    """
    m = re.search(r'struct\s+' + re.escape(type_name) + r'\b[^{]*\{', srcs)
    if not m:
        return None
    depth, i, n = 1, m.end(), len(srcs)
    while i < n and depth:
        c = srcs[i]
        if srcs.startswith('\"' * 3, i):
            j = srcs.find('\"' * 3, i + 3)
            i = n if j < 0 else j + 3
            continue
        if c == '"':
            i += 1
            while i < n and srcs[i] != '"':
                i += 2 if srcs[i] == '\\' else 1
            i += 1
            continue
        if c == '/' and i + 1 < n and srcs[i + 1] == '/':
            while i < n and srcs[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and srcs[i + 1] == '*':
            j = srcs.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        i += 1
    return srcs[m.end():i]


def _no_exotic_strings(srcs):
    """`_struct_body` 的掃描器不處理**原始字串**——所以要**量**它不在場。

    docstring 若只寫「目前沒有」而不驗，那句話會在第一個人加進來時安靜變假
    （#407 R58）。回傳 `None` 表示乾淨，否則回傳要報的訊息。
    """
    raw = len(re.findall(r'#"', srcs))
    if raw:
        return (f'原始碼出現原始字串 `#"…"#`（{raw} 處）——`_struct_body` 的掃描器'
                f'不處理它們，區段可能算錯')
    return None


def _command_name(type_name, srcs):
    body = _struct_body(type_name, srcs)
    if body is None:
        return None
    return re.search(r'commandName:\s*"([^"]+)"', body)


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
    # **只認表列裡的 token**（#407 R59，跨模型審查列為 HIGH）：上一版只驗「命令名
    # 出現在規則檔裡」——散文任一處提到就算數，於是一個**沒有被裁決過**的命令只要
    # 在某段說明裡被提及就綠。收緊成「必須出現在某一行 `|` 開頭的表列裡」：實測 43
    # 個命令**全部**已在表列中，收緊零誤傷。仍不驗它落在**哪一張**表（那需要欄位
    # 形狀的假設，見上方第二條邊界）。
    rows_text = '\n'.join(l for l in rule.split('\n') if l.startswith('|'))
    toks = {t.split()[0] for t in re.findall(r'`([a-z][a-z0-9 -]*)`', rows_text)}
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

    exotic = _no_exotic_strings(srcs)
    if exotic:
        fails.append(exotic)

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
