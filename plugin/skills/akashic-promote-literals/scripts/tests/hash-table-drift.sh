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
#   plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABLE="$HERE/../hash-merging-ranges.txt"
GEN="$HERE/derive-hash-extenders.swift"

[ -r "$TABLE" ] || { echo "✗ 讀不到生成的表：$TABLE" >&2; exit 2; }
[ -r "$GEN" ] || { echo "✗ 讀不到生成器：$GEN" >&2; exit 2; }
command -v swift >/dev/null || { echo "✗ 需要 swift 才能重新生成（此環境沒有）" >&2; exit 2; }

TMP=$(mktemp) || exit 2
MS_TMP=$(mktemp) || exit 2
TB_TMP=$(mktemp) || exit 2
trap 'rm -f "$TMP" "$MS_TMP" "$TB_TMP"' EXIT

swift "$GEN" > "$TMP" 2>/dev/null || { echo "✗ 生成器執行失敗" >&2; exit 2; }

# **census 的 ASCII 快速路徑依賴「表中沒有 ASCII range」**：它對 cp < 0x80 直接
# 回 True 而不查表。那句話在 R13 被量過（最小 range 起點 U+0300），但它的真假
# 依賴這張表——所以在這裡斷言，而不是只比對整份 diff。整份 diff 相同時這條當然
# 也成立；分開寫是為了讓失敗訊息指得出**是哪個性質**壞了。
# 不用 awk 的 strtonum（gawk 專屬，macOS 的 awk 沒有——實測它會印
# 「calling undefined function」到 stderr，**而檢查照樣通過**，因為變數是空的。
# 那是假綠，也正是本測試存在的理由的反面）。表中的 code point 是大寫十六進位，
# ASCII（< 0x80）只可能是一到兩位、且首位不超過 7，用行首樣式直接比對。
# `-i`：生成器目前印 `%X`（大寫），但這條守衛不該把「它剛好印大寫」當前提——
# 那正是本 issue 的形狀（一個沒被說出來的假設撐著一個檢查）。加一個字元即無關。
ASCII_ROWS=$(grep -Ei '^[0-7]?[0-9a-f] ' "$TABLE" || true)
if [ -n "$ASCII_ROWS" ]; then
  echo "✗ 表中出現 ASCII range——census 的 ASCII 快速路徑（cp < 0x80 直接回 True）失效：" >&2
  printf '%s\n' "$ASCII_ROWS" >&2
  exit 1
fi

# ── multiscalar-parity.swift 的 inline 副本 ────────────────────────────────
# 那支測試不能在執行期讀這張表（`swift <file>` 的 JIT 直譯模式下 Foundation 的
# 讀檔路徑會 crash），所以它把表**編進原始碼**。兩份 copy 會分岔，而分岔是安靜的：
# 過期的那份仍會跑完、仍會印 0 分歧，只是它驗的是**舊表**對 Swift 的**現行**行為。
#
# 這段是 #407 R18 補的。在此之前 multiscalar-parity.swift 的檔頭寫著「由
# tests/hash-table-drift.sh 的比對兜住」——而本腳本對 `multiscalar` 的命中數是 0。
# 那句話描述了一個不存在的守衛，寫在一個守衛檔案自己的檔頭上。
MS="$HERE/multiscalar-parity.swift"
if [ -r "$MS" ]; then
  # `(0x300,0x36F),` → `300 36F`。轉大寫後與表比（表由 `%X` 生成）。
  # **結尾逗號是可選的**——Swift 陣列的最後一個元素沒有它。第一版寫死 `),$`，
  # 於是漏掉最後一段，並把「我的抽取式太窄」報成「表分岔了」（#407 R18 當場踩到）。
  sed -n 's/^[[:space:]]*(0x\([0-9A-Fa-f]*\),0x\([0-9A-Fa-f]*\)),\{0,1\}[[:space:]]*$/\1 \2/p' \
    "$MS" | tr 'a-f' 'A-F' > "$MS_TMP"
  grep -v '^#' "$TABLE" > "$TB_TMP" || true
  if [ ! -s "$MS_TMP" ]; then
    # 抽不到任何一段 = 宣告寫法變了，而不是「剛好沒有」。**不得靜默通過**：
    # 那會讓這條守衛在最需要它的時候（有人改了 RANGES 的寫法）安靜消失。
    echo "✗ 從 multiscalar-parity.swift 抽不到任何 RANGES 段——抽取式已與宣告寫法脫節" >&2
    exit 1
  fi
  if ! diff -q "$TB_TMP" "$MS_TMP" >/dev/null; then
    echo "✗ multiscalar-parity.swift 的 inline RANGES 與生成的表不一致：" >&2
    diff "$TB_TMP" "$MS_TMP" | head -20 >&2
    echo >&2
    echo "  重新同步：把 $TABLE 的每一行改寫成 (0xLO,0xHI), 貼回該檔的 RANGES。" >&2
    exit 1
  fi
else
  echo "✗ 讀不到 multiscalar-parity.swift（inline 表無法比對）" >&2
  exit 2
fi

if diff -q "$TABLE" "$TMP" >/dev/null; then
  # 反引號在雙引號內是命令替換——`\`#\`` 會展開成空字串（# 開頭即註解）。
  # 這一行原本印成「✓  grapheme 表…」，少了它要講的那個字元。
  echo "✓ '#' grapheme 表與本機 Swift 一致（$(grep -c '^[0-9A-F]' "$TABLE") 段）"
  echo "✓ multiscalar-parity.swift 的 inline RANGES 與表一致"
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
