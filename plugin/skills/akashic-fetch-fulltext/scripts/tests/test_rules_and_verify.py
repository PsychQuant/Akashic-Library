#!/usr/bin/env python3
"""Offline tests for pdf_url_rules.py and verify_pdf.assess().

No network, no Safari, no PDFs: the cases are the ones observed on 2026-09-23/24
while fetching a real batch, frozen as text so they keep holding after the
publishers' sites drift. A publisher changing its URL scheme will not fail these
tests — they pin THIS code's behavior, not the publishers'.

    python3 plugin/skills/akashic-fetch-fulltext/scripts/tests/test_rules_and_verify.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from pdf_url_rules import pdf_url  # noqa: E402
from verify_pdf import assess, expected_page_count, title_score  # noqa: E402
from bot_signals import detect  # noqa: E402


class PdfUrlRules(unittest.TestCase):
    def test_sage_reader_link_is_replaced_by_download_url(self):
        self.assertEqual(
            pdf_url("https://journals.sagepub.com/doi/10.1177/0265407517718387",
                    "https://journals.sagepub.com/doi/reader/10.1177/0265407517718387"),
            "https://journals.sagepub.com/doi/pdf/10.1177/0265407517718387?download=true")

    def test_wiley_uses_pdfdirect(self):
        self.assertEqual(
            pdf_url("https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964"),
            "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1111/jopy.12964")

    def test_wiley_sici_doi_is_kept_verbatim(self):
        doi = "10.1002/(SICI)1099-0984(199909/10)13:5%3C389::AID-PER361%3E3.0.CO;2-A"
        self.assertEqual(
            pdf_url(f"https://onlinelibrary.wiley.com/doi/{doi}"),
            f"https://onlinelibrary.wiley.com/doi/pdfdirect/{doi}")

    def test_psycnet_fulltext_html_maps_to_pdf(self):
        self.assertEqual(
            pdf_url("https://psycnet.apa.org/fulltext/2020-54836-001.html"),
            "https://psycnet.apa.org/fulltext/2020-54836-001.pdf")

    def test_psycnet_doilanding_takes_id_from_record_link(self):
        self.assertEqual(
            pdf_url("https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285",
                    "/record/2022-13893-001?doi=1"),
            "https://psycnet.apa.org/fulltext/2022-13893-001.pdf")

    def test_psycnet_doilanding_without_record_link_gives_nothing(self):
        self.assertIsNone(pdf_url("https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285"))

    def test_unknown_publisher_defers_to_page_link(self):
        self.assertIsNone(pdf_url("https://www.tandfonline.com/doi/full/10.1080/10705511.2024.2379495"))


class VerifyPdf(unittest.TestCase):
    TITLE = "A Theory of States and Traits—Revised"

    def test_page_range_arithmetic(self):
        self.assertEqual(expected_page_count("71--98"), 28)
        self.assertEqual(expected_page_count("1013–1034"), 22)
        self.assertIsNone(expected_page_count("e81105"))
        self.assertIsNone(expected_page_count(None))

    def test_version_of_record_passes(self):
        r = assess("Downloaded from ... CP11CH04-Steyer\nA Theory of States and Traits—Revised",
                   28, self.TITLE, "71--98")
        self.assertTrue(r["is_article"])
        self.assertTrue(r["version_of_record"])

    def test_supplement_is_not_the_article(self):
        r = assess("Supplemental Material: Annu. Rev. Clin. Psychol. 2015. 11:71–98\n"
                   "A Theory of States and Traits—Revised\nA SUPPLEMENTAL TEXT TO CTT",
                   10, self.TITLE, "71--98")
        self.assertFalse(r["is_article"])
        self.assertIn("supplement", r["flags"])

    def test_author_manuscript_is_the_work_but_not_version_of_record(self):
        r = assess("NIH Public Access\nAuthor Manuscript\nA General Panel Model with Random and "
                   "Fixed Effects: A Structural Equations Approach",
                   36, "A General Panel Model with Random and Fixed Effects: A Structural Equations Approach",
                   "1--34")
        self.assertTrue(r["is_article"])
        self.assertFalse(r["version_of_record"])

    def test_same_topic_wrong_paper_is_rejected_on_title_alone(self):
        # Measured 2026-09-24: this pairing scored 0.8 and was caught only by the
        # page check. Without a page range the title threshold must catch it.
        first_page = "Personality Development Across the Life Course: The Argument for Change and Continuity"
        wrong_title = "The rank-order consistency of personality traits from childhood to old age"
        self.assertLess(title_score(wrong_title, first_page), 0.9)
        self.assertFalse(assess(first_page, 19, wrong_title, None)["is_article"])

    def test_page_count_far_from_range_is_rejected(self):
        r = assess(self.TITLE, 10, self.TITLE, "71--98")
        self.assertFalse(r["pages_ok"])
        self.assertFalse(r["is_article"])


class BotSignals(unittest.TestCase):
    def test_cloudflare_interstitial_stops(self):
        self.assertEqual(detect("<title>Just a moment...</title><div id=cf-chl-widget>"), "cloudflare-challenge")

    def test_403_alone_stops(self):
        self.assertEqual(detect("<html></html>", 403), "http-403")

    def test_429_alone_stops(self):
        self.assertEqual(detect("", 429), "http-429")

    def test_captcha_page_stops(self):
        self.assertIsNotNone(detect("Please complete the CAPTCHA to continue"))

    def test_paywall_loading_shell_is_not_suspicion(self):
        # PsycNet without entitlement, 2026-09-23: 200 + ~8 KB "Loading..." shell.
        # That is "no access" (exit 4), not the site suspecting a bot.
        self.assertIsNone(detect("<html><body><div>Loading...</div></body></html>", 200))

    def test_ordinary_article_page_is_not_suspicion(self):
        self.assertIsNone(detect("The Separation of Between-person and Within-person Components "
                                 "of Individual Change Over Time\nAbstract\nLongitudinal data...", 200))


if __name__ == "__main__":
    unittest.main(verbosity=2)
