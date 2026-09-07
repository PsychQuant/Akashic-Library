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
2. `doi` **原樣透傳**：URL 前綴與大小寫由 core 的 `DOI` 正規化吸收；這裡再寫一份就是
   第二份會分岔的副本。所以「重複」只認逐位元相同的 DOI 字串；大小寫／前綴不同的近重複
   留給 core（它會把第二筆報成 `skipped`，不會靜默）。
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

DIGEST_RE = re.compile(r"^sha256:([0-9a-f]{64})$")


def resolve_source(source: str, library: pathlib.Path):
    """回 (bytes, digest)。digest 形驗內容定址；路徑形算 digest。"""
    m = DIGEST_RE.match(source)
    if m:
        hex_ = m.group(1)
        path = library / "sources" / hex_[:2] / hex_[2:]
        if not path.is_file():
            sys.exit(f"✗ 存檔不存在：{path}（digest {source}）")
        data = path.read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        if actual != hex_:
            sys.exit(f"✗ 內容定址不符：{path} 的 sha256 是 {actual}，不是 {hex_}——不輸出任何提案")
        return data, source
    path = pathlib.Path(source)
    if not path.is_file():
        sys.exit(f"✗ 檔案不存在：{path}")
    data = path.read_bytes()
    return data, "sha256:" + hashlib.sha256(data).hexdigest()


def convert(data: bytes, digest: str):
    proposals, skips = [], []
    seen = set()
    for n, raw in enumerate(data.decode("utf8").splitlines(), start=1):
        if not raw.strip():
            continue
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
            reason = "duplicate-doi"
        if reason:
            skips.append((reason, doi if isinstance(doi, str) and doi.strip() else "(no doi)", n))
            continue
        seen.add(doi)
        proposals.append({"doi": doi, "fields": {"abstract": abstract.strip()}, "sourceDigest": digest})
    return proposals, skips, n if data.strip() else 0


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
        print(f"skip\t{reason}\t{doi}\tline {n}", file=sys.stderr)
    by_reason = Counter(r for r, _, _ in skips)
    detail = ", ".join(f"{k}={v}" for k, v in sorted(by_reason.items()))
    print(f"rows={rows} proposals={len(proposals)} skipped={len(skips)}" + (f" ({detail})" if detail else ""), file=sys.stderr)

    text = json.dumps(proposals, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if a.out:
        pathlib.Path(a.out).write_text(text, encoding="utf8")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
