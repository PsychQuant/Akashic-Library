#!/usr/bin/env python3
"""Publisher rules: from the URL a landing page settled on, derive the PDF URL.

Each rule exists because the page's own link pointed somewhere that returns HTML
instead of the file. Every rule records the date it was observed; a rule that
has not been re-observed is a claim about a publisher's site that may have
drifted (see ../../../rules/assertions-must-be-measured.md).

Usage:
    pdf_url_rules.py <final-landing-url> [<page-link>]

Prints the PDF URL to use, or nothing when no rule applies (the caller then
uses the page's own link). Exit 0 either way.
"""
import re
import sys
from urllib.parse import unquote, urlsplit


# View suffixes a landing URL can carry AFTER the DOI. A DOI itself may contain
# `/` (SICI DOIs do), so the capture cannot stop at the first slash; instead the
# known view segments are peeled off the end.
VIEW_SUFFIX = re.compile(r"/(abstract|full|fulltext|references|citedby|figures|tables|suppl|supplementary|epdf|pdf)/?$", re.I)


def doi_from_path(path: str) -> str | None:
    """The DOI after `/doi/` (optionally `/doi/full/`, `/doi/abs/`, `/doi/epdf/`)."""
    m = re.search(r"/doi/(?:full/|abs/|epdf/|reader/|pdf/|pdfdirect/)?(10\.[^?#]+)", path)
    if not m:
        return None
    doi = m.group(1).rstrip("/")
    while VIEW_SUFFIX.search(doi):
        doi = VIEW_SUFFIX.sub("", doi).rstrip("/")
    return doi


def pdf_url(final_url: str, page_link: str | None = None) -> str | None:
    parts = urlsplit(final_url)
    host = parts.netloc.lower()
    path = parts.path

    # SAGE — 2026-09-23: citation_pdf_url pointed at /doi/reader/ (an HTML reader,
    # text/html). /doi/pdf/<doi>?download=true returned application/pdf.
    if host == "journals.sagepub.com":
        doi = doi_from_path(path)
        return f"https://journals.sagepub.com/doi/pdf/{doi}?download=true" if doi else None

    # Wiley — 2026-09-23: /doi/pdf/<doi> returned the HTML viewer (text/html);
    # /doi/pdfdirect/<doi> returned application/pdf.
    if host == "onlinelibrary.wiley.com":
        doi = doi_from_path(path)
        return f"https://onlinelibrary.wiley.com/doi/pdfdirect/{doi}" if doi else None

    # APA PsycNet — 2026-09-23: /record/<id> and /fulltext/<id>.html both map to
    # /fulltext/<id>.pdf. When the site stays on doiLanding?doi=…, the id comes
    # from the page's /record/<id> link (pass it as page_link).
    if host == "psycnet.apa.org":
        m = re.match(r"/(?:record|fulltext)/(\d{4}-\d{5}-\d{3})", path)
        if not m and page_link:
            m = re.search(r"/record/(\d{4}-\d{5}-\d{3})", unquote(page_link))
        return f"https://psycnet.apa.org/fulltext/{m.group(1)}.pdf" if m else None

    return None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: pdf_url_rules.py <final-landing-url> [<page-link>]", file=sys.stderr)
        return 2
    url = pdf_url(argv[1], argv[2] if len(argv) > 2 else None)
    if url:
        print(url)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
