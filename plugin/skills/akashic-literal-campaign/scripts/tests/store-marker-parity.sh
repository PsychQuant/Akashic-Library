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
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../../../.." && pwd)
CENSUS="$HERE/../literal-census.sh"

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

WORK=$(mktemp -d)
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
census_verdict() {
  local d="$1" out first n
  out=$("$CENSUS" "$d" 2>&1) || { echo "ERROR"; return; }
  first=$(printf '%s\n' "$out" | head -1)
  case "$first" in
    *"marker 不合 grammar"*)      echo "malformed"; return ;;
    *"store.yaml 開不了"*)        echo "unreadable"; return ;;
    *"format 1（無 store.yaml"*)  echo "accept";    return ;;
  esac
  n=$(printf '%s\n' "$first" | grep -oE 'format [0-9]+' | grep -oE '[0-9]+$')
  if [ -z "$n" ]; then echo "ERROR"
  elif [ "$n" -gt "$SUPPORTED" ]; then echo "tooNew"
  else echo "accept"; fi
}

# 讀端（真 CLI）對這個 store 的裁決。
#
# **判準是錯誤的種類，不是 exit code。** 第一版寫 `if akashic people …; then open`，
# 六個完全合法的 fixture 全被判 closed——因為 `people` 對「查詢為空且有 quarantined
# 檔」也回 exit 1。那是查詢層的結果，不是版本層的裁決；把兩者折在一起，測試就會把
# 自己的 oracle 缺陷報成 census 的缺陷。
#
# StoreVersionError 有兩個 case，各有具名訊息（Sources/AkashicStoreIO/StoreVersion.swift）；
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

# check <名稱> <marker 內容或 __ABSENT__/__NOUTF8__/__NOPERM__/__DIR__> [xfail]
check() {
  local name="$1" marker="$2" expect_divergence="${3:-}"
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

  if [ "$c" = "$o" ]; then
    if [ -n "$expect_divergence" ]; then
      printf '✗ %-46s 現在一致了（census=%s oracle=%s）——已知分歧被修好，請更新本測試\n' "$name" "$c" "$o"
      fail=$((fail + 1))
    else
      printf '✓ %-46s %s\n' "$name" "$c"
      pass=$((pass + 1))
    fi
  else
    if [ -n "$expect_divergence" ]; then
      printf '~ %-46s 已知分歧：census=%s oracle=%s（%s）\n' "$name" "$c" "$o" "$expect_divergence"
      xfail=$((xfail + 1))
    else
      printf '✗ %-46s census=%s oracle=%s\n' "$name" "$c" "$o"
      fail=$((fail + 1))
    fi
  fi
}

echo "═══ store marker parity：census vs 讀端（supported=${SUPPORTED}）═══"
echo

# ── 合法 ──────────────────────────────────────────────────────────────────
check "format: 12"                      'format: 12\n'
check "缺檔（讀端：即 format 1）"        '__ABSENT__'
check "值後帶註解（讀端明文允許）"        'format: 12  # v12\n'
check "前後有註解與空行"                 '# hdr\n\nformat: 12\n\n# tail\n'
check "縮排的註解（允許）"               '  # indented comment\nformat: 12\n'
check "CRLF 換行"                        'format: 12\r\n'

# ── 讀端拒絕 ──────────────────────────────────────────────────────────────
check "無 format: 行"                    'current: main\n'
check "空檔"                             ''
check "第二個 format: 行（歧義）"         'format: 12\nformat: 3\n'
check "未知頂層行 meta: {（#112 繞法）"   'meta: {\nformat: 12\n'
check "縮排的非註解行"                    'format: 12\n  indented: x\n'
# 這一格是縮排守衛的**唯一**鑑別點：拿掉守衛後上一格仍會落到「未知的頂層行」而照樣
# 被拒，只有縮排的 *format* 行會被錯誤接受。negative control 抓到的盲點。
check "縮排的 format 行"                  '  format: 12\n'
check "format: 0（版號須 >= 1）"          'format: 0\n'
check "format: 2.5（值後不是註解）"       'format: 2.5\n'
check "format: 12 garbage"               'format: 12 garbage\n'
check "非 UTF-8"                         '__NOUTF8__'
check "讀不到（chmod 000）"               '__NOPERM__'
check "store.yaml 是目錄"                 '__DIR__'
check "版號太新（tooNew）"                "format: $((SUPPORTED + 1))\n"

# ── 已知殘留分歧（斷言現況；上游若改會變紅）────────────────────────────────
# Swift 的 Int(String) 只吃 ASCII 數字，Python 的 int() 吃 Unicode 十進位數字。
check "Unicode 數字 format: ١٢"          'format: ١٢\n' "Swift Int() 只吃 ASCII，Python int() 吃 Unicode 數字"

echo
echo "═══ pass=$pass  fail=$fail  已知分歧=${xfail} ═══"
[ "$fail" -eq 0 ] || exit 1
