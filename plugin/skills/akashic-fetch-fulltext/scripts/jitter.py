#!/usr/bin/env python3
"""Sleep for one delay drawn from a doubly truncated Cauchy (seconds on stdout).

Use only when the installed safari-browser lacks `wait --jitter cauchy`
(PsychQuant/safari-browser#182). Same distribution and defaults: [2, 60] s,
truncated median 3 s, scale 0.8 s. Out-of-range mass is discarded and the
density renormalized — never clamped. The older SKILL.md one-liner clamped with
max(2, ...), which put 22.3% of delays at exactly 2.0 s in a 10^6-draw
simulation (PsychQuant/safari-browser#182); do not use it.

    jitter.py [--min 2] [--max 60] [--median 3] [--scale 0.8] [--dry-run]
"""
import argparse, math, random, sys, time

def cdf(x, mu, s): return 0.5 + math.atan((x - mu) / s) / math.pi
def q(u, mu, s): return mu + s * math.tan(math.pi * (u - 0.5))
def tmed(mu, s, a, b): return q((cdf(a, mu, s) + cdf(b, mu, s)) / 2, mu, s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min", type=float, default=2.0); ap.add_argument("--max", type=float, default=60.0)
    ap.add_argument("--median", type=float, default=3.0); ap.add_argument("--scale", type=float, default=0.8)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not (0 <= a.min < a.median < a.max) or not (0 < a.scale <= 100 * (a.max - a.min)):
        sys.exit("✗ need 0 <= min < median < max and 0 < scale <= 100*(max-min)")
    lo, hi = tmed(a.min, a.scale, a.min, a.max), tmed(a.max, a.scale, a.min, a.max)
    if not lo <= a.median <= hi:
        sys.exit(f"✗ median {a.median} unreachable with scale {a.scale}; achievable {lo:.3f}..{hi:.3f}")
    l, h = a.min, a.max            # truncated median is monotone in mu on [min, max]
    for _ in range(200):
        m = (l + h) / 2
        l, h = (m, h) if tmed(m, a.scale, a.min, a.max) < a.median else (l, m)
    mu = (l + h) / 2
    fa, fb = cdf(a.min, mu, a.scale), cdf(a.max, mu, a.scale)
    for _ in range(64):
        x = q(fa + (fb - fa) * random.random(), mu, a.scale)
        if a.min < x < a.max: break
    else:
        x = a.median
    print(f"{x:.2f}")
    if not a.dry_run: time.sleep(x)

if __name__ == "__main__":
    main()
