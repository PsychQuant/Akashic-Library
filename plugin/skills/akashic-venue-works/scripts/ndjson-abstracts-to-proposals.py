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
接著：
    akashic enrich --library <root> --from proposals.json --json          # dry-run，先看 counts
    akashic enrich --library <root> --from proposals.json --json --apply  # 數字對了才寫
"""
import argparse, hashlib, json, os, pathlib, re, sys
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="sha256:<hex>（在 <library>/sources/ 解析）或 NDJSON 檔路徑")
    ap.add_argument("--library", default=os.environ.get("AKASHIC_LIBRARY") or os.path.expanduser("~/.akashic"),
                    help="store root（預設 $AKASHIC_LIBRARY 或 ~/.akashic）；只在 --source 為 digest 時用到")
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
        try:
            pathlib.Path(a.out).write_text(text, encoding="utf8")
        except OSError as e:
            sys.exit(f"✗ 無法寫入 --out {a.out}：{e.strerror}")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
