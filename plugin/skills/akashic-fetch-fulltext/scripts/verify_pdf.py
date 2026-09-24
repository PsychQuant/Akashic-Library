#!/usr/bin/env python3
"""Is this downloaded file the published article the store record describes?

A `%PDF` header only says "some PDF". On 2026-09-23 a `%PDF`-valid download was
the article's supplemental text (10 pages, first line "Supplemental Material")
instead of the 28-page article, and another was an NIH author manuscript. Both
passed a header check. This script compares the file with what the record says.

Usage:
    verify_pdf.py <file.pdf> --title "<record title>" [--pages 71--98] [--doi 10.x/y]

Prints one JSON object and exits 0 when the file is judged to be the article,
1 when it is not (or cannot be read). Flags such as author-manuscript do not by
themselves fail the check: the file may still be the right work, but it is not
the version of record, and the caller must say so rather than silently store it
as one.
"""
import argparse
import html
import json
import re
import subprocess
import sys
import unicodedata
import urllib.parse
from difflib import SequenceMatcher

# Author-manuscript: read from the first TWO pages (NIH stamps it in the running
# header, so it appears wherever the text starts).
AUTHOR_MANUSCRIPT = re.compile(r"\bauthor\s+manuscript\b", re.I)
# Supplement: the marker must START one of the first HEAD_LINES non-empty lines.
# Measured 2026-09-24 on 41 files: all three real supplements open with it on
# line 1 ("Supplemental Material: …", "Supplementary Material for:"), while a
# Taylor & Francis ARTICLE carries "View supplementary material" on its cover page
# (line 11) and was wrongly flagged by a match-anywhere rule. Articles also carry
# their own "Supporting Information" heading or note further down the front
# matter (ACS, Wiley), so the window is the first 3 lines — line 1 plus room for a
# download stamp — not the whole head.
SUPPLEMENT_HEAD = re.compile(
    r"^\s*(supplement(al|ary)\s+(material|text|information|appendix|methods)s?"
    r"|supporting\s+information|electronic\s+supplementary\s+material|online\s+supplement)\b", re.I | re.M)
HEAD_LINES = 3
# No "preprint" marker: measured 2026-09-24, a PsyArXiv preprint's first two pages
# contained none of psyarxiv/arxiv/preprint, so a text check would silently pass
# it. Whether a file is a preprint is decided from the RECORD (type
# unpublished-work, DOI prefix 10.31234), not from the file.

# ── Is this the paper? The TITLE LINE decides, not scattered words ────────────
#
# The first two versions judged by word overlap: share of the title's words
# present anywhere in the first two pages, accepted at ≥ 0.9 — "calibrated" on 10
# files. Measured 2026-09-24 on 29 real PDFs with Crossref titles (each file's own
# DOI, read from its first page), crossing every file with every other title:
#
#                                   own title accepted   wrong title accepted
#     word overlap ≥ 0.9                   28/28               14/808
#     title line (below)                   28/28                0/808
#
# Same-field papers share their vocabulary: an abstract about the within-between
# dispute contains every word of "A critique of the cross-lagged panel model".
# Character bigrams for CJK failed the same way (a paper differing in its last two
# characters scored 0.91), and plain containment accepted a longer title that
# nests the target ("台灣大學生自我認定的發展與相關因素之研究").
#
# The rule: some run of 1–10 consecutive non-empty lines among the first 80, with
# spaces, line breaks and punctuation removed, must EQUAL the record title — or
# begin with it and continue after a subtitle separator (: ? —), because records
# often carry the main title only. Measured on the same corpus: main-title-only
# records 28/28 accepted, still 0/808 wrong. A trailing footnote marker (≤ 2
# digits) is tolerated.
#
# ── Identity is graded. Only the file's own metadata or two agreeing signals
#    accept automatically. ──────────────────────────────────────────────────
#
# Reviews R4–R6 (2026-09-24) kept finding a different work that passes: a generic
# title heading a section, "Title: A reply to X", a reply marker on the line before
# the title, the same in German, a sequel "Title 2" — and in R6, an erratum whose
# page 1 CITES the original's DOI before its own, so "first DOI on page 1" is not
# identity either. Word lists did not converge. What the page PRINTS can quote
# anything; what the FILE SAYS ABOUT ITSELF cannot be a citation:
#
#   strong  the PDF's own metadata (XMP) carries a DOI. Measured 2026-09-24 on
#           29 corpus articles: 13 carry one, all 13 equal the file's own DOI,
#           none carries a second DOI.
#   medium  the first DOI printed on page 1 — usually the file's own (29/29 in
#           the corpus), but an erratum or reply can print the ORIGINAL's first.
#   weak    title line + page count only.
#
#   metadata DOI = record            → title line + pages not contradicting
#   metadata DOI ≠ record            → rejected (the file says it is another work)
#   no metadata, page-1 DOI = record → title line + pages AGREEING; a reply word
#                                      after a subtitle separator is refused
#   no metadata, page-1 DOI ≠ record → rejected
#   no DOI to compare at all         → never accepted automatically (exit 5)
#
# Residual, stated rather than hidden: a reply that prints the original's DOI
# first, carries no metadata DOI, prints the original title as a line, AND has a
# page count within the tolerance of the original's is accepted. Every other R4–R6
# case is rejected by a test in tests/test_rules_and_verify.py.
# Cost, measured with calibrate_title_match.py on the 29-file corpus: own title
# accepted 22/28, wrong title accepted 0/808. The 6 rejected all lack a metadata
# DOI and a comparable page count (3 online-first and 1 preprint without a page
# range, 2 PMC author manuscripts whose page count is not compared) — they get a
# human look.
#
# Known limit: Traditional and Simplified Chinese do not match each other (NFKC
# does not unify them). That fails toward rejecting a right paper — exit 5, a
# human looks — never toward accepting a wrong one.
#
# Recalibrate with scripts/calibrate_title_match.py against a folder of PDFs.
CJK = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")
SUBTITLE_SEP = re.compile(r"[:：?？—–]")
TITLE_SCAN_LINES = 80
TITLE_MAX_SPAN = 10
# DOI characters: anything but whitespace and quotes — SICI DOIs contain < and >.
DOI_IN_TEXT = re.compile(r"\b10\.\d{4,9}/[^\s\"]+")
# After a separator these mark a DIFFERENT work that echoes the title. Used only
# when there is no DOI to compare (see above).
RESPONSE_AFTER_SEP = re.compile(
    r"^\|+(a|an|the)?(reply|rejoinder|response|comment|commentary|correction|erratum|corrigendum"
    r"|retraction|addendum|回應|評論|评论|勘誤|勘误|更正|商榷)")


def normalize(text: str) -> list[str]:
    text = unicodedata.normalize("NFKC", text).lower()
    return [t for t in re.split(r"[^\w]+", text) if len(t) > 2]


def _prep(text: str) -> str:
    # "&" and "and" are the same title (review R4: a record and its PDF often
    # disagree on which one they print).
    return unicodedata.normalize("NFKC", text).lower().replace("&", " and ")


def collapse(text: str) -> str:
    """Letters and digits only, lowercased: line wraps, spaces and punctuation gone."""
    return re.sub(r"[\W_]+", "", _prep(text))


def _marked(line: str) -> str:
    """Like collapse(), but subtitle separators survive as '|'."""
    return re.sub(r"[^\w|]+|_", "", SUBTITLE_SEP.sub("|", _prep(line)))


def norm_doi(doi: str) -> str:
    d = urllib.parse.unquote(doi).strip().lower()
    d = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", "", d)
    d = re.split(r"[?#]", d, maxsplit=1)[0]   # a pasted URL's query or fragment is not the DOI
    return d.rstrip(".,;:)]}/")


# In XMP (XML) a DOI ends at the next tag: "<" can never be part of it there — a
# SICI DOI's angle brackets are stored escaped (&lt; &gt;) and unescaped after.
# The first version reused DOI_IN_TEXT (which allows "<" for SICI DOIs in page
# text) and captured "10.1080/…</dc:identifier>" — every metadata DOI then
# "mismatched" and 19 of 28 right papers were rejected. Caught by calibration,
# not by the unit tests, 2026-09-24.
DOI_IN_XML = re.compile(r"\b10\.\d{4,9}/[^\s\"<>]+")


def doi_from_xmp(xmp: str) -> str | None:
    m = DOI_IN_XML.search(xmp)
    return norm_doi(html.unescape(m.group(0))) if m else None


def metadata_doi(path: str) -> str | None:
    """The DOI in the PDF's own XMP metadata — the file's identity, not a citation."""
    return doi_from_xmp(subprocess.run(["pdfinfo", "-meta", path], capture_output=True,
                                       text=True, errors="replace").stdout)


def page_one_doi(first_pages: str) -> str | None:
    """The first DOI printed on page 1 (pdftotext separates pages with \\f)."""
    m = DOI_IN_TEXT.search(first_pages.split("\f")[0])
    return norm_doi(m.group(0)) if m else None


def title_match(title: str, first_pages: str) -> str | None:
    """'exact', 'main-title' (the PDF adds a subtitle), 'main-title-response'
    (what follows the separator reads like a reply/comment/correction), or None."""
    t = collapse(title)
    if not t:
        return None
    lines = [m for m in (_marked(ln) for ln in first_pages.splitlines()) if m.replace("|", "")]
    lines = lines[:TITLE_SCAN_LINES]
    for i in range(len(lines)):
        block = ""
        for k in range(TITLE_MAX_SPAN):
            if i + k >= len(lines):
                break
            block += lines[i + k]
            plain = block.replace("|", "")
            if plain == t or re.fullmatch(re.escape(t) + r"\d{1,2}", plain):
                return "exact"
            if plain.startswith(t):
                after = _after_separator(block, len(t))
                if after is not None:
                    return "main-title-response" if RESPONSE_AFTER_SEP.match(after) else "main-title"
            if len(plain) > len(t) + 2 and not plain.startswith(t):
                break
    return None


def _after_separator(block: str, n: int) -> str | None:
    """What follows the n-th letter of block, if a separator and more text do."""
    seen = 0
    for j, ch in enumerate(block):
        if ch != "|":
            seen += 1
            if seen == n:
                rest = block[j + 1:]
                return rest if rest.startswith("|") and rest.strip("|") else None
    return None


def title_score(title: str, first_page: str) -> float:
    """Share of the title's content words present anywhere — REPORTED ONLY.

    Kept because a low score explains a rejection at a glance; it no longer
    decides (see the table above). CJK and all-short-word titles have no words
    to count and report the longest contiguous run instead.
    """
    wanted = normalize(title)
    if CJK.search(title) or not wanted:
        t, p = collapse(title), collapse(first_page)
        if not t:
            return 0.0
        m = SequenceMatcher(None, t, p, autojunk=False).find_longest_match(0, len(t), 0, len(p))
        return m.size / len(t)
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


def assess(first_page: str, page_count: int, title: str, pages: str | None,
           doi: str | None = None, meta_doi: str | None = None) -> dict:
    head = "\n".join([ln for ln in first_page.splitlines() if ln.strip()][:HEAD_LINES])
    flags = []
    if SUPPLEMENT_HEAD.search(head):
        flags.append("supplement")
    if AUTHOR_MANUSCRIPT.search(first_page):
        flags.append("author-manuscript")
    score = title_score(title, first_page)
    expected = expected_page_count(pages)
    # Publisher PDFs add a cover page or two; author manuscripts reflow and are
    # often longer. Allow +3 / -0 against the printed range for the version of
    # record; do not apply the page check to flagged non-VoR versions.
    if expected is None or flags:
        pages_ok = None
    else:
        pages_ok = expected <= page_count <= expected + 3
    match = title_match(title, first_page)
    on_page = page_one_doi(first_page)
    wanted = norm_doi(doi) if doi else None
    own = norm_doi(meta_doi) if meta_doi else None
    if wanted and own:
        doi_state = "metadata-match" if own == wanted else "metadata-mismatch"
    elif wanted and on_page:
        doi_state = "page-match" if on_page == wanted else "page-mismatch"
    else:
        doi_state = "absent"
    base = bool(match) and "supplement" not in flags and pages_ok is not False
    if doi_state == "metadata-match":
        is_article = base
    elif doi_state == "page-match":
        is_article = base and pages_ok is True and match != "main-title-response"
    else:   # metadata-mismatch, page-mismatch, absent
        is_article = False
    return {
        "page_count": page_count,
        "expected_pages": expected,
        "pages_ok": pages_ok,
        "title_match": match,
        "doi_in_metadata": own,
        "doi_on_page": on_page,
        "doi_state": doi_state,
        "title_score": round(score, 2),
        "flags": flags,
        "is_article": is_article,
        "version_of_record": is_article and not flags,
    }


def read_pdf(path: str) -> tuple[str, int]:
    """First two pages' text and the page count."""
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
    ap.add_argument("--doi")
    args = ap.parse_args()
    try:
        first_page, count = read_pdf(args.pdf)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(json.dumps({"error": str(exc), "is_article": False}, ensure_ascii=False))
        return 1
    result = assess(first_page, count, args.title, args.pages, args.doi, metadata_doi(args.pdf))
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["is_article"] else 1


if __name__ == "__main__":
    sys.exit(main())
