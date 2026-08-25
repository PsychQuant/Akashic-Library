#!/usr/bin/env python3
"""plugin.json 宣告的 store format 必須等於 `StoreVersion.supported`（#408）。

**為什麼需要守衛而不是刪掉那個數字。** issue 立案時實測落後兩版（宣告 10、實際 12），
而在它開著的期間**又漂了一版**（13）——三次漂移、零次被發現。那正是本 repo 反覆記過的
形狀：一份規格的兩個副本必然分岔，而分岔是**安靜**的。

刪掉數字也能消除分岔，但那會丟掉一個真的資訊：marketplace 讀者藉它知道這個 MCP 認得
哪個 store 世代。#407 從 `Sources/` 拔掉四份寫死清單時，判準是「那份副本沒有獨立價值」；
這裡有，所以答案是**接上唯一來源**而不是刪除。

守衛刻意**不寫死 13**——寫死就是製造第三份副本，而它會與另外兩份分岔。
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

def fail(msg):
    print(f"✗ {msg}", file=sys.stderr); sys.exit(1)

src = (ROOT / "Sources/AkashicStoreIO/StoreVersion.swift").read_text(encoding="utf8")
m = re.search(r"public static let supported\s*=\s*(\d+)", src)
if not m:
    fail("讀不到 StoreVersion.supported——本守衛的前提不成立（宣告形式改了？）")
supported = int(m.group(1))

# **副本有三份不是兩份**（#408 verify R6）。第三份是 `mcpb/manifest.json`——它不是文件
# 而是**出貨物**：`scripts/release-signed.sh` 把它 zip 進 `.mcpb`，那是 Claude Desktop
# 一鍵安裝時顯示的 description。第一版只接上兩份，而守衛會印一個綠勾——
# **一個綠燈指認「漂移這個類別已經關閉」，而它其實只關閉了三分之二**。
DECLARERS = [
    "plugin/.claude-plugin/plugin.json",   # marketplace 顯示
    "mcpb/manifest.json",                  # Claude Desktop 一鍵安裝的出貨物
]

bad = []
for rel in DECLARERS:
    f = ROOT / rel
    if not f.exists():
        fail(f"{rel} 不存在——本守衛的宣告來源清單過期了（檔案搬走或刪除？）")
    d = re.search(r"Store format (\d+)\.", f.read_text(encoding="utf8"))
    if not d:
        fail(f"{rel} 的 description 找不到 `Store format N.`——"
             "若刻意移除該宣告，請一併把它移出本守衛的 DECLARERS（no-compat-fallback:退場即刪）")
    if int(d.group(1)) != supported:
        bad.append((rel, int(d.group(1))))

if bad:
    lines = "\n".join(f"    {rel}: 宣告 {n}" for rel, n in bad)
    fail(f"store format 宣告與唯一來源不一致（StoreVersion.supported = {supported}）:\n{lines}\n"
         f"  **兩個方向都要考慮**:若上面那些數字是舊的,改它們;\n"
         f"  若你剛 bump 了 format 而忘了同步,那也是同一個訊號——先確認 {supported} 是對的。\n"
         f"  mcpb/manifest.json 是**出貨物**（release-signed.sh 會 zip 進 .mcpb），\n"
         f"  它說謊的對象是 Claude Desktop 的安裝者。")

print(f"✓ {len(DECLARERS)} 份宣告與 StoreVersion.supported 一致（format {supported}）")
