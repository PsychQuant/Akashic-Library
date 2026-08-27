// **本檔由腳本生成，不要手改。** 來源：
//   plugin/skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py 的 `MUTATIONS`
//
// **為什麼機械抽而不是手抄**（#433）：那 14 個 mutation 全是**多行 Python 程式碼片段**，
// 而 `mutate()` 斷言原文片段必須在 census 裡**逐字唯一命中**——一個空白之差就中止。
// 手抄的錯誤率不可接受，而錯的方式是安靜的（片段對不上時 harness 直接 exit，看起來像
// census 改了）。`BacklinkRatchetData.swift` 的 113 個欄位是同一個手法的先例。
//
// 重新生成：見本檔在 #433 的 comment（`ast.literal_eval` 抽出 → Swift 字串字面）。

let markerParityMutationsTable: [(old: String, new: String, desc: String, expectCase: String)] = [
    (old: "            # grammar 不再跳過不認識的行。\n            return 'malformed', None, '(未知的頂層行)'",
     new: "            # grammar 不再跳過不認識的行。\n            continue",
     desc: "跳過未知頂層行（meta: { 繞法）",
     expectCase: "未知頂層行"),
    (old: "        if n < 1:\n            return 'malformed', None, f'(format: {n}——版號須 >= 1)'",
     new: "        if False:\n            return 'malformed', None, '(unreachable)'",
     desc: "format: 0 當成合法版號",
     expectCase: "format: 0"),
    (old: "        if found is not None:\n            return 'malformed', None, '(第二個 format: 行——歧義)'",
     new: "        if False:\n            return 'malformed', None, '(unreachable)'",
     desc: "重複 format: 行 last-wins",
     expectCase: "第二個 format"),
    (old: "        if rest and not _hr:\n            return 'malformed', None, '(format: 值後面不是註解)'",
     new: "        if False:\n            return 'malformed', None, '(unreachable)'",
     desc: "值後垃圾取前綴當真",
     expectCase: "format: 2.5"),
    (old: "    except UnicodeDecodeError:\n        # 讀端對此明文 throw malformed，訊息逐字是「(標記檔不是 UTF-8)」。\n        return 'malformed', None, '(標記檔不是 UTF-8)'",
     new: "    except UnicodeDecodeError:\n        raise",
     desc: "非 UTF-8 直接 traceback",
     expectCase: "非 UTF-8"),
    (old: "    except FileNotFoundError:\n        return 'absent', 1, ''",
     new: "    except FileNotFoundError:\n        return 'unreadable', None, '(ENOENT)'",
     desc: "缺檔誤標成讀不到",
     expectCase: "缺檔"),
    (old: "        if line_raw[:1] and line_raw[0] in _WS:\n            return 'malformed', None, '(縮排的非註解行)'",
     new: "        if False:\n            return 'malformed', None, '(unreachable)'",
     desc: "接受縮排的非註解行",
     expectCase: "縮排的 format 行"),
    (old: "            if ch not in '0123456789':",
     new: "            if not ch.isdigit():",
     desc: "數值解析認 Unicode 數字",
     expectCase: "全形數字"),
    (old: "        if n > 2 ** 63 - 1:\n            return 'malformed', None, '(format: 值超出 Int64——讀端的 Int() 回 nil)'",
     new: "        if False:\n            return 'malformed', None, '(unreachable)'",
     desc: "不設 Int64 上界",
     expectCase: "Int64 溢位"),
    (old: "_too_new = fmt_state == 'read' and _supported is not None and fmt > _supported",
     new: "_too_new = False",
     desc: "不偵測 tooNew",
     expectCase: "版號太新"),
    (old: "       '\\u200b'          # ← Foundation 有、Zs 沒有。整條註解存在的理由就是它\n",
     new: "       ''                 # mutation：拿掉 ZWSP\n",
     desc: "_WS 少掉 U+200B（退回 Zs 推導）",
     expectCase: "ZWSP 在 format: 之後"),
    (old: "    if not s.startswith('#'):\n        return False\n    if len(s) == 1:",
     new: "    if True:\n        return s.startswith('#')\n    if len(s) == 1:",
     desc: "註解判定退回 code-point 比較",
     expectCase: "# + combining acute"),
    (old: "    if _hash_table_error is not None:\n        return None\n    for lo, hi in _hash_ranges:\n        if lo <= cp <= hi:\n            return False\n    return True",
     new: "    import unicodedata as _u\n    if _u.category(s[1]) in ('Mn', 'Mc', 'Me'):\n        return False\n    if cp == 0x200D or 0xFE00 <= cp <= 0xFE0F:\n        return False\n    return True",
     desc: "退回 general category 近似（R9 的判準）",
     expectCase: "# + U+200C ZWNJ"),
    (old: "        text = raw_bytes.decode('utf-8-sig')",
     new: "        text = raw_bytes.decode('utf-8')",
     desc: "BOM 被當成未知頂層行",
     expectCase: "UTF-8 BOM"),
]

/// 供 baseline 訊息用——與上面那個陣列同源，不另寫一個數字。
let markerParityMutations_count = markerParityMutationsTable.count
