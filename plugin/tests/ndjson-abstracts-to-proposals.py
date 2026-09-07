#!/usr/bin/env python3
"""`ndjson-abstracts-to-proposals.py` 的 fixture 測試（#516）。

階段 B 的摘要存檔是 NDJSON（每列 `{"doi","status","abstract",…}`），要餵進
`akashic enrich --from` 得先變成 `[Proposal]`。這支守衛釘住轉換的三件事：

1. **只收 `status == got` 且摘要非空且 DOI 在場的列**；其餘每一列都在 stderr 的
   skip 報告裡逐筆具名（`lossless-intake` 執行細節 3：丟棄必須可見）。
2. **`doi` 原樣透傳、不正規化**——URL 前綴與大小寫由 core 的 `DOI` 吸收；腳本裡再寫
   一份正規化就是第二份會分岔的副本。所以「重複」只認**逐位元相同**的 DOI 字串。
3. **決定論**：同一輸入兩次輸出逐位元相同；digest 給定時驗內容定址（sha256 不符即拒）。

fixture 只有 6 列、不碰網路、不需要 build。
"""
import hashlib, json, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py"

def fail(msg):
    print(f"✗ {msg}", file=sys.stderr); sys.exit(1)

ROWS = [
    {"doi": "https://doi.org/10.1037/1082-989x.3.2.231", "status": "got", "abstract": "Abstract one.", "title": "T1", "year": 1998},
    {"doi": "https://doi.org/10.1037/1082-989x.3.2.231", "status": "got", "abstract": "Abstract dup.", "title": "T1", "year": 1998},
    {"doi": "https://doi.org/10.1037/1082-989x.1.4.354", "status": "landing-failed", "abstract": "", "title": "T3", "year": 1996},
    {"doi": "https://doi.org/10.1037//1082-989x.6.4.430-450", "status": "none-verified", "abstract": "", "title": "T4", "year": 2001},
    {"doi": None, "status": "landing-failed", "abstract": "", "title": "T5", "year": 1997},
    {"doi": "https://doi.org/10.1037/1082-989x.2.2.173", "status": "got", "abstract": "   ", "title": "T6", "year": 1997},
]
NDJSON = "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in ROWS).encode("utf8")
HEX = hashlib.sha256(NDJSON).hexdigest()
DIGEST = f"sha256:{HEX}"

def run(args, env=None):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=env)

if not SCRIPT.is_file():
    fail(f"腳本不存在：{SCRIPT.relative_to(ROOT)}")

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp) / "lib"
    blob = root / "sources" / HEX[:2] / HEX[2:]
    blob.parent.mkdir(parents=True)
    blob.write_bytes(NDJSON)

    # 1. digest 形：解析 sources/<2>/<62>，輸出恰 1 筆，doi 原樣
    r = run(["--library", str(root), "--source", DIGEST])
    if r.returncode != 0:
        fail(f"digest 形應 exit 0，得 {r.returncode}\n{r.stderr}")
    out = json.loads(r.stdout)
    if out != [{"doi": ROWS[0]["doi"], "fields": {"abstract": "Abstract one."}, "sourceDigest": DIGEST}]:
        fail(f"輸出不符：{out}")
    skips = [l for l in r.stderr.splitlines() if l.startswith("skip\t")]
    reasons = sorted(l.split("\t")[1] for l in skips)
    if reasons != sorted(["duplicate-doi", "status:landing-failed", "status:none-verified", "no-doi", "empty-abstract"]):
        fail(f"skip 理由不符：{reasons}\n{r.stderr}")
    if not any(l.startswith("skip\tno-doi\t(no doi)\tline 5") for l in skips):
        fail(f"no-doi 那列應印 (no doi) 與行號 5：\n{r.stderr}")
    if "rows=6 proposals=1 skipped=5" not in r.stderr:
        fail(f"缺總結行：\n{r.stderr}")
    print("✓ digest 形：1 筆提案、5 列 skip 逐筆具名、總結行在")

    # 2. 路徑形：sourceDigest 由位元組算出，與 digest 形逐位元相同輸出
    r2 = run(["--source", str(blob)])
    if r2.returncode != 0 or r2.stdout != r.stdout:
        fail(f"路徑形輸出應與 digest 形逐位元相同\nrc={r2.returncode}\n{r2.stderr}")
    print("✓ 路徑形：sourceDigest 由內容算出，輸出決定論")

    # 3. --out 寫檔，stdout 空
    outp = pathlib.Path(tmp) / "proposals.json"
    r3 = run(["--library", str(root), "--source", DIGEST, "--out", str(outp)])
    if r3.returncode != 0 or r3.stdout.strip() or outp.read_text(encoding="utf8") != r.stdout:
        fail("--out 應把同一份 JSON 寫進檔案且 stdout 為空")
    print("✓ --out：寫檔內容與 stdout 形相同")

    # 4. 內容定址：digest 對不上內容 → 拒絕、零輸出
    bad_hex = "0" * 64
    bad = root / "sources" / bad_hex[:2] / bad_hex[2:]
    bad.parent.mkdir(parents=True, exist_ok=True); bad.write_bytes(NDJSON)
    r4 = run(["--library", str(root), "--source", f"sha256:{bad_hex}"])
    if r4.returncode == 0 or r4.stdout.strip():
        fail("digest 與內容不符時應非零退出且不輸出提案")
    print("✓ 內容定址：digest 不符即拒")

    # 5. 找不到存檔 → 非零、訊息含路徑
    r5 = run(["--library", str(root), "--source", "sha256:" + "f" * 64])
    if r5.returncode == 0 or "sources/ff/" not in r5.stderr:
        fail(f"缺檔應非零退出並印出解析後的路徑：\n{r5.stderr}")
    print("✓ 缺檔：非零退出、路徑可見")

print("✓ ndjson-abstracts-to-proposals：全部通過")
