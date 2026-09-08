#!/usr/bin/env python3
"""階段 B 的摘要存檔（NDJSON）→ `akashic enrich --from` 的 `[Proposal]`（#516）。

**為什麼住在這個 skill 而不是 CLI 子命令**：NDJSON 的形狀（每列
`{"doi","status","abstract","title","year","landing","page_title","retrieved"}`）是本 skill
階段 B 的 scrape 產物，不是 store 的契約；store 的公開面只有 `[Proposal]` JSON，而
`AddOnlyEnrichment.decodeProposals` 是它唯一的解析器。把私有形狀焊進 CLI 要在
`mcp-cli-parity` 加一列、換一個來源又得再長一個子命令。adapter 跟產物住一起。

**三條紀律**：
1. 只收 `status == "got"`、摘要非空、DOI 在場的列；其餘每一列在 stderr 逐筆具名
   （`skip\\t<reason>\\t<doi>\\tline <n>`）——丟棄必須可見（`lossless-intake` 執行細節 3）。
2. `doi` **原樣透傳**：URL 前綴與大小寫由 core 的 `DOI` 正規化吸收，本腳本**不**複製那條
   規則。腳本自己只有一條更弱的身分規則——逐位元相同的 DOI 字串——大小寫／前綴不同的
   近重複兩筆都輸出、留給 core（它會把第二筆報成 `skipped`，不會靜默）。同 DOI 而摘要
   **不同**不是冗餘是衝突：理由印 `conflicting-duplicate`（仍取第一列），與 `duplicate-doi`
   分開具名（#516 verify）。
4. skip 報告不可被資料偽造：`doi`／`status` 裡的控制字元跳脫、長度截斷（`displaySafe`
   的同一立場），`doi` 含換行不得憑空多出一列（#516 verify）。
3. 決定論、無網路：同一輸入輸出逐位元相同（`sort_keys`）。`--source` 給 digest 時走
   `sources/<前 2 hex>/<其餘 62>`（`SourceStore` 的分片慣例）並驗 sha256；給路徑時由
   位元組算出 `sourceDigest`。

用法：
    ndjson-abstracts-to-proposals.py --source sha256:<hex> [--library <root>] [--out proposals.json]
    ndjson-abstracts-to-proposals.py --source /path/to/file.ndjson [--out proposals.json]
`--library` 的解析鏈比 CLI 窄，只有三段：`--library` → `$AKASHIC_LIBRARY` → `~/.akashic`。
**不讀** `$AKASHIC_HOME/config.yaml` 的 `current`（#519 Expected 3 裁決：接上去等於在這支
Python 腳本裡重新實作 registry 的解析鏈，那是把「一份描述的副本」換成「一份實作的副本」，
而後者更糟——描述分岔讀得出來，實作分岔只在特定 profile 下顯形）。`--source` 是 digest 時
走內容定址，library 取錯只會「找不到那個 digest」，是可見的失敗。

`--out` 拒絕寫到非普通檔（symlink／目錄／…），寫入走同目錄 temp ＋ `os.replace` 原子替換，
並把解析後的絕對路徑印到 stderr。

接著：
    akashic enrich --library <root> --from proposals.json --json          # dry-run，先看 counts
    akashic enrich --library <root> --from proposals.json --json --apply  # 數字對了才寫
"""
import argparse, hashlib, json, os, pathlib, re, stat, sys, tempfile
from collections import Counter

DIGEST_RE = re.compile(r"^sha256:([0-9a-fA-F]{64})$")
SKIP_MAX = 200


def display_safe(s: str, max_len: int = SKIP_MAX) -> str:
    """控制字元（含換行、ESC）跳脫成 \\xNN／\\n 形、超長截斷——skip 報告是給人讀的，
    不能讓資料本身改寫報告的形狀。"""
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\n": out.append("\\n")
        elif ch == "\t": out.append("\\t")
        elif o < 0x20 or o == 0x7f: out.append(f"\\x{o:02x}")
        else: out.append(ch)
    r = "".join(out)
    return r if len(r) <= max_len else r[:max_len] + "…"


def resolve_source(source: str, library: pathlib.Path):
    """回 (bytes, digest)。digest 形驗內容定址；路徑形算 digest。"""
    if source.lower().startswith("sha256:"):
        m = DIGEST_RE.match(source)
        if not m:
            sys.exit(f"✗ 不是合法的 digest（sha256: 之後須恰 64 個 hex）：{display_safe(source, 90)}")
        hex_ = m.group(1).lower()
        path = library / "sources" / hex_[:2] / hex_[2:]
        if not path.is_file():
            sys.exit(f"✗ 存檔不存在：{path}（digest sha256:{hex_}）")
        data = path.read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        if actual != hex_:
            sys.exit(f"✗ 內容定址不符：{path} 的 sha256 是 {actual}，不是 {hex_}——不輸出任何提案")
        return data, f"sha256:{hex_}"
    path = pathlib.Path(source)
    if not path.is_file():
        sys.exit(f"✗ 檔案不存在：{path}")
    data = path.read_bytes()
    return data, "sha256:" + hashlib.sha256(data).hexdigest()


def convert(data: bytes, digest: str):
    proposals, skips = [], []
    seen = {}          # doi → 已接受的摘要（判冗餘 vs 衝突）
    rows = 0
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        sys.exit(f"✗ 存檔不是 UTF-8（{e.reason}，byte {e.start}）——不輸出任何提案")
    for n, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip():
            continue
        rows += 1
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.exit(f"✗ 第 {n} 行不是合法 JSON：{e}")
        doi = row.get("doi")
        status = row.get("status")
        abstract = row.get("abstract")
        reason = None
        if not isinstance(doi, str) or not doi.strip():
            reason = "no-doi"
        elif status != "got":
            reason = f"status:{status}"
        elif not isinstance(abstract, str) or not abstract.strip():
            reason = "empty-abstract"
        elif doi in seen:
            reason = "duplicate-doi" if seen[doi] == abstract.strip() else "conflicting-duplicate"
        if reason:
            skips.append((reason, doi if isinstance(doi, str) and doi.strip() else "(no doi)", n))
            continue
        seen[doi] = abstract.strip()
        proposals.append({"doi": doi, "fields": {"abstract": abstract.strip()}, "sourceDigest": digest})
    return proposals, skips, rows


def write_out(path_str: str, text: str) -> None:
    """`--out` 的寫入語意（#519 Expected 1 裁決）。

    三條，順序固定：

    1. 目標存在且**不是普通檔**（symlink／目錄／FIFO／socket／device）→ 硬錯誤、具名、零寫入。
    2. 否則同目錄開 temp、寫完 `os.replace()` 原子替換。
    3. **無論成敗**，把解析後的絕對路徑印到 stderr。

    **為什麼拒絕 symlink 而不是「跟隨但原子替換」**：#516 verify 實測 `ln -sf victim.txt
    outlink.json` 之後 `--out ./outlink.json` **改到了 victim.txt**——逃逸到另一條路徑。
    原子替換本身就不會逃逸（`rename(2)` 作用在名字上、不跟隨 symlink），但那會把使用者
    刻意建立的導向**默默換成實體檔**。拒絕是唯一不做假設的選項。

    **為什麼不加 `--force`**：本 repo 對 `--force` 有明文立場（`idd-close`：「第一次是我趕
    時間，第三次就變成反正都 force」）。重跑覆寫這個中間產物是**常態**動作，把常態放在旗標
    後面訓練出來的正是那個反射，而反射一旦養成，旗標對真正危險的那次也不會攔住。

    **為什麼印絕對路徑**：`--out ~/.akashic/store.yaml` 這種**指錯地方**，上面兩條都擋不住
    （它是普通檔），加旗標也擋不住（旗標防的是「不小心覆寫」）。可見性才是對症的。

    **權限會變，而這是刻意的**：`mkstemp` 建的檔是 `0600`，`os.replace` 換的是 inode，所以
    **覆寫一個既有的 `0644` 檔之後它會變成 `0600`**（實測）。舊的 `write_text` 走 umask，通常
    是 `0644`。這裡不還原原本的 mode——`proposals.json` 裝的是第三方逐字摘要（含出版商版權
    聲明，SKILL.md 已載明），`0600` 對這個內容更對。寫出來是因為它是**安靜的**行為改變。

    **TOCTOU**：第 1 條與第 2 條之間有窗，但那個窗**不會造成逃逸**——`os.replace` 換的是
    名字，即使競爭者剛插入一個 symlink，被換掉的也是那個 symlink 本身，不會寫穿到它指向
    的檔。第 1 條買到的是「拒絕」而不是「不逃逸」，兩者是不同的性質。
    """
    resolved = pathlib.Path(os.path.abspath(os.path.expanduser(path_str)))
    print(f"→ --out 寫入 {resolved}", file=sys.stderr)

    try:
        st = os.lstat(resolved)          # lstat 不跟隨 symlink——跟隨的話這道檢查等於沒做
    except FileNotFoundError:
        st = None
    except OSError as e:
        sys.exit(f"✗ 無法檢查 --out {resolved}：{e.strerror}")

    if st is not None and not stat.S_ISREG(st.st_mode):
        m = st.st_mode
        kind = ("symlink" if stat.S_ISLNK(m) else "目錄" if stat.S_ISDIR(m)
                else "FIFO" if stat.S_ISFIFO(m) else "socket" if stat.S_ISSOCK(m)
                else "字元裝置" if stat.S_ISCHR(m) else "區塊裝置" if stat.S_ISBLK(m)
                else "非普通檔")
        # 括號裡那句**只對 symlink 為真**——對目錄／FIFO 講「跟隨它會改到另一條路徑上的檔」
        # 是假的。訊息按類別分，不要用一句話蓋兩種情形。
        why = ("跟隨它會改到另一條路徑上的檔（#516 verify 實測過），"
               "取代它則會默默拆掉你刻意建的導向" if stat.S_ISLNK(m)
               else "本腳本只寫普通檔")
        sys.exit(f"✗ --out {resolved} 已存在且是{kind}，不是普通檔——拒絕寫入，零寫入。\n"
                 f"  {why}。這支腳本的產出是 $TMPDIR 裡的短命中間產物；"
                 f"要寫到別處請直接把那個路徑給 --out。")

    # **`mkstemp` 也要在 try 裡**：它會在父目錄不存在時拋 `FileNotFoundError`（`OSError`
    # 的子類），寫在 try 之外就變成 traceback 而不是這裡承諾的具名錯誤——實測踩到。
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=str(resolved.parent), prefix=f".{resolved.name}.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf8") as f:
            f.write(text)
        os.replace(tmp, resolved)
    except OSError as e:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        sys.exit(f"✗ 無法寫入 --out {resolved}：{e.strerror}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="sha256:<hex>（在 <library>/sources/ 解析）或 NDJSON 檔路徑")
    ap.add_argument("--library", default=os.environ.get("AKASHIC_LIBRARY") or os.path.expanduser("~/.akashic"),
                    help="store root；只在 --source 為 digest 時用到。"
                         "**本腳本的解析鏈只有三段**：--library → $AKASHIC_LIBRARY → ~/.akashic。"
                         "它**不讀** $AKASHIC_HOME/config.yaml 的 current——CLI 有那一段，本腳本沒有")
    ap.add_argument("--out", help="寫入的 JSON 檔（省略則印到 stdout）")
    a = ap.parse_args()

    data, digest = resolve_source(a.source, pathlib.Path(a.library).expanduser())
    proposals, skips, rows = convert(data, digest)

    for reason, doi, n in skips:
        print(f"skip\t{display_safe(reason, 60)}\t{display_safe(doi)}\tline {n}", file=sys.stderr)
    by_reason = Counter(r for r, _, _ in skips)
    detail = ", ".join(f"{k}={v}" for k, v in sorted(by_reason.items()))
    print(f"rows={rows} proposals={len(proposals)} skipped={len(skips)}" + (f" ({detail})" if detail else ""), file=sys.stderr)

    text = json.dumps(proposals, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if a.out:
        write_out(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
