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

pj = (ROOT / "plugin/.claude-plugin/plugin.json").read_text(encoding="utf8")
d = re.search(r"Store format (\d+)\.", pj)
if not d:
    fail("plugin.json 的 description 找不到 `Store format N.`——"
         "若刻意移除該宣告，請一併刪除本守衛（no-compat-fallback:退場即刪）")
declared = int(d.group(1))

if declared != supported:
    fail(f"plugin.json 宣告 Store format {declared}，而 StoreVersion.supported = {supported}。\n"
         f"  marketplace 讀者看到的是 description 的第一行,一個過期數字比不宣告更糟。\n"
         f"  修法:把 plugin.json 的數字改成 {supported}。")

print(f"✓ plugin.json 與 StoreVersion.supported 一致（format {supported}）")
