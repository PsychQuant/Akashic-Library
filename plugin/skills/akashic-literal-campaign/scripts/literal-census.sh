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
# venue 域的「未部署」≠ 0：報 0 會把「還沒部署」與「查完了」折成同一個觀察，
# 而缺席與零必須可區分。
#
# 「未部署」只在**兩個條件同時成立**時才印：marker 讀得到且版號 < 11，**而且**
# 這一輪一條 venue 邊都沒解析到。先前這裡寫的是「format < 11 時 venue 邊不存在於
# 模型中」——一句全稱句，而它會不成立：磁碟上的 YAML 可以帶 venues: 而 marker 說
# 版號較低（手改、複製、遷移中途）。那種情形要報的是**不一致**，不是「不存在」。
#
# 輸出去向：本腳本的產出會被貼進 issue。所以路徑一律縮成 ~ 形式，不印使用者名。
set -euo pipefail
ROOT="${1:-$HOME/.akashic}"
if [ ! -d "$ROOT/entities" ] && [ ! -d "$ROOT/entries" ] && [ ! -d "$ROOT/people" ]; then
  echo "✗ 「${ROOT}」不是 Akashic store（entities/／entries/／people/ 皆缺）" >&2
  exit 2
fi
python3 - "$ROOT" <<'EOF'
import collections, errno, glob, os, re, sys

root = sys.argv[1]

# ── store format marker：讀端 grammar 的同構實作 ────────────────────────────
# 對照 Sources/AkashicStoreIO/StoreVersion.swift 的 read(data:path:)。
# 前一版只認 `^format:\s*(\d+)\s*$`，卻在註解裡宣稱「標籤對照讀端」——實測有六種
# 輸入形狀分歧，其中三種讓讀端**整體拒開**的 store 在這裡被報成健康。這支腳本的
# 數字會決定 campaign 的批次範圍，所以「只認一種形狀」不夠：使用者仍會拿到一個
# 看起來正常的數字。
#
# 本區塊的等價性是**被量測的**，不是被宣稱的：tests/store-marker-parity.sh 拿真的
# CLI 當 oracle 跑一張 fixture 矩陣，逐格比對接受／拒絕。已知殘留分歧也在那裡釘住。
#
# 回傳四態（讀端對每一態的裁決寫在各分支）：
#   read       → 讀到合法 marker，值為 fmt
#   absent     → 檔案不存在。讀端明訂「**缺檔 ＝ format 1**，不是錯誤」——#24 之前
#                寫的 store 都沒有這個檔，它們就是 v1.x。合法 legacy，不是儀器失敗
#   malformed  → 檔案在但 grammar 不合。讀端 throw；**任何 binary 都打不開這個 store**
#   unreadable → 開不了檔（權限／IO）。與「不存在」是不同的事，不得折在一起
import unicodedata

# CharacterSet.whitespaces ＝ Unicode Zs ∪ tab。刻意不用 str.strip()：它另外剝
# \v \f，而讀端不把那兩個當空白。
_WS = ''.join(chr(c) for c in range(0x3000 + 1)
              if unicodedata.category(chr(c)) == 'Zs') + '\t'
# Character.isNewline 的字元集。刻意不用 str.splitlines()：它另外認 \x1c–\x1e，
# 會在讀端不分行的地方分行。
_NL = re.compile('\r\n|[\n\r\v\f\x85  ]')


def _read_marker(path):
    """回傳 (state, value_or_None, detail)。detail 是給人看的原因字串。"""
    try:
        with open(path, 'rb') as fh:
            raw_bytes = fh.read()
    except FileNotFoundError:
        return 'absent', 1, ''
    except IsADirectoryError:
        # 讀端對此不走 malformed：fileExists 為真、Data(contentsOf:) 對目錄 throw
        # 一個 IO 錯誤。與 chmod 000 同類——marker 讀不進來，不是 grammar 不合。
        return 'unreadable', None, '(是目錄)'
    except OSError as e:
        code = errno.errorcode.get(e.errno, e.errno) if e.errno is not None else 'OSError'
        return 'unreadable', None, f'({code})'

    try:
        text = raw_bytes.decode('utf-8')
    except UnicodeDecodeError:
        # 讀端對此明文 throw malformed，訊息逐字是「(標記檔不是 UTF-8)」。
        return 'malformed', None, '(標記檔不是 UTF-8)'

    found = None
    for line_raw in _NL.split(text):
        line = line_raw.strip(_WS)
        if not line or line.startswith('#'):
            continue
        # 有內容的行必須頂格——marker 裡沒有巢狀結構。
        if line_raw[:1] and line_raw[0] in _WS:
            return 'malformed', None, '(縮排的非註解行)'
        if not line.startswith('format:'):
            # 含 `meta: {`：#112 之後 flow mapping 的第 0 欄鍵是僅存的毒化繞法，
            # grammar 不再跳過不認識的行。
            return 'malformed', None, '(未知的頂層行)'
        if found is not None:
            return 'malformed', None, '(第二個 format: 行——歧義)'
        v = line[len('format:'):].strip(_WS)
        numeric = ''
        for ch in v:
            if not ch.isdigit():
                break
            numeric += ch
        try:
            n = int(numeric)
        except ValueError:
            return 'malformed', None, '(format: 後不是整數)'
        if n < 1:
            return 'malformed', None, f'(format: {n}——版號須 >= 1)'
        # 值後面只能是註解：`format: 2 garbage` 與 `format: 2.5` 都不是
        # 「帶註解的整數」，不得取前綴當真。
        rest = v[len(numeric):].strip(_WS)
        if rest and not rest.startswith('#'):
            return 'malformed', None, '(format: 值後面不是註解)'
        found = n
    if found is None:
        return 'malformed', None, '(檔案內找不到 format: 行)'
    return 'read', found, ''


fmt_state, fmt, _detail = _read_marker(f'{root}/store.yaml')


def fmt_label():
    # 標籤自帶「format」一詞：呼叫端直接嵌入句子，不另外前綴。
    if fmt_state == 'absent':
        return 'format 1（無 store.yaml；讀端語意：缺檔即 format 1）'
    if fmt_state == 'unreadable':
        return f'format **未知**——store.yaml 開不了 {_detail}'
    if fmt_state == 'malformed':
        return f'format **未知**——marker 不合 grammar {_detail}；**讀端會整體拒開此 store**'
    return f'format {fmt}'

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

def _tilde(p):
    """把 $HOME 前綴縮成 ~。輸出會進 issue，不印使用者名。

    只處理前綴——store root 之外的路徑本腳本不印。這不是通用消毒器，
    別把它當成 displaySafe 的對應物（那是另一個威脅模型：檔案原文進 error）。
    """
    home = os.path.expanduser('~')
    return '~' + p[len(home):] if home and p.startswith(home) else p


print(f"store: {_tilde(root)}（{fmt_label()}）")
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
              "而 marker 說不是——**兩者不一致**。上列是這一輪實際解析到的數字；"
              "marker 不合 grammar 時讀端會整體拒開此 store，"
              "所以在修好 marker 之前，這些數字不能拿去定 campaign 的批次範圍")
elif isinstance(fmt, int) and fmt >= 11:
    row("venue", v_key, v_lit, len(v_distinct))          # 已部署且真的是 0
elif fmt_state in ("read", "absent"):
    print(f"{'venue':<14} 未部署（store {fmt_label()}，< 11，且本輪零 venue 邊——"
          "非「查完」；部署鏈見 repo 的 docs/store-format.md format 11 列（private，無存取權者取不到））")
else:
    print(f"{'venue':<14} **未知**（{fmt_label()}；且未解析到任何 venue 邊——"
          "無法區分「未部署」與「已部署但為 0」。先修 store.yaml 再重跑）")
row("affiliation", aff_key, aff_lit, len(aff_distinct))
row("org-parents", org_key, org_lit, len(org_distinct))
EOF
