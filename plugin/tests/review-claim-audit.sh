#!/bin/bash
# 逐條重建**審查者宣稱的失敗情境**，量它在修法前是否真的會發生。
#
# 為什麼存在
# ==========
# #407 的第 10 輪，跨模型審查給了九條 finding，我照著改了八條。而其中**一條是
# 假的**：它說 `_WS` 誤把 U+200B 當空白，論證是「U+200B 的 general category 是
# Cf 不是 Zs，所以 Foundation 的 CharacterSet.whitespaces 不含它」——**它從
# 屬性表推論，沒有量 Foundation 的實際集合**。實測：`contains(U+200B) == true`，
# count=19；端到端 fixture 也顯示真讀端接受。
#
# 那正是這條 issue 的主題（斷言要先量測）發生在審查者身上。而它逼出一個問題：
# **其餘八條呢？我是「照著它的論證改」還是「先驗過再改」？**
#
# 誠實答案是多數為前者。所以這支腳本把每一條的失敗情境重建出來實跑——
# 一條 finding 若重建不出它宣稱的失敗，那條就是未經量測的。
#
# 這不是為了記分。**下一個讀那些 finding 的人會被假的那條誤導**，而修法一旦
# 落地就長得跟真的一樣。
#
# 用法
# ====
#   plugin/tests/review-claim-audit.sh
#
# 每一格印出重建的證據（不是只印通過與否）——判準是「看得到那個失敗」，
# 不是「檢查回了綠燈」。
set -uo pipefail
R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0

verdict() {  # verdict <名稱> <成立?> <證據>
  if [ "$2" = yes ]; then printf '✓ %-52s %s\n' "$1" "$3"; pass=$((pass+1))
  else printf '✗ %-52s %s\n' "$1" "$3"; fail=$((fail+1)); fi
}

echo "══ codex finding #3：sed 的 /./q 是「第一個非空行就停」，不是「找到目標才停」══"
# codex 說：binary 若在正式錯誤訊息前先印一行別的，sed 看到那行就 q，CEILING 空手。
printf 'warning: config deprecated\nError: 此 library 由較新版本寫入（store format 99），本 binary 支援至 12。\n' > "$W/two-line"
OLD=$(sed -n 's/.*本 binary 支援至 \([0-9][0-9]*\).*/\1/p;/./q' < "$W/two-line")
NEW=""
_err=$(cat "$W/two-line")
if [[ "$_err" =~ 本\ binary\ 支援至\ ([0-9]+) ]]; then NEW="${BASH_REMATCH[1]}"; fi
verdict "舊寫法（sed …;/./q）在前置雜訊下拿不到值" \
  "$([ -z "$OLD" ] && echo yes || echo no)" "舊=「${OLD:-空}」"
verdict "新寫法（bash regex，無管線）拿得到" \
  "$([ "$NEW" = 12 ] && echo yes || echo no)" "新=「${NEW:-空}」"

echo
echo "══ codex finding #7：5000 前導零 fixture 依賴 seq，缺席時靜默退化 ══"
# codex 說：seq 不存在時舊寫法會靜默退化成一個極短的字串，仍屬 accept、測試照樣綠。
#
# **重建方式被修正過兩次，兩次都是因為機制沒被量。**
#   第一版：`PATH=/nonexistent bash -c '...'` —— 這讓**外層 bash 自己**找不到
#           （exit 127，`command not found: bash`），內層的 printf／seq **從未執行**。
#           量到的「長度 0」是 bash 沒跑，不是 seq 缺席。DA 抓到（#407 R12）。
#   第二版註解：宣稱「printf 仍成功、%s 代入空字串 → `01`」——那也是猜的。
#   **實測**：只抽掉 seq 而保留 bash／printf 時，輸出是 `0`（printf 的 `0%.0s`
#           在沒有參數時仍會印一次字面的 `0`），長度 1。
#
# 所以這裡建一個**只缺 seq** 的 PATH：真正隔離那一個變因。
_SQ=$(mktemp -d)
for _c in bash printf; do ln -s "$(command -v $_c)" "$_SQ/$_c" 2>/dev/null; done
DEGRADED=$(PATH="$_SQ" bash -c 'printf "0%.0s" $(seq 1 5000 2>/dev/null)1' 2>/dev/null)
rm -rf "$_SQ"
# 斷言用「遠短於 5000」而不是某個猜出來的確切值——重建的目的是證明**退化會發生**，
# 不是釘住退化的確切形狀（那個形狀正是上面兩次都猜錯的東西）。
verdict "舊寫法在無 seq 時退化（遠短於 5000）" \
  "$([ "${#DEGRADED}" -lt 10 ] && echo yes || echo no)" "退化後長度=${#DEGRADED}（不是 5000）"
# **標籤的兩半都要量**（#407 R47，跨模型審查指名）：標籤說「不依賴外部指令**且**
# 長度正確」，而上一版只測長度——依賴性那一半從未被執行過。改成在**只有 bash 的
# 受限 PATH** 下算它（同一支腳本前面已經用這個手法示範過 seq 的依賴性）。
_NOSEQ=$(mktemp -d)
ln -sf "$(command -v bash)" "$_NOSEQ/bash" 2>/dev/null
NEWZ=$(PATH="$_NOSEQ" bash -c "printf '%05000d' 0")
rm -rf "$_NOSEQ"
verdict "新寫法（純 bash）不依賴外部指令且長度正確" \
  "$([ "${#NEWZ}" -eq 5000 ] && echo yes || echo no)" "長度=${#NEWZ}"
verdict "出貨的 parity 測試已改用新寫法且有長度斷言" \
  "$(grep -q 'printf .%05000d' "$R/plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh" \
     && grep -q 'ZEROS.*-eq 5000' "$R/plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh" \
     && echo yes || echo no)" ""

echo
echo "══ codex finding #4：census-parity.yml 的 path filter 漏掉生成表 ══"
# **不能只問「這個字串在檔案裡嗎」**——它出現在 `paths:`（要的）與 `paths-ignore:`
# （反面）長得一模一樣，而後者正是這條 finding 當初要修的東西。所以先切出 `paths:`
# 到下一個同層 key 之間的那一段，只在那一段裡找。謂詞比它要管的東西寬，是本 issue
# 反覆記過的形狀——這裡是它在稽核腳本自己身上的一次（#407 R18）。
PATHS_BLOCK=$(awk '/^ *paths:/{f=1;next} f && /^ *[a-z_-]+:/{f=0} f' \
  "$R/.github/workflows/census-parity.yml")
verdict "生成表現在在 parity workflow 的 paths: 區段裡（非 paths-ignore:）" \
  "$(printf '%s' "$PATHS_BLOCK" | grep -q 'hash-merging-ranges.txt' && echo yes || echo no)" \
  "區段 $(printf '%s' "$PATHS_BLOCK" | grep -c . ) 行"
# 同理：drift 測試要真的被**執行**，不是出現在註解或 paths 裡。只在 `run:` 行找。
verdict "drift 測試在該 workflow 的某個 run: 步驟裡" \
  "$(grep -E '^ *run: ' "$R/.github/workflows/census-parity.yml" \
     | grep -q 'hash-table-drift.sh' && echo yes || echo no)" ""

echo
echo "══ codex finding #9：derive-hash-extenders.swift 的 --check 是假接口 ══"
# **排除註解行**：唯一命中在說明那句「從頭到尾沒讀過 CommandLine.arguments」裡，
# 而那正是在陳述它沒讀。不排除的話，這個檢查會因為「文件記載了這件事」而判定
# 「它做了這件事」——謂詞比它要管的東西寬，本 issue 反覆記過的形狀。
verdict "程式碼（非註解）確實從未讀 CommandLine.arguments" \
  "$(grep -vE '^\s*//' "$R/plugin/skills/akashic-literal-campaign/scripts/tests/derive-hash-extenders.swift" \
     | grep -q 'CommandLine' && echo no || echo yes)" ""
verdict "宣稱 --check 的那句註解已移除" \
  "$(grep -q -- '--check <生成的表>' "$R/plugin/skills/akashic-literal-campaign/scripts/tests/derive-hash-extenders.swift" \
     && echo no || echo yes)" ""

echo
echo "══ 總計 ══"
echo "成立 ${pass}｜不成立 ${fail}"
[ "$fail" -eq 0 ] || exit 1
