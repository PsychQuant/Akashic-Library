#!/usr/bin/env python3
"""`ndjson-abstracts-to-proposals.py` 的 fixture 測試（#516）。

階段 B 的摘要存檔是 NDJSON（每列 `{"doi","status","abstract",…}`），要餵進
`akashic enrich --from` 得先變成 `[Proposal]`。這支守衛釘住轉換的幾件事：

1. **只收 `status == got` 且摘要非空且 DOI 在場的列**；其餘每一列都在 stderr 的
   skip 報告裡逐筆具名（`lossless-intake` 執行細節 3：丟棄必須可見）。
2. **`doi` 原樣透傳、不正規化**——URL 前綴與大小寫由 core 的 `DOI` 吸收；腳本裡再寫
   一份正規化就是第二份會分岔的副本。所以「重複」只認**逐位元相同**的 DOI 字串：
   近重複（大小寫／前綴不同）**兩筆都輸出**，交給 core 判（#516 verify：把去重改成
   正規化後比對，舊 fixture 仍綠——那正是 148→82 全套算術依賴的前提，卻沒被釘住）。
3. **同 DOI 而摘要不同不是「重複」是「衝突」**（#516 verify DA）：理由印
   `conflicting-duplicate`，與摘要相同的 `duplicate-doi` 分開具名。
4. **skip 報告不可被資料偽造**（#516 verify security）：`doi`／`status` 裡的控制字元
   要跳脫、長度要有上限——`doi` 含 `\n` 不得憑空多出一列。
5. **決定論**：同一輸入兩次輸出逐位元相同；digest 給定時驗內容定址（sha256 不符即拒），
   大寫 hex 仍是 digest 形（不得靜默落到路徑形）。
6. 錯誤要具名：非 UTF-8、壞的 `--out` 目錄都印 `✗ …`，不吐 traceback。

fixture 只有 9 列（含 BOM 與一個空行）、不碰網路、不需要 build。
"""
import hashlib, json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py"

def fail(msg):
    print(f"✗ {msg}", file=sys.stderr); sys.exit(1)

DOI1 = "https://doi.org/10.1037/1082-989x.3.2.231"
DOI1_UPPER = "https://doi.org/10.1037/1082-989X.3.2.231"          # 近重複：只差大小寫
FORGING_DOI = "10.1/x\nskip\tno-doi\tFORGED\tline 999\x1b[2J" + "z" * 300
ROWS = [
    {"doi": DOI1, "status": "got", "abstract": "Abstract one.", "title": "T1", "year": 1998},
    {"doi": DOI1, "status": "got", "abstract": "Abstract DIFFERENT.", "title": "T1", "year": 1998},   # 衝突
    {"doi": DOI1, "status": "got", "abstract": "Abstract one.", "title": "T1", "year": 1998},         # 冗餘
    {"doi": "https://doi.org/10.1037/1082-989x.1.4.354", "status": "landing-failed", "abstract": "", "title": "T3", "year": 1996},
    None,                                                                                             # 空行
    {"doi": "https://doi.org/10.1037//1082-989x.6.4.430-450", "status": "none-verified", "abstract": "", "title": "T4", "year": 2001},
    {"doi": None, "status": "landing-failed", "abstract": "", "title": "T5", "year": 1997},
    {"doi": "https://doi.org/10.1037/1082-989x.2.2.173", "status": "got", "abstract": "   ", "title": "T6", "year": 1997},
    {"doi": DOI1_UPPER, "status": "got", "abstract": "Abstract one.", "title": "T1", "year": 1998},   # 近重複穿透
    {"doi": FORGING_DOI, "status": "landing-failed", "abstract": "", "title": "T9", "year": 1999},    # 偽造嘗試
]
NDJSON = "﻿".encode("utf8") + "".join(("" if r is None else json.dumps(r, ensure_ascii=False)) + "\n" for r in ROWS).encode("utf8")
HEX = hashlib.sha256(NDJSON).hexdigest()
DIGEST = f"sha256:{HEX}"
EXPECTED = [
    {"doi": DOI1, "fields": {"abstract": "Abstract one."}, "sourceDigest": DIGEST},
    {"doi": DOI1_UPPER, "fields": {"abstract": "Abstract one."}, "sourceDigest": DIGEST},
]
EXPECTED_REASONS = sorted([
    "conflicting-duplicate", "duplicate-doi", "status:landing-failed", "status:none-verified",
    "no-doi", "empty-abstract", "status:landing-failed",
])

def run(args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)

if not SCRIPT.is_file():
    fail(f"腳本不存在：{SCRIPT.relative_to(ROOT)}")

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp) / "lib"
    blob = root / "sources" / HEX[:2] / HEX[2:]
    blob.parent.mkdir(parents=True)
    blob.write_bytes(NDJSON)

    # 1. digest 形：BOM 可讀；2 筆提案（近重複穿透）；7 列 skip 逐筆具名；rows 不算空行
    r = run(["--library", str(root), "--source", DIGEST])
    if r.returncode != 0:
        fail(f"digest 形應 exit 0，得 {r.returncode}\n{r.stderr}")
    if json.loads(r.stdout) != EXPECTED:
        fail(f"輸出不符：{r.stdout}")
    skips = [l for l in r.stderr.splitlines() if l.startswith("skip\t")]
    if sorted(l.split("\t")[1] for l in skips) != EXPECTED_REASONS:
        fail(f"skip 理由不符：{sorted(l.split(chr(9))[1] for l in skips)}\n{r.stderr}")
    if not any(l.startswith("skip\tno-doi\t(no doi)\tline 7") for l in skips):
        fail(f"no-doi 那列應印 (no doi) 與行號 7：\n{r.stderr}")
    if "rows=9 proposals=2 skipped=7" not in r.stderr:
        fail(f"總結行應是 rows=9 proposals=2 skipped=7（rows 不算空行）：\n{r.stderr}")
    print("✓ digest 形：BOM 可讀、近重複穿透、衝突與冗餘分開具名、rows 不算空行")

    # 2. skip 報告不可偽造：控制字元跳脫、長度上限；FORGED 不得成為獨立一行
    forged = [l for l in r.stderr.splitlines() if "FORGED" in l]
    if len(forged) != 1 or not forged[0].startswith("skip\tstatus:landing-failed\t"):
        fail(f"偽造的換行應被跳脫成同一行 skip：\n{r.stderr}")
    if "\x1b" in r.stderr or len(forged[0]) > 400:
        fail(f"控制字元應跳脫、doi 應截斷：len={len(forged[0])}")
    print("✓ skip 報告：換行／ESC 跳脫、長度截斷、無法偽造多一行")

    # 3. 路徑形：sourceDigest 由位元組算出，輸出與 digest 形逐位元相同
    r2 = run(["--source", str(blob)])
    if r2.returncode != 0 or r2.stdout != r.stdout:
        fail(f"路徑形輸出應與 digest 形逐位元相同\nrc={r2.returncode}\n{r2.stderr}")
    print("✓ 路徑形：sourceDigest 由內容算出，輸出決定論")

    # 4. 大寫 hex 仍是 digest 形：解析成功，sourceDigest 以小寫輸出
    r3 = run(["--library", str(root), "--source", "sha256:" + HEX.upper()])
    if r3.returncode != 0 or r3.stdout != r.stdout:
        fail(f"大寫 digest 應視同 digest 形並正規化為小寫：rc={r3.returncode}\n{r3.stderr}")
    print("✓ 大寫 digest：仍走內容定址、輸出相同")

    # 5. --out 寫檔，stdout 空
    outp = pathlib.Path(tmp) / "proposals.json"
    r4 = run(["--library", str(root), "--source", DIGEST, "--out", str(outp)])
    if r4.returncode != 0 or r4.stdout.strip() or outp.read_text(encoding="utf8") != r.stdout:
        fail("--out 應把同一份 JSON 寫進檔案且 stdout 為空")
    print("✓ --out：寫檔內容與 stdout 形相同")

    # 6. 內容定址：digest 對不上內容 → 拒絕、零輸出
    bad_hex = "0" * 64
    bad = root / "sources" / bad_hex[:2] / bad_hex[2:]
    bad.parent.mkdir(parents=True, exist_ok=True); bad.write_bytes(NDJSON)
    r5 = run(["--library", str(root), "--source", f"sha256:{bad_hex}"])
    if r5.returncode == 0 or r5.stdout.strip():
        fail("digest 與內容不符時應非零退出且不輸出提案")
    print("✓ 內容定址：digest 不符即拒")

    # 7. 找不到存檔 → 非零、訊息含路徑；格式錯的 digest → 具名拒絕（不落到路徑形）
    r6 = run(["--library", str(root), "--source", "sha256:" + "f" * 64])
    if r6.returncode == 0 or "sources/ff/" not in r6.stderr:
        fail(f"缺檔應非零退出並印出解析後的路徑：\n{r6.stderr}")
    r7 = run(["--library", str(root), "--source", "sha256:notahash"])
    if r7.returncode == 0 or "digest" not in r7.stderr or "檔案不存在" in r7.stderr:
        fail(f"格式錯的 sha256: 應以 digest 形具名拒絕，不得當成路徑：\n{r7.stderr}")
    print("✓ 缺檔／壞 digest：非零退出、訊息具名")

    # 8. 非 UTF-8 blob、壞的 --out 目錄：具名訊息，不吐 traceback
    binblob = pathlib.Path(tmp) / "bin.ndjson"; binblob.write_bytes(b"\xff\xfe\x00garbage\n")
    r8 = run(["--source", str(binblob)])
    r9 = run(["--source", str(blob), "--out", str(pathlib.Path(tmp) / "no-such-dir" / "p.json")])
    for name, rr in (("非 UTF-8", r8), ("壞 --out 目錄", r9)):
        if rr.returncode == 0 or "Traceback" in rr.stderr or "✗" not in rr.stderr:
            fail(f"{name} 應具名失敗（✗）且無 traceback：rc={rr.returncode}\n{rr.stderr[-300:]}")
    print("✓ 錯誤具名：非 UTF-8、壞 --out 目錄都不吐 traceback")

print("✓ ndjson-abstracts-to-proposals：全部通過")
