#!/bin/bash
# plugin/rules/ 底下的每一條規則，是否被每一個 skill 掛到？
#
# 為什麼存在
# ==========
# CHANGELOG 與規則檔都寫過「**全部 6 個 skill** 引用它」。那是一個**硬編的計數**：
# 第 7 個 skill 長出來時沒有任何東西會提醒它漏掛，而那句「全部」會安靜地變成假的。
# 跨模型審查點名了這一格（#407 R5 finding 34）。
#
# 這支腳本把那句話從「作者數過」變成「跑一下就知道」。它不解決掛載面比適用面窄的
# 問題（規則檔的誠實邊界有記：see-also 只碰得到 skill 檔），只保證**在它碰得到的
# 範圍內沒有漏格**。
#
# 用法
# ====
#   plugin/tests/rule-coverage.sh [plugin-root]
#
#   plugin-root：repo 相對路徑（例：plugins/akashic-discovery），省略時為 `plugin`。
#   守衛入口以 `akashic-guards plugin-roots` 逐根呼叫——清單只有那一份（#625）。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ $# -ge 1 ]; then
  # 找不到就停，**不退回檢查 `plugin/`**：退回的話打錯的根會拿到一個與它無關的綠燈
  REPO=$(cd "$HERE/../.." && pwd)
  [ -d "$REPO/$1" ] || { echo "✗ 找不到 plugin 根：$1" >&2; exit 2; }
  PLUGIN=$(cd "$REPO/$1" && pwd)
else
  PLUGIN=$(cd "$HERE/.." && pwd)
fi
# 這支用 glob 定位規則檔，從不寫出任何 basename——trigger-coverage.py 的
# 啟發式因此看不見這條依賴（#407 R20 實測）。顯式宣告補上：
# trigger-coverage: reads plugin/rules/*.md
RULES="$PLUGIN/rules"
SKILLS="$PLUGIN/skills"

[ -d "$RULES" ]  || { echo "✗ 找不到 $RULES" >&2; exit 2; }

fail=0
n_skills=0
[ -d "$SKILLS" ] && n_skills=$(find "$SKILLS" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
# #625：0 個 skill 是 vacuous 通過，**印出來**——讀的人要分得出「沒有 skill」與「沒檢查」。
# 新 plugin 在第一個 skill 住進來之前就是這個狀態（akashic-discovery 先於 #617 上線）。
if [ "$n_skills" -eq 0 ]; then
  echo "═══ rule coverage：${PLUGIN#"$(cd "$HERE/../.." && pwd)"/} 有 0 個 skill（vacuous）═══"
  exit 0
fi
echo "═══ rule coverage：${n_skills} 個 skill ═══"
echo

for rule in "$RULES"/*.md; do
  name=$(basename "$rule" .md)
  echo "── ${name} ──"
  for d in "$SKILLS"/*/; do
    skill=$(basename "$d")
    # **驗的是「有一條解析得到的相對路徑指向這條規則」**，不是「這個字串在某處
    # 出現過」。前一版用整目錄子字串比對，於是任何一處純文字提及都算「已掛載」
    # ——包括一句「本規則不適用於此」。規則檔與 CHANGELOG 卻把它描述成「引用
    # 存在且路徑解析得到」，那個描述經實測為假（#407 R6 findings 14／15／17）。
    #
    # regex 的結尾用 `[^)\`" ]*` 一路吃到分隔符，**不是**吃到 .md 就停。前一版
    # 會從 `…assertions-must-be-measured.md.bak` 擷取出一個合法前綴、驗證通過，
    # 而那個連結是壞的。
    found=0
    while IFS= read -r hit; do
      f="${hit%%:*}"; rel="${hit#*:}"
      base=$(basename "$rel")
      # 擷取到的整個 token 必須就是規則檔本身（不是它的前綴）
      [ "$base" = "${name}.md" ] || {
        printf '  ✗ %s 的引用不是這條規則本身：%s\n' "${f#"$PLUGIN"/}" "$rel"
        fail=$((fail + 1)); continue
      }
      if [ -f "$(dirname "$f")/$rel" ]; then
        found=1
      else
        printf '  ✗ %s 的相對路徑解析不到：%s\n' "${f#"$PLUGIN"/}" "$rel"
        fail=$((fail + 1))
      fi
      # **只認 SKILL.md**。掛載點是 skill 的進入點，不是它目錄裡的任一份筆記。
      # 前一版掃整個子樹，於是把連結從 SKILL.md 拿掉、在旁邊的 note.md 寫一句
      # 「不要載入這條規則」，守衛照樣 ✓——而這支腳本的註解逐字宣稱它已經修掉
      # 那個形狀（#407 R7 verify）。加位置條件才是真的修掉。
    done < <(grep -Ho -- "\.\./[^)\`\" ]*${name}[^)\`\" ]*" "$d/SKILL.md" 2>/dev/null)

    if [ "$found" = 1 ]; then
      printf '  ✓ %s\n' "$skill"
    else
      printf '  ✗ %s ← 沒有指向這條規則的可解析相對路徑\n' "$skill"
      fail=$((fail + 1))
    fi
  done
done

echo
if [ "$fail" -eq 0 ]; then
  echo "═══ 全部掛上，相對路徑全部解析得到 ═══"
else
  echo "═══ ${fail} 個缺口 ═══"
fi
exit $((fail > 0))
