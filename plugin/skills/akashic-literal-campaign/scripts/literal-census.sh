#!/bin/bash
# 三域 literal census（#303 design D5）——campaign 每輪進度量測的唯一來源。
#
# 用法：literal-census.sh [store-root]   # 預設 ~/.akashic
#
# 口徑（兩個都報，只報比率會藏住 pending）：
#   邊數     = `.literal` ref 的出現次數（歸零的終局量測）
#   distinct = 不同 literal 字串數（查證工作量的估計）
#
# venue 域的「未部署」≠ 0：store format < 11 時 venue 邊不存在於模型中，
# 報 0 會把「還沒部署」與「查完了」折成同一個觀察——缺席與零必須可區分。
set -euo pipefail
ROOT="${1:-$HOME/.akashic}"
if [ ! -d "$ROOT/entities" ]; then
  echo "✗ 「$ROOT」不是 Akashic store（缺 entities/）" >&2
  exit 2
fi
python3 - "$ROOT" <<'EOF'
import glob, re, sys, collections

root = sys.argv[1]
fmt = 0
try:
    for line in open(f"{root}/store.yaml", encoding="utf-8"):
        m = re.match(r"^format:\s*(\d+)\s*$", line)
        if m:
            fmt = int(m.group(1))
except OSError:
    pass  # markerless legacy store 視同 format 1（read 端同語意）

a_key = a_lit = v_key = v_lit = 0
a_distinct = collections.Counter()
v_distinct = collections.Counter()
aff_key = aff_lit = 0
aff_distinct = collections.Counter()

for f in glob.glob(f"{root}/entities/*.yaml"):
    t = open(f, encoding="utf-8", errors="replace").read()
    if t.startswith("work:"):
        m = re.search(r"\nauthors:\n((?:- (?:key|literal): .*\n(?:  .*\n)*)*)", t)
        blk = m.group(1) if m else ""
        a_key += len(re.findall(r"^- key: ", blk, re.M))
        for x in re.findall(r"^- literal: (.*)$", blk, re.M):
            a_lit += 1
            a_distinct[x.strip()] += 1
        mv = re.search(r"\nvenues:\n((?:- (?:key|literal): .*\n)*)", t)
        bv = mv.group(1) if mv else ""
        v_key += len(re.findall(r"^- key: ", bv, re.M))
        for x in re.findall(r"^- literal: (.*)$", bv, re.M):
            v_lit += 1
            v_distinct[x.strip()] += 1
    elif t.startswith("person:"):
        m = re.search(r"\n  affiliations:\n(.*?)(?=\n  [a-z]|\nprofile|\Z)", t, re.S)
        if m:
            blk = m.group(1)
            aff_key += len(re.findall(r"value:\n\s+key: ", blk))
            for x in re.findall(r"value:\n\s+literal: (.*)$", blk, re.M):
                aff_lit += 1
                aff_distinct[x.strip()] += 1

def row(label, key, lit, distinct):
    total = key + lit
    pct = f"{lit/total:.1%}" if total else "—"
    print(f"{label:<14} 邊 {total:>5}（key {key} / literal {lit}，literal 佔 {pct}）"
          f"  distinct literal {distinct}")

print(f"store: {root}（format {fmt}）")
row("author", a_key, a_lit, len(a_distinct))
if fmt >= 11:
    row("venue", v_key, v_lit, len(v_distinct))
else:
    print(f"{'venue':<14} 未部署（store format {fmt} < 11——venue 邊不存在於模型中，"
          "非「查完」；部署鏈見 docs/store-format.md format 11 列）")
row("affiliation", aff_key, aff_lit, len(aff_distinct))
EOF
