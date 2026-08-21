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
    # 掃整個 skill 目錄（SKILL.md、references/、scripts/），不只 SKILL.md：
    # 引用可以落在該 skill 的任一份文件上。
    if grep -rq -- "$name" "$d"; then
      printf '  ✓ %s\n' "$skill"
    else
      printf '  ✗ %s ← 沒有引用這條規則\n' "$skill"
      fail=$((fail + 1))
    fi
  done

  # 相對路徑要真的解析得到——引用一條指不到的路徑，比不引用更糟：
  # 它讓讀者以為自己拿得到，而 plugin 安裝到別處時那個路徑不存在。
  while IFS= read -r f; do
    dir=$(dirname "$f")
    while IFS= read -r rel; do
      [ -f "$dir/$rel" ] || { printf '  ✗ %s 的相對路徑解析不到：%s\n' \
        "${f#"$PLUGIN"/}" "$rel"; fail=$((fail + 1)); }
    done < <(grep -o -- '\.\./[^)`" ]*'"$name"'\.md' "$f" | sort -u)
  done < <(grep -rl -- "$name" "$SKILLS" 2>/dev/null)
done

echo
if [ "$fail" -eq 0 ]; then
  echo "═══ 全部掛上，相對路徑全部解析得到 ═══"
else
  echo "═══ ${fail} 個缺口 ═══"
fi
exit $((fail > 0))
