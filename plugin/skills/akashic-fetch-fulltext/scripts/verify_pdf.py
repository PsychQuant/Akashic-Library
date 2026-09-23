#!/usr/bin/env python3
"""Is this downloaded file the published article the store record describes?

A `%PDF` header only says "some PDF". On 2026-09-23 a `%PDF`-valid download was
the article's supplemental text (10 pages, first line "Supplemental Material")
instead of the 28-page article, and another was an NIH author manuscript. Both
passed a header check. This script compares the file with what the record says.

Usage:
    verify_pdf.py <file.pdf> --title "<record title>" [--pages 71--98]

Prints one JSON object and exits 0 when the file is judged to be the article,
1 when it is not (or cannot be read). Flags such as author-manuscript do not by
themselves fail the check: the file may still be the right work, but it is not
the version of record, and the caller must say so rather than silently store it
as one.
"""
import argparse
import json
import re
import subprocess
import sys
import unicodedata

# Markers read from the first TWO pages only (publishers prepend a cover page) —
# a references list mentioning "supplemental material" must not flag the article.
FIRST_PAGE_FLAGS = {
    "supplement": re.compile(r"\bsupplement(al|ary)\s+(material|text|information|appendix)\b", re.I),
    "author-manuscript": re.compile(r"\bauthor\s+manuscript\b", re.I),
}
# No "preprint" marker: measured 2026-09-24, a PsyArXiv preprint's first two pages
# contained none of psyarxiv/arxiv/preprint, so a text check would silently pass
# it. Whether a file is a preprint is decided from the RECORD (type
# unpublished-work, DOI prefix 10.31234), not from the file.

# Title threshold, measured 2026-09-24 on 10 files: all 9 correct pairings scored
# 1.0; a deliberately wrong pairing (same topic area) scored 0.8. 0.9 separates
# them. Ten files is a small sample — this is a calibrated guess, not a law, and
# the page check below is the second, independent line.
TITLE_THRESHOLD = 0.9


def normalize(text: str) -> list[str]:
    text = unicodedata.normalize("NFKC", text).lower()
    return [t for t in re.split(r"[^\w]+", text) if len(t) > 2]


def title_score(title: str, first_page: str) -> float:
    """Share of the title's content words that appear on the first page."""
    wanted = normalize(title)
    if not wanted:
        return 0.0
    present = set(normalize(first_page))
    return sum(1 for w in wanted if w in present) / len(wanted)


def expected_page_count(pages: str | None) -> int | None:
    """`71--98` → 28. Non-numeric or single pages → None (no page check)."""
    if not pages:
        return None
    m = re.fullmatch(r"\s*(\d+)\s*[-–—]+\s*(\d+)\s*", pages)
    if not m:
        return None
    first, last = int(m.group(1)), int(m.group(2))
    return last - first + 1 if last >= first else None


def assess(first_page: str, page_count: int, title: str, pages: str | None) -> dict:
    flags = [name for name, rx in FIRST_PAGE_FLAGS.items() if rx.search(first_page)]
    score = title_score(title, first_page)
    expected = expected_page_count(pages)
    # Publisher PDFs add a cover page or two; author manuscripts reflow and are
    # often longer. Allow +3 / -0 against the printed range for the version of
    # record; do not apply the page check to flagged non-VoR versions.
    if expected is None or flags:
        pages_ok = None
    else:
        pages_ok = expected <= page_count <= expected + 3
    is_article = score >= TITLE_THRESHOLD and "supplement" not in flags and pages_ok is not False
    return {
        "page_count": page_count,
        "expected_pages": expected,
        "pages_ok": pages_ok,
        "title_score": round(score, 2),
        "flags": flags,
        "is_article": is_article,
        "version_of_record": is_article and not flags,
    }


def read_pdf(path: str) -> tuple[str, int]:
    with open(path, "rb") as fh:
        if fh.read(5) != b"%PDF-":
            raise ValueError("not a PDF (no %PDF- header)")
    info = subprocess.run(["pdfinfo", path], capture_output=True, text=True, check=True).stdout
    m = re.search(r"^Pages:\s+(\d+)", info, re.M)
    if not m:
        raise ValueError("pdfinfo reported no page count")
    first = subprocess.run(["pdftotext", "-l", "2", path, "-"], capture_output=True, text=True, check=True).stdout
    return first, int(m.group(1))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--title", required=True)
    ap.add_argument("--pages")
    args = ap.parse_args()
    try:
        first_page, count = read_pdf(args.pdf)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(json.dumps({"error": str(exc), "is_article": False}, ensure_ascii=False))
        return 1
    result = assess(first_page, count, args.title, args.pages)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["is_article"] else 1


if __name__ == "__main__":
    sys.exit(main())
