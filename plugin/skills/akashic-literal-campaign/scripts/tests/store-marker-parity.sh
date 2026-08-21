#!/bin/bash
# literal-census.sh 的 store-marker 解析 vs 真正的讀端：**量測**，不是宣稱。
#
# 為什麼存在
# ==========
# census 的註解說它的 format 狀態「對照讀端」（AkashicStoreIO/StoreVersion.read）。
# 那是一句關於世界的斷言，而它曾經是假的：前一版只認 `^format:\s*(\d+)\s*$`，
# 跨模型審查實測出六種輸入形狀分歧，其中三種讓一個**讀端整體拒開**的 store 被 census
# 報成健康——而 campaign 的批次範圍就是照那個數字定的。
#
# 所以這支測試不驗「程式碼看起來對」，它驗**兩個實作對同一批輸入給出同樣的裁決**。
# oracle 是真的 CLI：`akashic` 的每個指令都經 openStore() → StoreVersion.check()，
# 所以任一讀取指令的 exit code 就是讀端對這個 store 的裁決。
#
# 這也是 #407 那條規則（斷言要先量測）對這支腳本自己的套用：註解裡那句「對照讀端」
# 現在有一個可重跑的東西支撐它，而不是只有作者讀過原始碼的印象。
#
# 用法
# ====
#   plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh
#
# 需要先 `swift build`（會自己找 .build/debug/akashic 或 .build/release/akashic）。
#
# **本測試需要 Akashic repo 的原始碼與 build 產物**：它讀 Sources/ 取支援上限、
# 並拿建出來的 CLI 當 oracle。**該 repo 為 private**，所以 plugin 單獨安裝的環境
# 跑不了這支測試——它出貨的目的是讓有 repo 的人能重跑那個等價性主張，而不是讓
# 每個使用者都跑得動。這個限制寫在這裡，免得「有測試」被讀成「你可以驗」。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../../../.." && pwd)
# --census <path>：讓 negative control 可以 mutate **一份 copy** 而不是出貨檔。
# 先前的 harness 就地改寫 tracked 的 literal-census.sh，審查期間被實際觀察到
# 兩分鐘內出現三種被注入的狀態。改成 mutate copy 之後，鎖／finally／前置潔淨
# 檢查三個缺口一次消失——它們防的是「原檔被改壞」，而原檔不再被碰。
CENSUS="$HERE/../literal-census.sh"
while [ $# -gt 0 ]; do
  case "$1" in
    --census) CENSUS="$2"; shift 2 ;;
    --census=*) CENSUS="${1#--census=}"; shift ;;
    *) echo "✗ 未知參數：$1" >&2; exit 2 ;;
  esac
done
[ -r "$CENSUS" ] || { echo "✗ 讀不到 census：$CENSUS" >&2; exit 2; }

AKASHIC=""
for c in "$REPO/.build/debug/akashic" "$REPO/.build/release/akashic"; do
  [ -x "$c" ] && AKASHIC="$c" && break
done
if [ -z "$AKASHIC" ]; then
  echo "✗ 找不到 akashic binary（先跑 swift build）" >&2
  exit 2
fi

# 支援上限從原始碼取，不寫死——寫死的數字會在 format bump 時安靜過期。
SUPPORTED=$(grep -oE 'static let supported = [0-9]+' \
  "$REPO/Sources/AkashicStoreIO/StoreVersion.swift" | grep -oE '[0-9]+$')
if [ -z "$SUPPORTED" ]; then
  echo "✗ 抽不到 StoreVersion.supported——宣告寫法可能改了，先修這支測試再說" >&2
  exit 2
fi

# **驗 mktemp 成功**。本檔用 `set -uo`（刻意沒有 -e，因為 check() 要收 census
# 的非零退出），所以 mktemp 失敗時 $WORK 會是空字串，而下面每個 fixture 路徑都是
# "$WORK/..." —— 那會在**檔案系統根目錄**建目錄寫檔，且 trap 的 rm -rf "" 清不掉。
WORK=$(mktemp -d) || { echo "✗ mktemp -d 失敗" >&2; exit 2; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "✗ mktemp -d 沒有給出可用的目錄" >&2; exit 2; }
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0; fail=0; xfail=0

# 建一個最小 store：一筆 work，帶一條 venue literal 邊。
make_store() {
  local d="$1"
  mkdir -p "$d/entities"
  cat > "$d/entities/x.yaml" <<'YAML'
work:
id: 11111111-1111-1111-1111-111111111111
citekey: t
type: periodical-article
title: t
authors:
- literal: A
venues:
- literal: V
YAML
}

# 兩邊都歸到同一套四值詞彙：accept / malformed / tooNew / unreadable。
#
# **刻意不是二值 open/closed。** 第一版用二值，negative control 立刻證明它是盲的：
# 把 census 的 `n >= 1` 守衛拿掉之後，`format: 0` 仍然「通過」——因為測試自己的
# 分類器也做了一次範圍檢查，把 census 的錯誤吸收掉了。二值看不見「census 以為自己
# 讀到一個合法 marker」與「census 知道 marker 壞了」的差別，而那正是要比的東西。
# 把 repo 位置顯式傳給 census：`--census` 指到的可能是 tempdir 裡的 copy
# （negative control 就是這樣跑的），那份 copy 從自身位置推不到 Sources/。
census_verdict() {
  local out first
  out=$(AKASHIC_REPO="$REPO" "$CENSUS" "$1" 2>&1) || { echo "ERROR"; return; }
  first=$(printf '%s\n' "$out" | head -1)
  case "$first" in
    *"marker 不合 grammar"*)      echo "malformed" ;;
    *"store.yaml 開不了"*)        echo "unreadable" ;;
    # **tooNew 讀 census 自己說的話，不由本測試算。** 前一版寫
    #   elif [ "$n" -gt "$SUPPORTED" ]; then echo "tooNew"
    # ——那是測試自己做的範圍檢查。決定性實驗：只刪掉那一行、census 一個位元組
    # 都沒動，該格立刻變成 census=accept oracle=tooNew。也就是說那個 ✓ 完全由
    # 測試的算術製造，而 census 對一個沒有任何 binary 打得開的 store 印得跟健康
    # store 逐字相同。這與本檔上方「刻意不是二值」的理由是**同一個**，而四值那次
    # 只修好了 n >= 1 那一格。
    *"超過本機原始碼的支援上限"*) echo "tooNew" ;;
    *"不知道你的 binary 支援到第幾版"*) echo "ceiling-unknown" ;;
    *"format 1（無 store.yaml"*)  echo "accept" ;;
    *"（format "*)                echo "accept" ;;
    *)                            echo "ERROR" ;;
  esac
}

# 讀端（真 CLI）對這個 store 的裁決。
#
# **判準是錯誤的種類，不是 exit code。** 第一版寫 `if akashic people …; then open`，
# 六個完全合法的 fixture 全被判 closed——因為 `people` 對「查詢為空且有 quarantined
# 檔」也回 exit 1。那是查詢層的結果，不是版本層的裁決；把兩者折在一起，測試就會把
# 自己的 oracle 缺陷報成 census 的缺陷。
#
# StoreVersionError 有兩個 case，各有具名訊息（Akashic repo 的
# Sources/AkashicStoreIO/StoreVersion.swift，**private，取不到原始碼者只能看訊息本身**）；
# 第三類不經 StoreVersionError：marker **讀不進來**（權限、是目錄），
# Data(contentsOf:) 直接 throw Cocoa 檔案錯誤，訊息點名 store.yaml。
oracle_verdict() {
  local d="$1" err
  err=$("$AKASHIC" people --library "$d" 2>&1 >/dev/null)
  case "$err" in
    *"store format 標記無法解析"*) echo "malformed" ;;
    *"由較新版本寫入"*)            echo "tooNew" ;;
    *store.yaml*)                  echo "unreadable" ;;
    *)                             echo "accept" ;;
  esac
}

# check <名稱> <marker 或 __ABSENT__/__NOUTF8__/__NOPERM__/__DIR__> <預期裁決>
#
# **第三個參數是必填的預期值，不只是比對兩邊相等。**
# 前一版只驗 census == oracle，於是**兩邊一起錯仍然全綠**——例如作者誤讀了讀端的
# grammar、又把 census 寫成跟那個誤讀一致，測試無法區分「兩邊都對」與「兩邊都錯」
# （#407 R6 finding 13）。加上預期值之後，這張矩陣才是一份可否證的規格。
check() {
  local name="$1" marker="$2" expect="$3"
  local d="$WORK/$(echo "$name" | tr -c 'a-zA-Z0-9' '_')"
  make_store "$d"
  case "$marker" in
    __ABSENT__) : ;;
    __NOUTF8__) printf 'format: \xff\xfe12\n' > "$d/store.yaml" ;;
    __NOPERM__) printf 'format: 12\n' > "$d/store.yaml"; chmod 000 "$d/store.yaml" ;;
    __DIR__)    mkdir -p "$d/store.yaml" ;;
    *)          printf '%b' "$marker" > "$d/store.yaml" ;;
  esac

  local c o
  c=$(census_verdict "$d"); o=$(oracle_verdict "$d")
  chmod -R u+rwX "$d" 2>/dev/null

  if [ "$c" = "$expect" ] && [ "$o" = "$expect" ]; then
    printf '✓ %-46s %s\n' "$name" "$expect"
    pass=$((pass + 1))
  elif [ "$c" = "$o" ]; then
    printf '✗ %-46s 兩邊一致於 %s，但預期 %s ← 規格與實作一起錯\n' "$name" "$c" "$expect"
    fail=$((fail + 1))
  else
    printf '✗ %-46s census=%s oracle=%s（預期 %s）\n' "$name" "$c" "$o" "$expect"
    fail=$((fail + 1))
  fi
}

echo "═══ store marker parity：census vs 讀端（supported=${SUPPORTED}）═══"
echo

# ── 合法 ──────────────────────────────────────────────────────────────────
check "format: 12"                      'format: 12\n' accept
check "缺檔（讀端：即 format 1）"        '__ABSENT__' accept
check "值後帶註解（讀端明文允許）"        'format: 12  # v12\n' accept
check "前後有註解與空行"                 '# hdr\n\nformat: 12\n\n# tail\n' accept
check "縮排的註解（允許）"               '  # indented comment\nformat: 12\n' accept
check "CRLF 換行"                        'format: 12\r\n' accept
# ── 讀端拒絕 ──────────────────────────────────────────────────────────────
check "無 format: 行"                    'current: main\n' malformed
check "空檔"                             '' malformed
check "第二個 format: 行（歧義）"         'format: 12\nformat: 3\n' malformed
check "未知頂層行 meta: {（#112 繞法）"   'meta: {\nformat: 12\n' malformed
check "縮排的非註解行"                    'format: 12\n  indented: x\n' malformed
# 這一格是縮排守衛的**唯一**鑑別點：拿掉守衛後上一格仍會落到「未知的頂層行」而照樣
# 被拒，只有縮排的 *format* 行會被錯誤接受。negative control 抓到的盲點。
check "縮排的 format 行"                  '  format: 12\n' malformed
check "format: 0（版號須 >= 1）"          'format: 0\n' malformed
check "format: 2.5（值後不是註解）"       'format: 2.5\n' malformed
check "format: 12 garbage"               'format: 12 garbage\n' malformed
check "非 UTF-8"                         '__NOUTF8__' malformed
check "讀不到（chmod 000）"               '__NOPERM__' unreadable
check "store.yaml 是目錄"                 '__DIR__' unreadable
check "版號太新（tooNew）"                "format: $((SUPPORTED + 1))\n" tooNew
# ── 數值解析（R6 CRITICAL 2：這一族先前只有阿拉伯數字一格，且標成 xfail，
#    於是整套仍報 fail=0 而 census 把讀端拒開的 store 印得跟健康 store 逐字相同）──
# Swift 的 Int(String) 只吃 ASCII 數字且超出 Int64 回 nil；Python 的 isdigit()
# 認全部 Unicode 數字、int() 是任意精度。三種數字系統 + 上下界各一格。
check "全形數字 format: １２"            'format: １２\n' malformed
check "天城體數字 format: १२"            'format: १२\n' malformed
check "阿拉伯數字 format: ١٢"            'format: ١٢\n' malformed
check "Int64 上界 9223372036854775807"   'format: 9223372036854775807\n' tooNew
check "Int64 溢位 9223372036854775808"   'format: 9223372036854775808\n' malformed
check "超大版號（26 位）"                 'format: 99999999999999999999999999\n' malformed
# ── grapheme vs code point（R8 CRITICAL）──────────────────────────────────
# 讀端的 `hasPrefix("#")` 是 grapheme cluster 比較，Python 的 `startswith('#')`
# 是 code point 比較。`#` 後緊跟一個 grapheme extender 時：讀端判「未知的頂層行」
# 整檔拒開，舊版 census 判註解、跳過、照常印計數——輸出與健康 store 逐字相同。
# **兩個方向都要造格子。** 上一版寫「分歧單向…所以只有 fail-open 那一半」，
# 而那句話決定了矩陣**只造一半的格子**——於是 R9 新引入的 31 個 Mc 反向誤擋
# 一格都沒被測到（#407 R9 verify）。這是「總括判準與封閉列舉分岔」的教科書形狀。
check "# + combining acute（註解行）"    '#\xcc\x81 c\nformat: 12\n' malformed
check "# + VS16（註解行）"               '#\xef\xb8\x8f c\nformat: 12\n' malformed
check "# + ZWJ（註解行）"                '#\xe2\x80\x8d c\nformat: 12\n' malformed
check "#️⃣ keycap 序列（註解行）"          '#\xef\xb8\x8f\xe2\x83\xa3 s\nformat: 12\n' malformed
check "值後註解 # + combining acute"     'format: 12 #\xcc\x81c\n' malformed

# ── R9 verify 具名的兩個方向（近似判準漏 103 / 多含 31）────────────────────
# 前一版用 general category ＋ 硬編範圍近似 grapheme extender，並寫「那正是分歧
# 的充要形狀」。實測兩個方向都錯。這五格各取一個代表：前四個是漏掉的（fail-open
# ——讀端拒開卻被報成健康），最後一個是多含的（反向誤擋——好檔被說壞掉）。
check "# + U+200C ZWNJ（Cf，終端機看不見）"  '#\xe2\x80\x8c x\nformat: 12\n' malformed
check "# + U+0E33 泰文 SARA AM（Lo）"        '#\xe0\xb8\xb3 x\nformat: 12\n' malformed
check "# + U+1F3FB emoji modifier（Sk）"     '#\xf0\x9f\x8f\xbb x\nformat: 12\n' malformed
check "# + U+FF9E 半形濁音（Lm）"            '#\xef\xbe\x9e x\nformat: 12\n' malformed
check "# + U+102B 緬甸文 Mc（GCB=Other）"    '#\xe1\x80\xab x\nformat: 12\n' accept
check "值後 # + U+200C"                      'format: 12 #\xe2\x80\x8cx\n' malformed
check "值後 # + U+102B"                      'format: 12 #\xe1\x80\xabx\n' accept

# ── 前導零（R8 HIGH：Python 3.11+ 的 int() 位數上限；Swift 逐位解析不受影響）──
check "5000 個前導零 + 1"                "format: $(printf '0%.0s' $(seq 1 5000))1\n" accept
check "前導零 + Int64 上界"              "format: 000009223372036854775807\n" tooNew
check "前導零 + Int64 上界加一"          "format: 000009223372036854775808\n" malformed

# ── U+200B ZWSP（R8 HIGH：反方向的假話——讀端 trim 掉它、census 不 trim）────
# Foundation 的 CharacterSet.whitespaces 含 ZWSP（Cf，不是 Zs），而舊版 _WS 由
# Zs 推導。五種位置讀端全部接受，census 全部說「讀端會整體拒開此 store」並指名
# 一個動作（去修一個健康的檔）。差集只有這一個元素，而矩陣先前一格都沒落在上面。
check "ZWSP 在 format: 之後"             'format:\xe2\x80\x8b 12\n' accept
check "ZWSP 在值之後"                    'format: 12\xe2\x80\x8b\n' accept
check "ZWSP 在 # 註解行之前"             '\xe2\x80\x8b# c\nformat: 12\n' accept
check "ZWSP 夾在值與註解之間"            'format: 12\xe2\x80\x8b # c\n' accept
check "只有 ZWSP 的一行"                 '\xe2\x80\x8b\nformat: 12\n' accept

# ── BOM（R6 HIGH 22：反方向的假話——讀端吃掉 BOM 正常開啟，census 卻說拒開
#    並叫使用者去改一個合法的檔。指名動作的假話比報成健康更容易被當真）──
check "UTF-8 BOM + format: 12"           '\xef\xbb\xbfformat: 12\n' accept
echo
echo "═══ pass=$pass  fail=$fail  已知分歧=${xfail} ═══"
[ "$fail" -eq 0 ] || exit 1
