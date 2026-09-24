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
import json, pathlib, re, sys

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

# **第四份曾在另一個 repo**（#408 verify R7 ②）：psychquant-claude-plugins 的 marketplace
# 條目有一份人工複製的 description，實測寫著過期的 **Store format 10**，而 `/plugin` 顯示的
# 正是**那一份**。
#
# #625 起 marketplace 搬進本 repo（`.claude-plugin/marketplace.json`），外部條目移除，而本 repo
# 的條目**不帶** description。2026-09-24 實測（`claude plugin list --available --json`，探針
# marketplace 兩個條目對照）：條目沒寫時顯示回落到 plugin.json 的描述；條目有寫時**條目覆蓋**
# plugin.json。所以第四份不再存在——**前提是條目一直不帶 description**。下方把這個前提變成
# 一道會紅的檢查，而不是留一句註解：有人日後在條目加描述，就是重新製造那份會分岔的副本。
MARKETPLACE = ".claude-plugin/marketplace.json"

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

mk = ROOT / MARKETPLACE
if not mk.exists():
    fail(f"{MARKETPLACE} 不存在——本守衛的前提（marketplace 在本 repo）不成立")
with_desc = [p.get("name") for p in json.loads(mk.read_text(encoding="utf8")).get("plugins", [])
             if "description" in p]
if with_desc:
    fail(f"{MARKETPLACE} 的條目帶了 description：{with_desc}\n"
         f"  條目的描述會**覆蓋** plugin.json（2026-09-24 實測）——那就是第四份會分岔的副本。\n"
         f"  拿掉它，讓 /plugin 回落到 plugin.json。")

print(f"✓ {len(DECLARERS)} 份宣告與 StoreVersion.supported 一致（format {supported}）")
print(f"✓ {MARKETPLACE} 的條目不帶 description——/plugin 顯示的就是 plugin.json 那份")
