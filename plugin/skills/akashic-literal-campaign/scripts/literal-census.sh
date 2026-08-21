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
# script 自身的目錄要顯式傳進去：`python3 -` 讀 stdin，__file__ **不存在**
# （用它會 NameError）。census 需要它來找原始碼判定支援上限。
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3 - "$ROOT" "$SCRIPT_DIR" <<'EOF'
import collections, errno, glob, io, os, re, sys

root = sys.argv[1]
# script 自身的目錄（bash 端顯式傳入）——查表與找原始碼都要它。
_script_dir = sys.argv[2] if len(sys.argv) > 2 else '.'

# ── store format marker：讀端 grammar 的同構實作 ────────────────────────────
# 對照 Akashic repo（**private**）的 Sources/AkashicStoreIO/StoreVersion.swift 的 read
# （**該 repo 為 private，plugin 單獨安裝者取不到原始碼**——所以下方那句「對照讀端」
# 不能靠讀者自己去核對，它由 tests/store-marker-parity.sh 拿真的 CLI 當 oracle 量測）。
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

# 讀端 trim 用 Foundation 的 `CharacterSet.whitespaces`。這裡**列舉它實際含有的
# 19 個 scalar**，不從 Unicode category 推導。
#
# 前一版寫「CharacterSet.whitespaces ＝ Unicode Zs ∪ tab」並照那句話推導——**那句
# 等式是假的**：Foundation 沿用舊表，含 **U+200B**（ZERO WIDTH SPACE），而 ZWSP
# 自 Unicode 4.0 起是 Cf 不是 Zs。差集恰好一個元素，而它是最容易從網頁／聊天視窗
# 貼進來、又在終端機裡看不見的那一個。
#
# 後果是**反方向**的假話（實測 5 種位置，讀端全部 ACCEPT）：census 說 marker 壞了、
# 整份計數被宣告不可用，而使用者被指去修一個完全健康的檔。這比報成健康更容易被
# 當真，因為它指名了一個動作——那句判準就寫在本檔下面幾行（#407 R8）。
#
# 量測（可重跑；需要 swift）：
#   for cp in 0...0x10FFFF { if CharacterSet.whitespaces.contains(scalar) { … } }
#   → count=19：U+0009 U+0020 U+00A0 U+1680 U+2000–U+200A U+200B U+202F U+205F U+3000
_WS = ('\u0009\u0020\u00a0\u1680'
       '\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a'
       '\u200b'          # ← Foundation 有、Zs 沒有。整條註解存在的理由就是它
       '\u202f\u205f\u3000')
# Character.isNewline 的字元集。刻意不用 str.splitlines()：它另外認 \x1c–\x1e，
# 會在讀端不分行的地方分行。
_NL = re.compile('\r\n|[\n\r\v\f\x85  ]')


# 「緊跟在 `#` 後面會讓讀端不把該行當註解」的 code point 表。
#
# 讀端判註解用 Swift 的 `line.hasPrefix("#")`，而 Swift 的 String 比較以
# **Character（grapheme cluster）** 為單位；Python 標準庫沒有 grapheme 分段。
#
# 前一版用「general category（Mn/Mc/Me）＋ 四段硬編範圍」近似，並寫下「那正是
# 分歧的**充要**形狀」。跨模型審查把兩個方向都否證了：漏 103 個（fail-open：
# 讀端拒開的 store 被印得跟健康的逐字相同），多含 31 個 Mc（反向誤擋：叫使用者
# 去修一個完全健康的檔）。根因是拿 general category 近似 Grapheme_Cluster_Break
# ——兩者既不互相包含也不是同一張表，**再加幾段是加不完的**（#407 R9）。
#
# 現在改成查表，而表由 Swift 自己列舉：
#   swift tests/derive-hash-extenders.swift > hash-merging-ranges.txt
# `tests/hash-table-drift.sh` 每次重新生成並比對——Unicode 版本漂移會變紅。
_HASH_TABLE_PATH = f'{_script_dir}/hash-merging-ranges.txt'
_hash_ranges = []
_hash_table_error = None
try:
    for _ln in io.open(_HASH_TABLE_PATH, encoding='utf-8'):
        _ln = _ln.strip()
        if not _ln or _ln.startswith('#'):
            continue
        _a, _b = _ln.split()
        _hash_ranges.append((int(_a, 16), int(_b, 16)))
except (OSError, ValueError) as _e:
    _hash_table_error = str(_e)


def _starts_with_hash(s):
    """第一個 grapheme cluster 是不是恰好 `#`。回 True／False／None（判不出來）。

    None 只在表讀不到、且 `#` 後面是非 ASCII 時出現——那時**不猜**。替讀端猜
    的兩種猜法都出過事：猜寬 → 把拒開的 store 報成健康；猜窄 → 叫人去修一個
    好檔。第三態是這支腳本已經用過的出路（見 ceiling-unknown）。
    """
    if not s.startswith('#'):
        return False
    if len(s) == 1:
        return True
    cp = ord(s[1])
    if cp < 0x80:
        # ASCII 一律不是 grapheme extender——這一半不需要表，也不會漂移。
        return True
    if _hash_table_error is not None:
        return None
    for lo, hi in _hash_ranges:
        if lo <= cp <= hi:
            return False
    return True


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
        # utf-8-**sig**：Foundation 解 UTF-8 時會吃掉 BOM，所以一個帶 BOM 的
        # marker 在讀端是**合法的**。前一版用 'utf-8'，於是 BOM 變成第一行的
        # 第一個字元、既非空白也非 '#'、也不以 'format:' 開頭 → 判「未知的頂層行」，
        # 印出「讀端會整體拒開此 store」並叫使用者去改一個沒壞的檔。
        # 這是**反方向**的假話，比報成健康更容易被當真（它指名了一個動作）。
        text = raw_bytes.decode('utf-8-sig')
    except UnicodeDecodeError:
        # 讀端對此明文 throw malformed，訊息逐字是「(標記檔不是 UTF-8)」。
        return 'malformed', None, '(標記檔不是 UTF-8)'

    found = None
    for line_raw in _NL.split(text):
        line = line_raw.strip(_WS)
        _h = _starts_with_hash(line)
        if _h is None:
            return ('undecidable', None,
                    f'(`#` 後面是非 ASCII 且判註解用的表讀不到：{_hash_table_error}'
                    f'——本腳本不替讀端猜。跑 `akashic doctor --library <store>` 問讀端)')
        if not line or _h:
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
        # **只認 ASCII 數字**。Swift 的 `Int(String)` 只吃 ASCII，而 Python 的
        # `str.isdigit()` 認全部 Unicode 數字——前一版用 isdigit()，於是
        # `format: １２`（全形）、`format: १२`（天城體）、`format: ١٢`（阿拉伯）
        # 全部被讀成 12，輸出與一個真正健康的 format 12 store **逐字相同**，
        # 使用者沒有任何字元可以分辨。讀端對這三者都是 malformed、整體拒開。
        numeric = ''
        for ch in v:
            if ch not in '0123456789':
                break
            numeric += ch
        # **先剝前導零再判上界**，不要把完整字串交給 int()。Python 3.11+ 對超長
        # 十進位字串的 int() 有位數上限（預設約 4300 位）會拋 ValueError，而
        # Swift 的 Int(String) 逐位解析、數值未溢位就接受。所以
        # `format: 000…0001`（前面幾千個 0）在讀端是合法的 1，在舊版 census 卻
        # 落進「不是整數」→ 又一次**反方向**的假話（#407 R8 HIGH）。
        significant = numeric.lstrip('0') or '0'
        if len(significant) > 19:
            return 'malformed', None, '(format: 值超出 Int64——讀端的 Int() 回 nil)'
        try:
            n = int(significant)
        except ValueError:
            return 'malformed', None, '(format: 後不是整數)'
        if n < 1:
            return 'malformed', None, f'(format: {n}——版號須 >= 1)'
        # **Int64 上界**。Swift 的 Int 是 64-bit，`Int("9223372036854775808")`
        # 回 nil → malformed；Python 的 int 是任意精度，於是超大版號被當成合法，
        # 而且 `fmt >= 11` 為真 → venue 走「已部署且真的是 0」分支，連不一致
        # 註記都被抑制。實測界線：…807 兩端一致，…808 起分歧。
        if n > 2 ** 63 - 1:
            return 'malformed', None, '(format: 值超出 Int64——讀端的 Int() 回 nil)'
        # 值後面只能是註解：`format: 2 garbage` 與 `format: 2.5` 都不是
        # 「帶註解的整數」，不得取前綴當真。
        rest = v[len(numeric):].strip(_WS)
        _hr = _starts_with_hash(rest) if rest else True
        if _hr is None:
            return ('undecidable', None,
                    f'(值後的 `#` 註解判不出來：{_hash_table_error}——不替讀端猜)')
        if rest and not _hr:
            return 'malformed', None, '(format: 值後面不是註解)'
        found = n
    if found is None:
        return 'malformed', None, '(檔案內找不到 format: 行)'
    return 'read', found, ''


fmt_state, fmt, _detail = _read_marker(f'{root}/store.yaml')

# ── 支援上限：store 的 format 再合法，也可能沒有任何 binary 打得開 ──────────
# 「支援到第幾版」是**binary 的性質**，不是 store 的性質，所以 census 只有在
# 找得到原始碼時才知道它。找不到時**明說不知道**——前一版兩種情形都印得跟一個
# 健康 store 逐字相同且 exit 0，而 SKILL.md 的四列表把它歸進「照常進 venue 輪」：
# skill 主動叫使用者拿一個沒有任何 binary 打得開的 store 去定 campaign 批次範圍。
_supported = None
# 來源根：`AKASHIC_REPO` 環境變數優先，其次由腳本自身位置往上推。
# 環境變數這條是給「腳本不在 repo 內」的情形——例如 negative control 把 census
# 複製到 tempdir 再 mutate（不碰出貨檔），那份 copy 從自身位置推不到 Sources/。
# 沒有它的話，copy 會對每個健康 fixture 都回「支援上限未知」，而那是 copy 造成的
# 差異、不是 mutation 造成的——negative control 會把它誤報成一整片變紅。
_repo_env = os.environ.get('AKASHIC_REPO')
_cands = []
if _repo_env:
    _cands.append(f'{_repo_env}/Sources/AkashicStoreIO/StoreVersion.swift')
_cands.append(f'{_script_dir}/../../../../Sources/AkashicStoreIO/StoreVersion.swift')
for _cand in _cands:
    try:
        _m = re.search(r'static let supported = (\d+)',
                       io.open(_cand, encoding='utf-8', errors='replace').read())
        if _m:
            _supported = int(_m.group(1))
            break
    except OSError:
        pass

_too_new = fmt_state == 'read' and _supported is not None and fmt > _supported
_ceiling_unknown = fmt_state == 'read' and _supported is None


def fmt_label():
    if _too_new:
        return (f'format {fmt}——**超過本機原始碼的支援上限 {_supported}**；'
                '任何只支援到那一版的 binary 都會整體拒開此 store')
    if _ceiling_unknown:
        return (f'format {fmt}（**本腳本找不到原始碼，不知道你的 binary 支援到第幾版**'
                '——若它低於這個數字，開不起來）')
    # 標籤自帶「format」一詞：呼叫端直接嵌入句子，不另外前綴。
    if fmt_state == 'absent':
        return 'format 1（無 store.yaml；讀端語意：缺檔即 format 1）'
    if fmt_state == 'undecidable':
        return f'format **判不出來** {_detail}'
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
    home = os.path.expanduser('~').rstrip(os.sep)
    if not home:
        return p
    # **比到路徑邊界**，不是裸前綴。裸前綴在 HOME=/home/ann 時會把
    # /home/anna/x 改寫成 ~a/x —— 一個不存在的路徑，而這份輸出的去向是 issue。
    if p == home:
        return '~'
    if p.startswith(home + os.sep):
        return '~' + p[len(home):]
    return p


# marker 壞到讀端會整體拒開時，**這一輪的每一個數字都不能拿去定批次範圍**
# ——不只 venue 那一列。author 才是 campaign 的終局量測，而前一版只在 venue
# 那一列掛但書，author 照常裸印（R6 finding 50）。
_store_unopenable = fmt_state in ('malformed', 'unreadable') or _too_new
_undecidable = fmt_state == 'undecidable'

print(f"store: {_tilde(root)}（{fmt_label()}）")
if _store_unopenable:
    print(f"{'':<14} ⚠ 讀端會整體拒開此 store，**下面每一列都不能拿去定 campaign "
          "的批次範圍**——它們是直接掃 YAML 得到的，不代表任何 binary 讀得到這些內容")
elif _undecidable:
    print(f"{'':<14} ⚠ **本腳本判不出這個 marker 合不合法**，所以下面每一列都不能"
          "拿去定 campaign 的批次範圍。去問讀端：`akashic doctor --library <store>`")
elif _ceiling_unknown:
    # **這是 plugin 單獨安裝的常態**（marketplace 出貨時沒有 Sources/），所以它
    # 每次都會印。那是誠實的：每次都真的不知道。前一版只把這件事寫進 format 標籤，
    # 於是一個 `format: 99` 的 store（讀端明確拒開）照樣印四列計數、rc=0、
    # 沒有任何 ⚠——而 SKILL.md 的操作指引正是「先看第一行有沒有全域警告」。
    print(f"{'':<14} ⚠ 找不到原始碼，**無法判斷 format {fmt} 是否超過你的 binary "
          "支援上限**。若超過，任何 binary 都會整體拒開此 store，下面的數字就不能"
          "拿去定批次範圍。消除這個未知：在 repo 內跑，或設 AKASHIC_REPO=<repo 路徑>")
row("author", a_key, a_lit, len(a_distinct))
# venue 的三分支。**先報量到的，解釋擺後面** —— 前一版反過來（先套 format 的解釋、
# 再決定要不要印計數），於是在 format 未知時印出「下面的計數是實際掃到的」而下面
# 根本沒有計數行；在 format 缺檔時，明明手上握著已解析的 venue 邊，卻宣告
# 「venue 邊不存在於模型中」。兩者都是拿推論蓋掉量測。
_v_total = v_key + v_lit
if _v_total > 0:
    # 量到就印，不論 format 說什麼。format 與量測不一致時，把不一致本身報出來。
    row("venue", v_key, v_lit, len(v_distinct))
    if fmt_state in ('read', 'absent') and not _too_new and fmt < 11:
        # marker **說得出**一個版號，而它與量測不合——這才是「兩者不一致」。
        print(f"{'':<14} ↑ 註：marker 說 format {fmt}（< 11，該版本沒有 venue 邊），"
              "而上列是**實際解析到的**——兩者不一致，請查 store 狀態")
    elif fmt_state in ('malformed', 'unreadable'):
        # marker 壞掉時它**什麼版本都沒說**，談不上「說不是」。前一版把
        # 「marker 說不是」寫死在一個對三種狀態都會觸發的分支裡（R6 finding 28）。
        print(f"{'':<14} ↑ 註：marker 讀不出版號，所以無法判斷上列 venue 邊"
              "是否屬於這個 store 的模型——上游的全域警告已說明數字不可用")
elif isinstance(fmt, int) and fmt >= 11:
    row("venue", v_key, v_lit, len(v_distinct))          # 已部署且真的是 0
elif fmt_state == 'absent':
    # **缺檔不是壞掉**：讀端明訂缺檔即 format 1。前一版對這個情形也印「先修好
    # marker」，而根本沒有東西要修，且那句話指名了一個動作（R6 finding 39）。
    print(f"{'venue':<14} 未部署（無 store.yaml ＝ format 1，而 venue 邊自 format 11 起"
          "才存在於模型中；本輪零 venue 邊——非「查完」。"
          "部署鏈見 repo 的 docs/store-format.md format 11 列（private，無存取權者取不到））")
elif fmt_state == 'read':
    print(f"{'venue':<14} 未部署（marker 說 format {fmt}，< 11——該版本沒有 venue 邊；"
          "本輪零 venue 邊——非「查完」。"
          "部署鏈見 repo 的 docs/store-format.md format 11 列（private，無存取權者取不到））")
else:
    print(f"{'venue':<14} **未知**（{fmt_label()}；且未解析到任何 venue 邊——"
          "無法區分「未部署」與「已部署但為 0」。先修 store.yaml 再重跑）")
row("affiliation", aff_key, aff_lit, len(aff_distinct))
row("org-parents", org_key, org_lit, len(org_distinct))
EOF
