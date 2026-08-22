#!/bin/bash
# 生成的 `#` grapheme 表有沒有漂移。
#
# 為什麼存在
# ==========
# census 判「這一行是不是註解」要複製 Swift 的 `hasPrefix("#")` 語意，而那是
# grapheme cluster 比較；Python 標準庫沒有 grapheme 分段。
#
# #407 的第 9 輪用「general category ＋ 硬編範圍」近似，並在旁邊寫下「那正是分歧
# 的**充要**形狀」。跨模型審查把兩個方向都否證了——漏 103 個（讀端拒開的 store 被
# 印得跟健康的逐字相同）、多含 31 個（叫使用者去修一個完全健康的檔）。**再加幾段
# 是加不完的**：general category 與 Grapheme_Cluster_Break 不是同一張表。
#
# 所以那張表改由 Swift 自己列舉。而一張生成的表有它自己的失效模式：**Unicode 版本
# 一動它就過期，而過期是安靜的**。這支測試就是那個失效模式的守衛——重新生成一次，
# 與版控裡那份逐位元組比對。
#
# 用法
# ====
#   plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABLE="$HERE/../hash-merging-ranges.txt"
GEN="$HERE/derive-hash-extenders.swift"

[ -r "$TABLE" ] || { echo "✗ 讀不到生成的表：$TABLE" >&2; exit 2; }
[ -r "$GEN" ] || { echo "✗ 讀不到生成器：$GEN" >&2; exit 2; }
command -v swift >/dev/null || { echo "✗ 需要 swift 才能重新生成（此環境沒有）" >&2; exit 2; }

TMP=$(mktemp) || exit 2
trap 'rm -f "$TMP"' EXIT

swift "$GEN" > "$TMP" 2>/dev/null || { echo "✗ 生成器執行失敗" >&2; exit 2; }

# **census 的 ASCII 快速路徑依賴「表中沒有 ASCII range」**：它對 cp < 0x80 直接
# 回 True 而不查表。那句話在 R13 被量過（最小 range 起點 U+0300），但它的真假
# 依賴這張表——所以在這裡斷言，而不是只比對整份 diff。整份 diff 相同時這條當然
# 也成立；分開寫是為了讓失敗訊息指得出**是哪個性質**壞了。
# 不用 awk 的 strtonum（gawk 專屬，macOS 的 awk 沒有——實測它會印
# 「calling undefined function」到 stderr，**而檢查照樣通過**，因為變數是空的。
# 那是假綠，也正是本測試存在的理由的反面）。表中的 code point 是大寫十六進位，
# ASCII（< 0x80）只可能是一到兩位、且首位不超過 7，用行首樣式直接比對。
ASCII_ROWS=$(grep -E '^[0-7]?[0-9A-F] ' "$TABLE" || true)
if [ -n "$ASCII_ROWS" ]; then
  echo "✗ 表中出現 ASCII range——census 的 ASCII 快速路徑（cp < 0x80 直接回 True）失效：" >&2
  printf '%s\n' "$ASCII_ROWS" >&2
  exit 1
fi

if diff -q "$TABLE" "$TMP" >/dev/null; then
  # 反引號在雙引號內是命令替換——`\`#\`` 會展開成空字串（# 開頭即註解）。
  # 這一行原本印成「✓  grapheme 表…」，少了它要講的那個字元。
  echo "✓ '#' grapheme 表與本機 Swift 一致（$(grep -c '^[0-9A-F]' "$TABLE") 段）"
  exit 0
fi

echo "✗ 表已漂移——本機 Swift 列舉出的集合與版控裡那份不同。"
echo
diff "$TABLE" "$TMP" | head -20
echo
echo "  這通常代表 Swift／Unicode 版本變了。重新生成並檢查 census 的 fixture："
echo "    swift $GEN > $TABLE"
echo "    bash $HERE/store-marker-parity.sh"
exit 1
