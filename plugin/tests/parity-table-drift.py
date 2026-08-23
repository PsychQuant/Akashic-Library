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
        mm = re.search(r'struct\s+' + t + r'\s*:.*?commandName:\s*"([^"]+)"', srcs, re.S)
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
        mm = re.search(r'struct\s+' + t_ + r'\s*:.*?commandName:\s*"([^"]+)"', srcs, re.S)
        if mm:
            live.add(mm.group(1))
    for struck, name in re.findall(r'^\|\s*(~~)?`([a-z][a-z0-9-]*)`(?:~~)?', rule, re.M):
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
