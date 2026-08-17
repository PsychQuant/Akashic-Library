#!/bin/bash
# 三域 literal census（#303 design D5）——campaign 每輪進度量測的唯一來源。
#
# 用法：literal-census.sh [store-root]   # 預設 ~/.akashic
#
# 口徑（R1-fix I4 統一；兩個都報，只報比率會藏住 pending）：
#   總邊     = 該域 ref 邊總數（key＋literal）
#   literal 邊 = `.literal` ref 的出現次數（**歸零的終局量測就是這個數**）
#   distinct = 不同 literal 字串數（查證工作量的估計）
#
# venue 域的「未部署」≠ 0：store format < 11 時 venue 邊不存在於模型中，
# 報 0 會把「還沒部署」與「查完了」折成同一個觀察——缺席與零必須可區分。
set -euo pipefail
ROOT="${1:-$HOME/.akashic}"
if [ ! -d "$ROOT/entities" ] && [ ! -d "$ROOT/entries" ] && [ ! -d "$ROOT/people" ]; then
  echo "✗ 「${ROOT}」不是 Akashic store（entities/／entries/／people/ 皆缺）" >&2
  exit 2
fi
python3 - "$ROOT" <<'EOF'
import glob, re, sys, os, collections

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
org_key = org_lit = 0
org_distinct = collections.Counter()

# glob.escape（R1-fix I4）：root 含 glob metacharacter（`[a]` 等）時，未跳脫的
# pattern 會靜默匹配零檔——輸出與「查完歸零」無法區分，正是本檔 header 對 venue
# 域禁止的那種折疊。
# 佈局模式**切換**不合併（R4-8——loader 的 usesEntitiesLayout 同語意）：
# entities/ 有檔 → 只掃 entities/（合併掃描會把半遷移 store 的同一記錄雙計）；
# 否則掃 legacy（entries/＋people/）。
entity_files = glob.glob(glob.escape(root) + "/entities/*.yaml")
files = entity_files if entity_files else (
    glob.glob(glob.escape(root) + "/entries/*.yaml")
    + glob.glob(glob.escape(root) + "/people/*.yaml"))
if not files and os.path.isdir(f"{root}/entities") and os.listdir(f"{root}/entities"):
    print(f"✗ entities/ 非空但匹配不到任何 .yaml——路徑或權限異常，拒絕輸出計數", file=sys.stderr)
    sys.exit(3)
for f in files:
    t = open(f, encoding="utf-8", errors="replace").read()
    # legacy 佈局檔無形狀前綴——依目錄判 kind（entries/=work、people/=person）
    parent = os.path.basename(os.path.dirname(f))
    is_work = t.startswith("work:") or (parent == "entries" and not t.startswith(("person:", "organization:")))
    is_person = t.startswith("person:") or (parent == "people" and not t.startswith(("work:", "organization:")))
    if is_work:
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
    elif t.startswith("organization:"):
        # parents 是頂層鍵（非縮排）——與 person affiliations（profile 下縮排）不同形
        m = re.search(r"\nparents:\n(.*?)(?=\n[a-z]|\Z)", t, re.S)
        if m:
            blk = m.group(1)
            org_key += len(re.findall(r"value:\n\s+key: ", blk))
            for x in re.findall(r"value:\n\s+literal: (.*)$", blk, re.M):
                org_lit += 1
                org_distinct[x.strip()] += 1
    elif is_person:
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
    print(f"{label:<14} 總邊 {total:>5}｜literal 邊 {lit}（佔 {pct}）｜key {key}"
          f"｜distinct literal {distinct}")

print(f"store: {root}（format {fmt}）")
row("author", a_key, a_lit, len(a_distinct))
if fmt >= 11:
    row("venue", v_key, v_lit, len(v_distinct))
else:
    print(f"{'venue':<14} 未部署（store format {fmt} < 11——venue 邊不存在於模型中，"
          "非「查完」；部署鏈見 docs/store-format.md format 11 列）")
row("affiliation", aff_key, aff_lit, len(aff_distinct))
row("org-parents", org_key, org_lit, len(org_distinct))
EOF
