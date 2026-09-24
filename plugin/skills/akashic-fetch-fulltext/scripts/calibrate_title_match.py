#!/usr/bin/env python3
"""Measure verify_pdf's title rule on a folder of real PDFs.

For every PDF whose first page carries a DOI, fetch that DOI's title from
Crossref, then check:

    own    each file against its own title        → should be accepted
    main   each file against its main title only  → should be accepted
    cross  each file against every OTHER title    → should be rejected

twice: the title rule alone (title_match), and the whole decision (assess, with
the file's own metadata DOI, the record's DOI and Crossref's page range). The
decision's wrong-title column is near-tautological here — each file's DOI was
read from its own first page, so another record's DOI cannot match; it guards
against regressions, it does not measure the reply/erratum residual documented
in verify_pdf.py. Rerun
it when the rule changes or a new kind of PDF turns up. Not a unit test: it
needs the network and a folder of full texts, which never enter the repository.

    calibrate_title_match.py <folder> [--mailto you@example.org]
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_pdf import assess, metadata_doi, title_match  # noqa: E402

DOI = re.compile(r"\b(10\.\d{4,9}/[^\s\"<>]+)")


def crossref(doi: str, mailto: str | None) -> tuple[str | None, str | None]:
    url = "https://api.crossref.org/works/" + urllib.parse.quote(doi)
    if mailto:
        url += "?mailto=" + urllib.parse.quote(mailto)
    try:
        msg = json.load(urllib.request.urlopen(url, timeout=20))["message"]
    except Exception:
        return None, None
    title = (msg.get("title") or [None])[0]
    sub = (msg.get("subtitle") or [None])[0]
    return (f"{title}: {sub}" if title and sub else title), msg.get("page")


def pdftext(path: str, last: int) -> str:
    return subprocess.run(["pdftotext", "-l", str(last), path, "-"], capture_output=True, text=True).stdout


def main_title(title: str) -> str:
    return re.split(r"(?<=[:?—])\s*", title)[0].rstrip(":—").strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--mailto", help="Crossref polite-pool contact")
    args = ap.parse_args()

    rows = []
    for path in sorted(glob.glob(os.path.join(args.folder, "**", "*.pdf"), recursive=True)):
        m = DOI.search(pdftext(path, 1))
        if not m:
            continue
        doi = m.group(1).rstrip(".,;)")
        title, pages = crossref(doi, args.mailto)
        time.sleep(0.5)
        if title:
            info = subprocess.run(["pdfinfo", path], capture_output=True, text=True).stdout
            count = int(re.search(r"^Pages:\s+(\d+)", info, re.M).group(1))
            rows.append({"file": os.path.basename(path), "doi": doi, "title": title, "pages": pages,
                         "count": count, "text": pdftext(path, 2), "meta": metadata_doi(path)})

    articles = [r for r in rows if "supplement" not in r["file"].lower()]
    pairs = [(a, b) for a in rows for b in rows if a["doi"] != b["doi"]]
    print(f"files with a DOI and a Crossref title: {len(rows)}")
    bad = False
    # ok(downloaded file, record, title): the file brings its text and page
    # count, the record brings its title and page range.
    judges = {
        "title rule": lambda f, rec, t: bool(title_match(t, f["text"])),
        "whole decision, record DOI": lambda f, rec, t: assess(f["text"], f["count"], t, rec["pages"], rec["doi"], f["meta"])["is_article"],
    }
    for name, ok in judges.items():
        own = [r for r in articles if not ok(r, r, r["title"])]
        main = [r for r in articles if not ok(r, r, main_title(r["title"]))]
        wrong = [(a, b) for a, b in pairs if ok(a, b, b["title"])]
        print(f"── {name}")
        print(f"   own title accepted:        {len(articles) - len(own)}/{len(articles)}")
        print(f"   main title only accepted:  {len(articles) - len(main)}/{len(articles)}")
        print(f"   wrong title accepted:      {len(wrong)}/{len(pairs)}")
        for r in own:
            print("     own REJECTED:", r["file"], "|", r["title"][:60], "| pages", r["pages"])
        for r in main:
            print("     main-title REJECTED:", r["file"], "|", main_title(r["title"])[:60], "| pages", r["pages"])
        for a, b in wrong:
            print("     WRONG ACCEPT:", a["file"], "<-", b["title"][:60])
        bad = bad or bool(wrong)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
