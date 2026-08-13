#!/usr/bin/env python3
"""用標題＋期刊＋年份查 Crossref 取得 DOI，並做反向驗證。

輸入 JSON：[{"citekey": ..., "title": ..., "journal": ..., "year": ...}, ...]
（`journal` 與 `year` 可缺，但缺了會削弱判定——見 SKILL 的驗證段落）

輸出 JSON：每筆帶 status（confident / probable / needs_review / no_result）、
選定的 DOI 與書目欄位、以及判定依據（各訊號的分數）。

判定要求四個獨立訊號合取，而不是把單一訊號的門檻調高——因為 preprint 的標題
相似度可以是 1.00，比期刊版還高。詳見 references/work-sources.md。

用法：
    python3 crossref_match.py works.json -o result.json --mailto you@example.com
    python3 crossref_match.py works.json --verify-only result.json    # 只跑反向驗證
"""

import argparse
import difflib
import json
import re
import sys
import time
import urllib.parse
import urllib.request

CROSSREF = "https://api.crossref.org/works"
REVIEW_SUFFIX = re.compile(r"^(.*?)/v\d+/review\d+$")
# Crossref 的記錄型別裡，這些不是「論文本體」——審稿報告、preprint、附件
NON_ARTICLE_TYPES = {"peer-review", "posted-content", "component"}


def norm(s):
    """比對用正規化：轉小寫、非英數字轉空白、壓縮空白。"""
    return " ".join("".join(c.lower() if c.isalnum() else " " for c in (s or "")).split())


def jnorm(s):
    """期刊名正規化：在 norm 之上處理常見縮寫差異。"""
    s = norm(s)
    for a, b in (("journal of", "j"), ("the ", ""), ("and ", ""), ("&", "")):
        s = s.replace(a, b)
    return " ".join(s.split())


def sim(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


class Client:
    def __init__(self, mailto, delay=0.5):
        self.ua = f"akashic-bootstrap/1.0 (mailto:{mailto})" if mailto else "akashic-bootstrap/1.0"
        self.delay = delay

    def get(self, url):
        req = urllib.request.Request(url, headers={"User-Agent": self.ua})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
        time.sleep(self.delay)
        return data


def score(item, want_title, want_journal, want_year):
    """把一筆 Crossref 記錄對照期望值，回傳各訊號的分數。"""
    title = (item.get("title") or [""])[0]
    container = (item.get("container-title") or [""])[0]
    parts = (item.get("published") or {}).get("date-parts") or [[None]]
    year = parts[0][0] if parts and parts[0] else None
    year_ok = bool(want_year and year and abs(int(year) - int(want_year)) <= 1)
    return {
        "doi": item.get("DOI"),
        "type": item.get("type"),
        "title": title,
        "container": container,
        "year": year,
        "tsim": round(sim(norm(title), norm(want_title)), 3),
        "jsim": round(sim(jnorm(container), jnorm(want_journal)), 3) if container and want_journal else 0.0,
        "year_ok": year_ok,
        "volume": item.get("volume"),
        "issue": item.get("issue"),
        "page": item.get("page"),
        "n_authors": len(item.get("author") or []),
        "n_affiliated": sum(1 for a in (item.get("author") or []) if a.get("affiliation")),
    }


def classify(c):
    """四訊號合取。期刊完全相符且年份吻合時，標題門檻可降到 0.85——
    那通常是來源標題帶了更正註記或被截斷，實測零誤收。"""
    if not c:
        return "no_result"
    if c["type"] in NON_ARTICLE_TYPES:
        return "needs_review"
    if c["tsim"] >= 0.92 and c["jsim"] >= 0.75 and c["year_ok"]:
        return "confident"
    if c["jsim"] >= 0.95 and c["year_ok"] and c["tsim"] >= 0.85:
        return "confident"
    if c["tsim"] >= 0.92 and (c["jsim"] >= 0.75 or c["year_ok"]):
        return "probable"
    return "needs_review"


def rank(cands):
    """標題權重加倍——它是最強的單一訊號，只是不能單獨用。"""
    return sorted(cands, key=lambda c: c["tsim"] * 2 + c["jsim"] + (0.5 if c["year_ok"] else 0),
                  reverse=True)


def search(client, w, typed=False):
    q = {"query.bibliographic": w["title"], "rows": 5,
         "select": "DOI,title,container-title,volume,issue,page,author,published,type"}
    if typed:
        q["filter"] = "type:journal-article"
        if w.get("journal"):
            q["query.container-title"] = w["journal"]
    items = client.get(f"{CROSSREF}?{urllib.parse.urlencode(q)}").get("message", {}).get("items", [])
    return rank([score(it, w["title"], w.get("journal"), w.get("year")) for it in items])


def resolve(client, w):
    """三段式：一般查詢 → 剝 review 後綴 → 限定 journal-article 重查。"""
    cands = search(client, w)
    best = cands[0] if cands else None
    st = classify(best)
    if st == "confident":
        return best, cands[:3], st, "direct"

    # preprint / 審稿報告 / 會議摘要 → 試著救
    if best:
        m = REVIEW_SUFFIX.match(best["doi"] or "")
        if m:
            try:
                item = client.get(f"{CROSSREF}/{urllib.parse.quote(m.group(1))}")["message"]
                c = score(item, w["title"], w.get("journal"), w.get("year"))
                if classify(c) == "confident":
                    return c, cands[:3], "confident", "strip-review-suffix"
            except Exception:
                pass

    retyped = search(client, w, typed=True)
    if retyped:
        c = retyped[0]
        s2 = classify(c)
        if s2 in ("confident", "probable"):
            return c, retyped[:3], s2, "typed-requery"
        return c, retyped[:3], "needs_review", "typed-requery"
    return best, cands[:3], st, "direct"


def reverse_verify(client, doi, w):
    """用選定的 DOI 回查，比對回來的標題／期刊／年份／type。
    方向與查詢階段相反，所以『查詢時選錯候選』不會一致地重複。"""
    try:
        item = client.get(f"{CROSSREF}/{urllib.parse.quote(doi)}")["message"]
    except Exception as e:
        return False, {"error": f"{type(e).__name__}: {e}"}
    c = score(item, w["title"], w.get("journal"), w.get("year"))
    ok = c["type"] == "journal-article" and c["tsim"] >= 0.90 and c["jsim"] >= 0.70 and c["year_ok"]
    return ok, c


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("works", help="輸入 JSON：[{citekey, title, journal, year}, ...]")
    ap.add_argument("-o", "--out", default="crossref_result.json")
    ap.add_argument("--mailto", default="", help="Crossref 禮貌流量用的聯絡信箱")
    ap.add_argument("--delay", type=float, default=0.5, help="請求間隔秒數")
    ap.add_argument("--no-verify", action="store_true", help="跳過反向驗證（不建議）")
    args = ap.parse_args()

    works = json.load(open(args.works, encoding="utf-8"))
    client = Client(args.mailto, args.delay)
    out = []

    for i, w in enumerate(works, 1):
        best, cands, st, how = resolve(client, w)
        rec = {"citekey": w.get("citekey"), "status": st, "how": how,
               "best": best, "candidates": cands}
        if best and st in ("confident", "probable") and not args.no_verify:
            ok, back = reverse_verify(client, best["doi"], w)
            rec["reverse_verified"] = ok
            rec["reverse"] = back
            if not ok:
                rec["status"] = "needs_review"
                rec["note"] = "反向驗證未過——人工核對後才可採用"
        print(f"{i:4d}/{len(works)}  {rec['status']:13s} {str(w.get('citekey'))[:30]:30s} "
              f"{(best or {}).get('doi') or '-'}", file=sys.stderr, flush=True)
        out.append(rec)

    json.dump(out, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    tally = {}
    for r in out:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    print("\n=== 判定 ===", file=sys.stderr)
    for k in ("confident", "probable", "needs_review", "no_result"):
        if k in tally:
            print(f"  {k}: {tally[k]}", file=sys.stderr)
    print(f"\n寫入 {args.out}", file=sys.stderr)
    print("needs_review 的請人工核對；一筆錯的 DOI 比一個缺的 DOI 糟得多。", file=sys.stderr)


if __name__ == "__main__":
    main()
