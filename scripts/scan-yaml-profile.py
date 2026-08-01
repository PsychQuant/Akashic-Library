#!/usr/bin/env python3
"""掃描 library 內的 YAML 檔，統計 store YAML profile 外的語法用了多少。

用途：#33（store YAML 輸入 profile）的證據來源。宣稱「真實 corpus 遷移成本為零」
的那張表就是這支腳本產出的——把它放進 repo 是為了讓結論可重跑、可核對，而不是
只能相信 issue 上的數字。

用法：
    python3 scripts/scan-yaml-profile.py [library-root]

    library-root 預設 ./library。輸出兩段：
      1. regex 層的粗掃（含已知的 false positive，見 --inspect）
      2. YAML parser 層的 ground truth（需要 PyYAML；沒裝就只出第 1 段）

    --inspect  額外印出每個 regex 命中的實際文字，用來人工判斷是不是 false
               positive。2026-08-01 的實測：13 個 anchor/alias 命中全部是期刊名
               裡的 `&amp;` 與引號內的 `*keyword*` 標記，parser 層 0 命中。
"""
import sys
import pathlib
import re
import collections

# profile 外的語法（見 docs/specs/2026-08-01-akashic-yaml-input-profile-design.md §4）
ANCHOR_ALIAS = re.compile(r'(^|[\s\[{,])[&*][A-Za-z0-9_-]+')
TAG = re.compile(r'(^|\s)!!?[A-Za-z0-9_/-]*')
MERGE_KEY = re.compile(r'^\s*<<\s*:', re.M)
BLOCK_SCALAR = re.compile(r':\s*[|>][0-9+-]*\s*$', re.M)
EXOTIC_LINE_SEPS = re.compile('[  ]')

## 顯式 complex key（`? key`）——**這個統計是不完整的**（R12）。
## alias 落在 key 位置會在 compose 內部指數展開，但 YAML 的 mapping key
## 根本不需要 `?`：`*a12: 1`（block 隱式）、`{*a12: 1}`（flow）都繞過本判準。
## 保留此欄僅供參考，**不可**用來論證「corpus 對該 DoS 免疫」——真正相關的
## 是上面的 anchor/alias 統計。
COMPLEX_KEY = re.compile(r'^[ ]*\?(?=[ \t]|$)', re.M)

FEATURES = [
    "BOM", "NEL/LS/PS", "tab", "CR", "comment line", "inline comment",
    "multi-doc ---", "anchor/alias", "explicit tag", "merge key",
    "block scalar |>", "flow seq [..]", "flow map {..}", "complex key ? k",
]


def scan(root: pathlib.Path):
    files = sorted(root.rglob('*.yaml'))
    buckets = collections.OrderedDict((k, []) for k in FEATURES)
    depth = collections.Counter()

    for f in files:
        raw = f.read_bytes()
        if raw.startswith(b'\xef\xbb\xbf'):
            buckets["BOM"].append(f)
        if b'\r' in raw:
            buckets["CR"].append(f)

        text = raw.decode('utf-8', 'replace')
        if EXOTIC_LINE_SEPS.search(text):      buckets["NEL/LS/PS"].append(f)
        if '\t' in text:                       buckets["tab"].append(f)
        if re.search(r'^\s*#', text, re.M):    buckets["comment line"].append(f)
        if re.search(r'\S\s+#', text):         buckets["inline comment"].append(f)
        if re.search(r'^---', text, re.M):     buckets["multi-doc ---"].append(f)
        if ANCHOR_ALIAS.search(text):          buckets["anchor/alias"].append(f)
        if TAG.search(text):                   buckets["explicit tag"].append(f)
        if MERGE_KEY.search(text):             buckets["merge key"].append(f)
        if BLOCK_SCALAR.search(text):          buckets["block scalar |>"].append(f)
        if re.search(r':\s*\[', text):         buckets["flow seq [..]"].append(f)
        if re.search(r':\s*\{', text):         buckets["flow map {..}"].append(f)
        if COMPLEX_KEY.search(text):           buckets["complex key ? k"].append(f)

        lines = [l for l in text.splitlines() if l.strip()]
        d = max((len(l) - len(l.lstrip(' '))) for l in lines) if lines else 0
        depth[d // 2] += 1

    return files, buckets, depth


def ground_truth(files):
    """用真正的 parser 確認 —— regex 會誤判，parser 不會。"""
    try:
        import yaml
    except ImportError:
        print("\n(PyYAML 未安裝，跳過 parser 層 ground truth：pip install pyyaml)")
        return None

    anchored, tagged, tagged_core, failed = [], [], [], []
    for f in files:
        try:
            for ev in yaml.parse(f.read_text(encoding='utf-8')):
                if getattr(ev, 'anchor', None):
                    anchored.append(f.name)
                    break
                # R11（R10-verify M9）：原本用 `not startswith('tag:yaml.org,2002:')`
                # 排除標準 URI——但 PyYAML 會把**顯式** `!!str` / `!!binary` 也展開成
                # 標準 URI，於是顯式 core tag（profile §4 明文禁止）被誤判為「無 tag」。
                # 改成：只要 event 帶 tag 就記錄，另分「標準 URI」與「自訂」兩欄，
                # 讓報告能區分而不是靜默漏掉。
                t = getattr(ev, 'tag', None)
                if t:
                    (tagged if not t.startswith('tag:yaml.org,2002:') else tagged_core).append(f.name)
                    break
        except Exception as e:
            failed.append((f.name, f"{type(e).__name__}: {str(e)[:60]}"))
    return anchored, tagged, tagged_core, failed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    inspect = '--inspect' in sys.argv
    root = pathlib.Path(args[0]) if args else pathlib.Path('library')

    if not root.is_dir():
        print(f"✗ {root} 不存在或不是目錄。用法：{sys.argv[0]} [library-root]")
        return 2

    files, buckets, depth = scan(root)
    print(f"library root : {root}")
    print(f"total files  : {len(files)}")
    print()
    print(f"{'FEATURE (regex 粗掃)':22} {'FILES':>6}   examples")
    for name, hits in buckets.items():
        ex = ', '.join(p.name for p in hits[:2]) if hits else ''
        flag = '  <-- 命中，需人工核對' if hits else ''
        print(f"{name:22} {len(hits):6}   {ex}{flag}")
    print()
    print("nesting depth (max indent / 2):", dict(sorted(depth.items())))

    gt = ground_truth(files)
    if gt is not None:
        anchored, tagged, tagged_core, failed = gt
        print()
        print("--- YAML parser ground truth（權威）---")
        print(f"真 anchor      : {len(anchored)}  {anchored[:3]}")
        print(f"非標準 tag     : {len(tagged)}  {tagged[:3]}")
        # profile §4 同樣禁止顯式 core tag——與「非標準 tag」分欄是為了讓報告
        # 看得出差別，而不是像 R11 之前那樣被 startswith 濾掉後靜默歸零。
        print(f"顯式 core tag  : {len(tagged_core)}  {tagged_core[:3]}")
        if failed:
            print(f"parse 失敗     : {len(failed)}  {failed[:3]}")

    if inspect:
        print()
        print("--- regex 命中的實際文字（人工判斷 false positive）---")
        for f in buckets["anchor/alias"] + buckets["inline comment"]:
            text = f.read_text(encoding='utf-8', errors='replace')
            for line in text.splitlines():
                if ANCHOR_ALIAS.search(line) or re.search(r'\S\s+#', line):
                    print(f"  {f.name}: {line.strip()[:110]}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
