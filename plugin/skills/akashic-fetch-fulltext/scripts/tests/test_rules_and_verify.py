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
from pdf_url_rules import doi_from_path, pdf_url  # noqa: E402
from verify_pdf import assess, doi_from_xmp, expected_page_count, norm_doi, title_match, title_score  # noqa: E402
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

    def test_view_suffix_after_doi_is_peeled_off(self):
        self.assertEqual(doi_from_path("/doi/10.1111/jopy.12964/abstract"), "10.1111/jopy.12964")
        self.assertEqual(doi_from_path("/doi/full/10.1111/jopy.12964/"), "10.1111/jopy.12964")
        self.assertEqual(
            pdf_url("https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964/references"),
            "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1111/jopy.12964")

    def test_sici_doi_slashes_survive_suffix_peeling(self):
        doi = "10.1002/(SICI)1099-0984(199909/10)13:5%3C389::AID-PER361%3E3.0.CO;2-A"
        self.assertEqual(doi_from_path(f"/doi/abs/{doi}/full"), doi)

    def test_unknown_publisher_defers_to_page_link(self):
        self.assertIsNone(pdf_url("https://www.tandfonline.com/doi/full/10.1080/10705511.2024.2379495"))


class VerifyPdf(unittest.TestCase):
    TITLE = "A Theory of States and Traits—Revised"
    DOI = "10.1146/annurev-clinpsy-032813-153719"
    OWN = {"doi": DOI, "meta_doi": DOI}   # the file's metadata names this work

    def test_page_range_arithmetic(self):
        self.assertEqual(expected_page_count("71--98"), 28)
        self.assertEqual(expected_page_count("1013–1034"), 22)
        self.assertIsNone(expected_page_count("e81105"))
        self.assertIsNone(expected_page_count(None))

    def test_version_of_record_passes(self):
        r = assess("Downloaded from ... CP11CH04-Steyer\nA Theory of States and Traits—Revised",
                   28, self.TITLE, "71--98", **self.OWN)
        self.assertEqual(r["doi_state"], "metadata-match")
        self.assertTrue(r["is_article"])
        self.assertTrue(r["version_of_record"])

    def test_supplement_is_not_the_article(self):
        r = assess("Supplemental Material: Annu. Rev. Clin. Psychol. 2015. 11:71–98\n"
                   "A Theory of States and Traits—Revised\nA SUPPLEMENTAL TEXT TO CTT",
                   10, self.TITLE, "71--98")
        self.assertFalse(r["is_article"])
        self.assertIn("supplement", r["flags"])

    MS_TITLE = "A General Panel Model with Random and Fixed Effects: A Structural Equations Approach"
    MS_PAGE = ("NIH Public Access\nAuthor Manuscript\nSoc Forces. doi:10.1353/sof.2010.0072.\n"
               "A General Panel Model with Random and Fixed Effects: A Structural Equations Approach")

    def test_author_manuscript_is_the_work_but_not_version_of_record(self):
        # With the file's own metadata DOI it is accepted — as the work, not the VoR.
        r = assess(self.MS_PAGE, 36, self.MS_TITLE, "1--34", "10.1353/sof.2010.0072", "10.1353/sof.2010.0072")
        self.assertTrue(r["is_article"])
        self.assertFalse(r["version_of_record"])

    def test_author_manuscript_with_only_a_printed_doi_gets_a_human_look(self):
        # PMC manuscripts carry no metadata DOI (measured 2026-09-24) and their page
        # count is not compared, so the printed DOI stands alone: not automatic.
        r = assess(self.MS_PAGE, 36, self.MS_TITLE, "1--34", "10.1353/sof.2010.0072")
        self.assertEqual(r["doi_state"], "page-match")
        self.assertFalse(r["is_article"])

    def test_title_line_alone_is_not_enough(self):
        # No DOI to compare and no page range: one signal, so a human looks.
        self.assertFalse(assess(self.MS_PAGE, 36, self.MS_TITLE, None, None)["is_article"])

    WRONG_TITLE = "The rank-order consistency of personality traits from childhood to old age"

    def test_same_topic_wrong_paper_at_the_measured_boundary(self):
        # Measured 2026-09-24 on real pdftotext output: this pairing scored 0.8,
        # because the other paper's abstract uses most of the wrong title's words.
        # Synthetic text (our wording) reproducing that: 8 of the 10 content words.
        first_page = ("Personality Development Across the Life Course\n"
                      "We review the rank-order consistency of personality traits from childhood onward.")
        self.assertAlmostEqual(title_score(self.WRONG_TITLE, first_page), 0.8)
        self.assertFalse(assess(first_page, 19, self.WRONG_TITLE, None)["is_article"])

    def test_unrelated_title_scores_far_below(self):
        first_page = "Personality Development Across the Life Course: The Argument for Change and Continuity"
        self.assertLess(title_score(self.WRONG_TITLE, first_page), 0.5)

    CJK_TITLE = "大學生自我認定的發展軌跡"

    def test_cjk_title_survives_a_line_wrap(self):
        page = "大學生自我認定\n的發展軌跡\n摘要\nDOI: 10.6251/BEP.2020.0001"
        self.assertTrue(title_match(self.CJK_TITLE, page))
        self.assertTrue(assess(page, 20, self.CJK_TITLE, None, "10.6251/bep.2020.0001", "10.6251/BEP.2020.0001")["is_article"])

    def test_cjk_same_topic_paper_differing_at_the_end_is_rejected(self):
        # Review 2026-09-24: bigram overlap scored this 0.91 and accepted it.
        wrong = "自我概念與生涯輔導：大學生自我認定的發展軌道分析\n摘要\n本研究分析大學生自我概念形成歷程。"
        self.assertFalse(title_match(self.CJK_TITLE, wrong))
        self.assertFalse(assess(wrong, 19, self.CJK_TITLE, None)["is_article"])

    def test_mixed_script_title_needs_both_parts_in_order(self):
        title = "RI-CLPM 在大學生自我認定研究中的應用"
        self.assertTrue(title_match(title, "RI-CLPM 在大學生自我\n認定研究中的應用\nAbstract"))
        self.assertFalse(title_match(title, "RI-CLPM 在青少年情緒研究中的應用\n大學生自我認定"))

    def test_title_nested_in_a_longer_cjk_title_is_rejected(self):
        # Review R3, 2026-09-24: plain containment accepted both of these.
        title = "大學生自我認定的發展"
        self.assertIsNone(title_match(title, "台灣大學生自我認定的發展與相關因素之研究\n王小明\n摘要"))
        self.assertIsNone(title_match(title, "對「大學生自我認定的發展」一文之商榷\n李四\n摘要"))

    def test_latin_title_extended_without_a_separator_is_rejected(self):
        page = "A critique of the cross-lagged panel model in developmental research\nAuthor\nAbstract"
        self.assertIsNone(title_match("A critique of the cross-lagged panel model", page))

    def test_abstract_containing_every_title_word_is_not_the_title(self):
        # The measured failure of word overlap (14/808 wrong accepts): a same-field
        # paper's abstract uses every word of another paper's title.
        page = ("The within-between dispute in panel research\nJane Doe\nAbstract\n"
                "We revisit a critique of the cross-lagged panel model and its random intercept extension.")
        self.assertEqual(title_score("A critique of the cross-lagged panel model", page), 1.0)
        self.assertIsNone(title_match("A critique of the cross-lagged panel model", page))
        self.assertFalse(assess(page, 20, "A critique of the cross-lagged panel model", None)["is_article"])

    def test_record_with_main_title_only_matches_a_pdf_with_subtitle(self):
        # Subtitle on the SAME line: only the separator rule can match the main title.
        page = "Journal\nThe separation of between-person and within-person components: A latent curve model\nAbstract"
        self.assertEqual(title_match("The separation of between-person and within-person components", page), "main-title")
        # Subtitle on its own line: the main-title line alone already equals the record.
        wrapped = "Journal\nThe separation of between-person and within-person components:\nA latent curve model"
        self.assertEqual(title_match("The separation of between-person and within-person components", wrapped), "exact")
        self.assertEqual(title_match("The separation of between-person and within-person components: "
                                     "A latent curve model", page), "exact")

    def test_generic_title_needs_the_page_count(self):
        # Review R4: "Introduction" heads a section of any paper.
        page = "Some Other Paper\nJohn Smith\nAbstract\nText.\nIntroduction\nMore text."
        self.assertEqual(title_match("Introduction", page), "exact")
        # Without a DOI, a title line and a page count are never enough.
        self.assertFalse(assess(page, 12, "Introduction", "1--12")["is_article"])
        # This page prints another work's DOI first: rejected.
        other = page + "\ndoi:10.1037/other0001"
        self.assertFalse(assess(other, 12, "Introduction", "1--12", "10.1037/intro0001")["is_article"])

    CRITIQUE = "A critique of the cross-lagged panel model"
    CRITIQUE_DOI = "10.1037/a0038889"

    def test_reply_after_the_separator_is_a_different_work(self):
        page = "A critique of the cross-lagged panel model: A reply to Orth et al.\nJane Doe\nAbstract"
        self.assertEqual(title_match(self.CRITIQUE, page), "main-title-response")
        self.assertEqual(title_match("大學生自我認定的發展軌跡", "大學生自我認定的發展軌跡：回應王氏\n摘要"),
                         "main-title-response")
        # No DOI on the page: even a page count that happens to fit does not save it.
        self.assertFalse(assess(page, 16, self.CRITIQUE, "102--116")["is_article"])

    # Review R5, 2026-09-24: each of these is a different work that a title-line
    # rule accepts. Each prints its own DOI, which is what rejects it.
    def test_reply_marker_on_the_line_before_the_title_is_rejected_by_its_doi(self):
        page = "Erratum to:\nA critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0099999\nText"
        self.assertEqual(title_match(self.CRITIQUE, page), "exact")
        r = assess(page, 16, self.CRITIQUE, "102--116", self.CRITIQUE_DOI)
        self.assertEqual(r["doi_state"], "page-mismatch")
        self.assertFalse(r["is_article"])

    def test_reply_in_another_language_is_rejected_by_its_doi(self):
        page = "A critique of the cross-lagged panel model: Eine Erwiderung auf Müller\ndoi:10.1026/0012-1924/a000001"
        self.assertEqual(title_match(self.CRITIQUE, page), "main-title")
        self.assertFalse(assess(page, 16, self.CRITIQUE, "102--116", self.CRITIQUE_DOI)["is_article"])

    def test_sequel_with_a_number_is_rejected_by_its_doi(self):
        page = "A Theory of States and Traits Revised 2\nhttps://doi.org/10.1146/annurev-other-000000\nJane Doe"
        self.assertEqual(title_match("A Theory of States and Traits Revised", page), "exact")
        self.assertFalse(assess(page, 28, "A Theory of States and Traits Revised", None,
                                "10.1146/annurev-clinpsy-032813-153719")["is_article"])

    def test_ordinary_subtitle_word_like_correction_is_accepted_with_the_doi(self):
        page = "Range restriction revisited: Correction for attenuation in panel data\ndoi:10.1037/met0000123\nAbstract"
        r = assess(page, 20, "Range restriction revisited", None, "10.1037/met0000123", "10.1037/met0000123")
        self.assertEqual(r["doi_state"], "metadata-match")
        self.assertTrue(r["is_article"])
        # Without metadata the printed DOI could be a citation; the reply-word guard
        # then refuses — the documented cost (a human looks).
        self.assertFalse(assess(page, 20, "Range restriction revisited", "1--20", "10.1037/met0000123")["is_article"])

    def test_only_page_one_doi_counts(self):
        # A DOI in page 2's references is not the file's own; no DOI on page 1 = absent.
        page = "A critique of the cross-lagged panel model\nAbstract\n\fReferences\ndoi:10.1037/other"
        r = assess(page, 16, self.CRITIQUE, "102--116", self.CRITIQUE_DOI)
        self.assertEqual(r["doi_state"], "absent")
        self.assertFalse(r["is_article"])  # no DOI signal: a human looks

    # Review R6, 2026-09-24: page 1's first DOI can be a CITATION of the original.
    def test_erratum_citing_the_originals_doi_first_is_caught_by_pages(self):
        page = "Erratum to: A critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0038889\nIn the article..."
        r = assess(page, 1, self.CRITIQUE, "102--116", self.CRITIQUE_DOI)
        self.assertEqual(r["doi_state"], "page-match")
        self.assertFalse(r["is_article"])   # 1 page against 15

    def test_metadata_doi_overrides_what_the_page_prints(self):
        page = "A critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0038889\nText"
        # the file says it is another work (an erratum citing the original first)
        r = assess(page, 16, self.CRITIQUE, "102--116", self.CRITIQUE_DOI, "10.1037/met0099999")
        self.assertEqual(r["doi_state"], "metadata-mismatch")
        self.assertFalse(r["is_article"])
        # the file says it is this work, though page 1 first prints a cited DOI
        cited = "A critique of the cross-lagged panel model\nsee doi:10.1037/cited0001\nText"
        r = assess(cited, 16, self.CRITIQUE, None, self.CRITIQUE_DOI, self.CRITIQUE_DOI)
        self.assertEqual(r["doi_state"], "metadata-match")
        self.assertTrue(r["is_article"])

    def test_xmp_doi_stops_at_the_closing_tag(self):
        # The shape found in the corpus (T&F, SAGE): the tag follows the DOI directly.
        self.assertEqual(doi_from_xmp("<dc:identifier>doi:10.1080/10705511.2020.1784738</dc:identifier>"),
                         "10.1080/10705511.2020.1784738")
        self.assertEqual(doi_from_xmp("<prism:doi>10.1177/0265407517718387</prism:doi></rdf:Description>"),
                         "10.1177/0265407517718387")

    def test_xmp_sici_doi_is_unescaped(self):
        self.assertEqual(
            doi_from_xmp("<prism:doi>10.1002/(SICI)1099-0984(199909/10)13:5&lt;389::AID-PER361&gt;3.0.CO;2-A</prism:doi>"),
            "10.1002/(sici)1099-0984(199909/10)13:5<389::aid-per361>3.0.co;2-a")

    def test_doi_from_a_url_drops_query_and_fragment(self):
        self.assertEqual(norm_doi("https://doi.org/10.1111/jopy.12964?utm_source=x#abstract"), "10.1111/jopy.12964")

    def test_main_title_match_needs_the_page_count(self):
        title = "The separation of between-person and within-person components"
        page = "Journal\nThe separation of between-person and within-person components: A latent curve model\nAbstract"
        printed = page + "\ndoi:10.1037/a0035297"
        self.assertFalse(assess(printed, 16, title, None, "10.1037/a0035297")["is_article"])
        self.assertTrue(assess(printed, 16, title, "879--894", "10.1037/a0035297")["is_article"])

    def test_ampersand_and_and_are_the_same_title(self):
        page = "Structure & Dynamics of Self-Concept\nDevelopment\nAuthor"
        self.assertEqual(title_match("Structure and Dynamics of Self-Concept Development", page), "exact")
        self.assertEqual(title_match("Structure & Dynamics of Self-Concept Development",
                                     "Structure and Dynamics of\nSelf-Concept Development"), "exact")

    def test_title_wrapped_over_seven_lines_still_matches(self):
        title = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen"
        words = title.split()
        page = "\n".join(" ".join(words[i:i + 2]) for i in range(0, len(words), 2))
        self.assertEqual(title_match(title, page), "exact")

    def test_footnote_marker_after_the_title_is_tolerated(self):
        self.assertEqual(title_match("Residual Structural Equation Models", "Residual Structural Equation Models1\nX"), "exact")

    def test_title_of_short_words_uses_containment(self):
        # Every word ≤ 2 letters, so normalize() is empty and containment decides.
        self.assertTrue(title_match("Is It Ok", "is it ok\nabstract"))
        self.assertFalse(title_match("Is It Ok", "something else entirely"))

    def test_standalone_supporting_information_heading_inside_an_article_is_not_flagged(self):
        # ACS / Wiley articles carry their own "Supporting Information" heading in
        # the front matter; only the first 3 lines can mark a supplement file.
        page = "\n".join(["Journal of Things", "A Theory of States and Traits—Revised", "Jane Doe",
                          "Abstract", "We study states.", "Supporting Information", "Details online."])
        r = assess(page, 28, self.TITLE, "71--98")
        self.assertNotIn("supplement", r["flags"])

    def test_supporting_information_file_is_a_supplement(self):
        r = assess("Supporting Information\n" + self.TITLE, 6, self.TITLE, "71--98")
        self.assertIn("supplement", r["flags"])
        self.assertFalse(r["is_article"])

    def test_tandf_cover_page_link_is_not_a_supplement(self):
        # Measured 2026-09-24: a T&F article's cover page reads like this and the
        # match-anywhere rule flagged the article itself as a supplement.
        cover = ("Structural Equation Modeling: A Multidisciplinary Journal\n"
                 "A Theory of States and Traits—Revised\n"
                 "To link to this article: https://doi.org/10.1080/x\n"
                 "View supplementary material\nPublished online: 06 Oct 2025.")
        r = assess(cover, 30, self.TITLE, "71--98", **self.OWN)
        self.assertNotIn("supplement", r["flags"])
        self.assertTrue(r["is_article"])

    def test_article_mentioning_its_supplement_below_the_head_is_not_flagged(self):
        body = "\n".join(["A Theory of States and Traits—Revised"] + [f"line {i}" for i in range(20)]
                          + ["Supporting Information is available online."])
        r = assess(body, 28, self.TITLE, "71--98", **self.OWN)
        self.assertNotIn("supplement", r["flags"])
        self.assertTrue(r["is_article"])

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

    def test_vendor_block_pages_stop(self):
        self.assertEqual(detect("Pardon Our Interruption"), "akamai-block")
        self.assertEqual(detect("Press & Hold to confirm you are a human"), "perimeterx-block")
        self.assertEqual(detect("<script src=https://ct.captcha-delivery.com/c.js>"), "datadome-block")

    def test_ordinary_hci_wording_is_not_a_vendor_block(self):
        # Review 2026-09-24: these bare phrases stopped runs on normal abstracts.
        self.assertIsNone(detect("Participants were asked to press and hold the target icon for 500 ms."))
        self.assertIsNone(detect("Teams using automation tools shipped releases faster."))

    def test_paywall_loading_shell_is_not_suspicion(self):
        # PsycNet without entitlement, 2026-09-23: 200 + ~8 KB "Loading..." shell.
        # That is "no access" (exit 4), not the site suspecting a bot.
        self.assertIsNone(detect("<html><body><div>Loading...</div></body></html>", 200))

    def test_ordinary_article_page_is_not_suspicion(self):
        self.assertIsNone(detect("The Separation of Between-person and Within-person Components "
                                 "of Individual Change Over Time\nAbstract\nLongitudinal data...", 200))


if __name__ == "__main__":
    unittest.main(verbosity=2)
