#!/usr/bin/env python3
"""Has the site started to suspect automation? If so, the whole run stops.

This is the skill's stop clause (SKILL.md「中止條款」). The user's standard is
"any sign the site suspects an AI" — so this errs toward stopping: a false stop
costs one human glance, a missed signal teaches a publisher to block the user's
institutional session.

The patterns are a MINIMUM, not the definition. SKILL.md tells the agent to stop
on anything that reads as suspicion even when nothing here matches.

Usage:
    bot_signals.py [--status N] < text        prints the matched signal, exit 0
                                               no signal: prints nothing, exit 1
"""
import argparse
import re
import sys

# Each entry: (label, pattern). Observed ones carry a date; the rest are the
# standard wording of common challenge pages, kept because the stop direction
# is the cheap one to be wrong in.
SIGNALS = [
    ("cloudflare-challenge", re.compile(r"just a moment\.\.\.|cf-chl|challenge-platform|cf_chl_", re.I)),  # OUP, 2026-09-23
    ("captcha", re.compile(r"captcha|hcaptcha|recaptcha|turnstile", re.I)),
    ("human-check", re.compile(r"are you (a )?(robot|human)|verify (that )?you('| a)re (a )?human|prove you('| a)re human|i'?m not a robot", re.I)),
    ("unusual-traffic", re.compile(r"unusual (traffic|activity)|automated (access|requests|queries|traffic)|suspicious activity", re.I)),
    ("rate-limit", re.compile(r"too many requests|rate limit(ed)?\b", re.I)),
    ("access-denied", re.compile(r"\baccess denied\b|request (was )?blocked|you have been blocked", re.I)),
    ("pmc-pow-challenge", re.compile(r"preparing to download|proof[- ]of[- ]work|checking your browser", re.I)),  # PMC, 2026-09-23
]

# 403 / 429 are suspicion by themselves: a paywall answers 200 with a login
# page (PsycNet, 2026-09-23), not 403. 403 from OUP was the Cloudflare page.
SUSPICIOUS_STATUS = {403, 429}


def detect(text: str, status: int | None = None) -> str | None:
    if status in SUSPICIOUS_STATUS:
        return f"http-{status}"
    for label, rx in SIGNALS:
        if rx.search(text or ""):
            return label
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--status", type=int)
    args = ap.parse_args()
    hit = detect(sys.stdin.read(), args.status)
    if hit:
        print(hit)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
