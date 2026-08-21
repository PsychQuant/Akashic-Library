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
# 四種狀態必須分開。標籤**對照讀端**（AkashicStoreIO/StoreVersion.read）而非自創：
#   int   → 讀到 format 標記
#   1     → store.yaml 不存在。讀端明訂「**缺檔 ＝ format 1**，不是錯誤：#24 之前
#           寫的 store 都沒有這個檔」，所以這是合法的 legacy store，不是儀器失敗。
#   None  → 檔案在但沒有 format: 行。讀端對這個情形**throw malformed**（「不猜，
#           明說」），所以這裡也不能自己編一個版號。
#   -1    → 檔案在但讀不到（權限／IO）。與「不存在」是**不同**的事。
#
# 前一版把前兩者的標籤寫反了（缺檔標成「讀不到」、無標記標成「視同 1」），而那是
# 讀一次讀端就能查證的事。也把「不存在」與「讀不到」折成同一個 OSError 分支——
# 而本腳本正是「分得清沒有與讀不到嗎」這條紀律的反面教材來源。
import errno, os as _os

_p = f"{root}/store.yaml"
if not _os.path.exists(_p):
    fmt = 1                      # 讀端語意：缺檔即 format 1
    fmt_state = "absent"
else:
    fmt = None
    fmt_state = "malformed"      # 有檔但沒讀到 format: 行 → 讀端會拒讀
    try:
        with open(_p, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^format:\s*(\d+)\s*$", line)
                if m:
                    fmt = int(m.group(1))
                    fmt_state = "read"
    except OSError as e:
        fmt = -1
        fmt_state = "unreadable"
        _err = errno.errorcode.get(e.errno, e.errno)

def fmt_label():
    # 標籤自帶「format」一詞：呼叫端直接嵌入句子，不再另外前綴（前一版前綴後
    # 讀成「store format store.yaml 有檔但無 format: 行」）。
    if fmt_state == "absent":
        return "format 1（無 store.yaml；讀端語意：缺檔即 format 1）"
    if fmt_state == "unreadable":
        return f"format **未知**——store.yaml 讀不到（{_err}）"
    if fmt_state == "malformed":
        return "format **未知**——store.yaml 無 format: 行（讀端會拒讀此 store）"
    return f"format {fmt}"

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
# 合併掃描（R5 更正 R4-8 的「切換」誤修）：loader 的 load() 本來就**並存讀取**
# entities/＋entries/＋people/（LibraryStore doc「與 legacy 並存讀取」；中斷遷移
# 的 store 在 loader 眼中就是兩筆）——census 與 loader 同語意才不會在混合佈局
# 報假零（R4 實測：legacy＋1 個 entities 檔 → 切換版報 0，doctor 報 2）。
files = (glob.glob(glob.escape(root) + "/entities/*.yaml")
         + glob.glob(glob.escape(root) + "/entries/*.yaml")
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

print(f"store: {root}（{fmt_label()}）")
row("author", a_key, a_lit, len(a_distinct))
# venue 的三分支。**先報量到的，解釋擺後面** —— 前一版反過來（先套 format 的解釋、
# 再決定要不要印計數），於是在 format 未知時印出「下面的計數是實際掃到的」而下面
# 根本沒有計數行；在 format 缺檔時，明明手上握著已解析的 venue 邊，卻宣告
# 「venue 邊不存在於模型中」。兩者都是拿推論蓋掉量測。
_v_total = v_key + v_lit
if _v_total > 0:
    # 量到就印，不論 format 說什麼。format 與量測不一致時，把不一致本身報出來。
    row("venue", v_key, v_lit, len(v_distinct))
    if not (isinstance(fmt, int) and fmt >= 11):
        print(f"{'':<14} ↑ 註：store {fmt_label()}，但上列 venue 邊是**實際解析到的**。"
              "兩者不一致——以量測為準，並請查 store 狀態")
elif isinstance(fmt, int) and fmt >= 11:
    row("venue", v_key, v_lit, len(v_distinct))          # 已部署且真的是 0
elif fmt_state in ("read", "absent"):
    print(f"{'venue':<14} 未部署（store {fmt_label()}，< 11——venue 邊不存在於模型中，"
          "非「查完」；部署鏈見 repo 的 docs/store-format.md format 11 列（private，無存取權者取不到））")
else:
    print(f"{'venue':<14} **未知**（{fmt_label()}；且未解析到任何 venue 邊——"
          "無法區分「未部署」與「已部署但為 0」。先修 store.yaml 再重跑）")
row("affiliation", aff_key, aff_lit, len(aff_distinct))
row("org-parents", org_key, org_lit, len(org_distinct))
EOF
