#!/usr/bin/env python3
"""每支守衛都必須在 **hook 實際使用的那個 Python** 下編得過（#394 verify R9）。

## 為什麼需要這支

`PrePushHookTests` 把 `PATH` 設成 `/usr/bin:/bin`——那裡的 `python3` 是 macOS 內建的
**3.9**，而開發者終端機上的 `python3` 是 homebrew 的 3.12+。兩者的**語法**不同：
PEP 701（f-string 內可換行、可用同款引號）是 3.12 才有的。

於是有一個完全安靜的失效模式：**守衛在我的終端機永遠通過，在 hook 裡是 SyntaxError**。

實測代價（#394 R9）：三次 push 失敗、三個被自己量測推翻的假設、約三小時的排除法，
根因是我在 R8 寫的**兩行**多行 f-string。而症狀極具誤導性——
失敗耗時各不相同（2857／911／1173 秒），因為卡的位置隨負載漂移。

## 這支查的是語法，不是行為

`py_compile` 只保證**解析得過**。一支用了 3.10+ **執行期**特性的守衛（例如
`match` 語句以外的新 stdlib API）仍可能在 3.9 下跑掛——那要靠實際執行才抓得到，
而實際執行 21 支守衛要一小時。**這裡刻意只做便宜的那一半**，並把限制寫出來。
"""
import glob, py_compile, subprocess, sys, tempfile, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(ROOT)
SYSTEM_PY = "/usr/bin/python3"

if not os.path.exists(SYSTEM_PY):
    print("✗ 找不到 %s——本守衛的前提（hook 用系統 Python）不成立" % SYSTEM_PY,
          file=sys.stderr)
    sys.exit(1)

ver = subprocess.run([SYSTEM_PY, "--version"], capture_output=True, text=True).stdout.strip()
targets = sorted(glob.glob(os.path.join(ROOT, "plugin/tests/*.py"))
                 + glob.glob(os.path.join(ROOT, "plugin/skills/*/scripts/tests/*.py")))
if not targets:
    print("✗ 一支守衛都沒找到——路徑改了？本檢查的前提不成立", file=sys.stderr)
    sys.exit(1)

bad = []
for t in targets:
    r = subprocess.run([SYSTEM_PY, "-m", "py_compile", t], capture_output=True, text=True)
    if r.returncode != 0:
        bad.append((os.path.relpath(t, ROOT), r.stderr.strip().split("\n")[-1]))

if bad:
    print("✗ 以下守衛在 %s 下解析不過（hook 用的就是它）：" % ver, file=sys.stderr)
    for f, e in bad:
        print("    %s\n      %s" % (f, e), file=sys.stderr)
    print("  多行 f-string 是 PEP 701（3.12+）。改用 %% 格式化或把運算式拉出來。",
          file=sys.stderr)
    sys.exit(1)

print("✓ %d 支守衛在 %s 下都解析得過" % (len(targets), ver))
