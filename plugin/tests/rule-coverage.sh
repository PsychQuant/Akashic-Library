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
#   plugin/tests/rule-coverage.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
RULES="$PLUGIN/rules"
SKILLS="$PLUGIN/skills"

[ -d "$RULES" ]  || { echo "✗ 找不到 $RULES" >&2; exit 2; }
[ -d "$SKILLS" ] || { echo "✗ 找不到 $SKILLS" >&2; exit 2; }

fail=0
n_skills=$(find "$SKILLS" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
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
    done < <(grep -rHo -- "\.\./[^)\`\" ]*${name}[^)\`\" ]*" "$d" 2>/dev/null)

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
