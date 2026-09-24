#!/bin/bash
# Fetch one work's full-text PDF through the user's own Safari session.
#
# The PDF is fetched from INSIDE the article page (same origin, the page's
# cookies), not by navigating to the PDF URL: Safari's PDF viewer is not a page
# JavaScript can read, and headless fetches were refused (403 / JS challenge) on
# sites the user's session could read (observed 2026-09-23).
#
# Usage:
#   fetch-fulltext.sh --window N --expect-profile NAME --landing URL --out FILE.pdf
#                     [--title "record title" --pages 71--98 --doi 10.x/y]
#                     [--prime URL] [--bin /path/to/safari-browser]
#
#   --window          Safari window (1-based).
#   --expect-profile  The Safari profile that window must belong to (the user's
#                     OWN profile). Refuses to touch the window otherwise — other
#                     profiles are other people's sessions. Without it the script
#                     only prints the profile, and the check is the caller's.
#   --prime           Open this URL in its own tab first, like a reader clicking
#                     the PDF link, then close it — for PMC, whose in-page fetch
#                     otherwise met a challenge page (2026-09-23). If the primed
#                     tab shows ANY suspicion, the run stops there.
#   --out             Must not land in a git working tree unless that tree
#                     ignores it: full text is third-party copyrighted content.
#   --title/--pages/--doi  Run verify_pdf.py; a file that fails is kept as
#                     FILE.unverified.pdf, never under the requested name. The
#                     DOI defaults to the one in a https://doi.org/… --landing;
#                     it is one of the two identity signals verify_pdf needs.
#
# Exit codes:
#   0 stored and (if --title) verified    3 no PDF link found on the page
#   1 automation failure (see stderr)     4 no access (site served its login shell)
#   2 response was not a PDF (body saved  5 PDF did not verify as this work
#     as FILE.response.txt to look at)
#   6 STOP THE WHOLE RUN (SKILL.md「中止條款」): the site showed a sign of
#     suspecting automation — a challenge/block page, HTTP 403/429, the tab
#     moving to another site, a stalled or empty response, or a page that could
#     not be read to check. "Could not check" is treated as suspicion, not as
#     clean. The tab is left open for the user to look at.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=safari-browser WINDOW="" LANDING="" OUT="" TITLE="" PAGES="" PRIME="" EXPECT_PROFILE="" DOI=""
OWN_TAB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window) WINDOW=$2; shift 2 ;;   --landing) LANDING=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;         --title) TITLE=$2; shift 2 ;;
    --pages) PAGES=$2; shift 2 ;;     --prime) PRIME=$2; shift 2 ;;
    --bin) BIN=$2; shift 2 ;;         --expect-profile) EXPECT_PROFILE=$2; shift 2 ;;
    --doi) DOI=$2; shift 2 ;;
    *) echo "✗ unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$WINDOW" ] && [ -n "$LANDING" ] && [ -n "$OUT" ] || { echo "✗ --window, --landing and --out are required" >&2; exit 1; }
[[ "$WINDOW" =~ ^[0-9]+$ ]] || { echo "✗ --window must be a number" >&2; exit 1; }
command -v "$BIN" >/dev/null 2>&1 || [ -x "$BIN" ] || { echo "✗ safari-browser not found: $BIN" >&2; exit 1; }
if [ -z "$DOI" ]; then
  case "$LANDING" in https://doi.org/*|http://doi.org/*|https://dx.doi.org/*)
    DOI=${LANDING#*doi.org/}; DOI=${DOI%%[?#]*} ;;   # a query or fragment is not part of the DOI
  esac
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Waits go through nap so the path tests (tests/fetch-fulltext-paths.sh, which
# drive this script against a stub browser) can set FETCH_FULLTEXT_NAP=0.
# Unset in real runs: every wait is the literal number below.
nap() { sleep "${FETCH_FULLTEXT_NAP:-$1}"; }

# --- where the file lands: checked BEFORE touching the browser ----------------
out_dir=$(dirname "$OUT")
[ -d "$out_dir" ] || { echo "✗ --out directory does not exist: $out_dir" >&2; exit 1; }
OUT="$(cd "$out_dir" && pwd -P)/$(basename "$OUT")"; out_dir=$(dirname "$OUT")
UNVERIFIED="${OUT%.pdf}.unverified.pdf"; RESPONSE="${OUT%.pdf}.response.txt"
if git -C "$out_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for f in "$OUT" "$UNVERIFIED" "$RESPONSE"; do
    git -C "$out_dir" check-ignore -q -- "$f" || {
      echo "✗ refusing: $f would land in the git working tree $(git -C "$out_dir" rev-parse --show-toplevel), which does not ignore it." >&2
      echo "  Full text is third-party content. Write to a scratch directory outside git, then store it with akashic store-source." >&2
      exit 1; }
  done
fi

# --- Safari helpers: JSON over `documents --json`, never the human table ------
docs() { "$BIN" documents --json 2>/dev/null; }
tab_field() {  # $1 tab_in_window, $2 field → that field of tab $1 in window $WINDOW
  docs | python3 -c "import json,sys
d=[x for x in json.load(sys.stdin) if x['window']==$WINDOW and x['tab_in_window']==$1]
print((d[0].get('$2') or '') if d else '')"
}
tab_url() { tab_field "$1" url; }
tab_title() { tab_field "$1" title; }
current_tab() {
  docs | python3 -c "import json,sys
d=[x for x in json.load(sys.stdin) if x['window']==$WINDOW and x['is_current']]
print(d[0]['tab_in_window'] if d else '')"
}
origin() { python3 -c 'import sys,urllib.parse as u;p=u.urlsplit(sys.argv[1]);print(f"{p.scheme}://{p.netloc}")' "$1"; }

# An ordinary automation failure. It says where our tab is, because the human
# should look before retrying: if the page reads like suspicion, that is exit 6
# territory even though the script could not tell.
fail() {
  echo "✗ $1" >&2
  [ -n "$OWN_TAB" ] && echo "  our tab (window $WINDOW, tab $OWN_TAB) is left open — look at it before retrying." >&2
  exit 1
}

# The stop clause. No retry, no fallback source, the tab stays open as evidence.
bot_stop() {  # $1 signal, $2 site
  echo "✋ SITE SUSPECTS AUTOMATION ($1) on ${2:-?} — STOP THE WHOLE RUN." >&2
  echo "  our tab was window $WINDOW, tab ${OWN_TAB:-?}; it is left open for you to look at" >&2
  echo "  (if tabs were closed meanwhile, its position may have shifted)." >&2
  exit 6
}

PROFILE=$(docs | python3 -c "import json,sys
d={x.get('profile') for x in json.load(sys.stdin) if x['window']==$WINDOW}
print(','.join(sorted(p for p in d if p)) if d else '')")
[ -n "$PROFILE" ] || { echo "✗ Safari window $WINDOW not found" >&2; exit 1; }
echo "window $WINDOW profile: $PROFILE"
if [ -n "$EXPECT_PROFILE" ] && [ "$PROFILE" != "$EXPECT_PROFILE" ]; then
  echo "✗ window $WINDOW belongs to profile '$PROFILE', not '$EXPECT_PROFILE' — refusing to touch it" >&2; exit 1
fi

# Open a tab, remember WHICH tab by position, and close only that tab later.
# Position, not URL: when the user already has the same page open, a URL lock
# matches two tabs and safari-browser fail-closes (observed 2026-09-23).
open_own_tab() {
  "$BIN" open --new-tab --window "$WINDOW" "$1" >/dev/null 2>"$T/e" || fail "open: $(cat "$T/e")"
  OWN_TAB=$(current_tab)
  [ -n "$OWN_TAB" ] || fail "cannot identify the tab just opened"
}
close_own_tab() {  # only if tab $OWN_TAB still shows the origin we opened
  local u; u=$(tab_url "$OWN_TAB")
  if [ -n "$u" ] && [ "$(origin "$u")" = "$1" ]; then
    "$BIN" close --window "$WINDOW" --tab-in-window "$OWN_TAB" >/dev/null 2>&1 && echo "tab closed" && OWN_TAB=""
  else
    echo "⚠ tab $OWN_TAB no longer shows $1 — left open, not closed (tabs may have moved)" >&2
  fi
}

# Title + first 3000 characters of our tab. Two attempts; failure is reported,
# never read as "the page is clean".
page_text() {
  local i
  for i in 1 2; do
    "$BIN" js --window "$WINDOW" --tab-in-window "$OWN_TAB" \
      "return document.title + '\\n' + (document.body ? document.body.innerText.slice(0, 3000) : '')" 2>/dev/null && return 0
    nap 2
  done
  return 1
}
bot_check_page() {  # $1 site label; $2 = pdf-ok when Safari's PDF viewer is expected (prime)
  local text title hit
  title=$(tab_title "$OWN_TAB")
  if text=$(page_text); then
    hit=$(printf '%s\n%s' "$title" "$text" | python3 "$HERE/bot_signals.py") && bot_stop "$hit" "$1"
    return 0
  fi
  hit=$(printf '%s' "$title" | python3 "$HERE/bot_signals.py") && bot_stop "$hit" "$1"
  # Safari's PDF viewer is not scriptable, so on the primed PDF the tab title
  # (read without JS) is the whole check. Anywhere else, "could not read the
  # page" means "could not check", and that is not "clean".
  [ "${2:-}" = pdf-ok ] && return 0
  bot_stop "page-unreadable: could not check it for suspicion" "$1"
}

if [ -n "$PRIME" ]; then
  open_own_tab "$PRIME"; nap 12
  PRIME_ORIGIN=$(origin "$PRIME"); u=$(tab_url "$OWN_TAB")
  [ -n "$u" ] && [ "$(origin "$u")" = "$PRIME_ORIGIN" ] || bot_stop "primed tab left the site → ${u:-<gone>}" "$PRIME_ORIGIN"
  bot_check_page "$PRIME_ORIGIN" pdf-ok
  close_own_tab "$PRIME_ORIGIN"
fi

open_own_tab "$LANDING"
LOCK=(--window "$WINDOW" --tab-in-window "$OWN_TAB")

# Settle: past doi.org, and the DOM past "loading". An interstitial can report
# readyState=complete before the article page replaces it, so the real gate is
# the next step (a PDF link appearing), not this one. A page that does not
# settle in 60 s counts as a stalled response — the stop clause, not a retry.
FINAL=""
for _ in $(seq 1 30); do
  nap 2
  u=$(tab_url "$OWN_TAB")
  case "$u" in ""|*://doi.org/*|*://dx.doi.org/*) continue ;; esac
  rs=$("$BIN" js "${LOCK[@]}" "return document.readyState" 2>/dev/null)
  if [ "$rs" = complete ] || [ "$rs" = interactive ]; then FINAL=$u; break; fi
done
[ -n "$FINAL" ] || bot_stop "page did not settle in 60 s (stalled) → $(tab_url "$OWN_TAB")" "$(origin "$LANDING")"
ORIGIN=$(origin "$FINAL"); echo "page: $FINAL"
bot_check_page "$ORIGIN"

# Before every further action: our tab must still show the article's site. A tab
# that moved to another site mid-run (a verification subdomain, a login/SSO
# page) is the stop clause, not an automation glitch.
guard() {
  local u hit; u=$(tab_url "$OWN_TAB")
  [ -n "$u" ] && [ "$(origin "$u")" = "$ORIGIN" ] && return 0
  hit=$(printf '%s\n%s' "$(tab_title "$OWN_TAB")" "$u" | python3 "$HERE/bot_signals.py")
  bot_stop "${hit:-site changed} → ${u:-<our tab is gone>}" "$ORIGIN"
}

cat > "$T/haslink.js" <<'JS'
!!(document.querySelector('meta[name=citation_pdf_url]')
  || document.querySelector('a[href*="/doi/pdf/"],a[href*="pdfdirect"],a[href$=".pdf"],a[href*=".pdf?"],a[href^="/record/"]')
  || document.querySelector('form.ft-download-content__form--pdf'))
JS
guard; "$BIN" wait "${LOCK[@]}" --js "$(cat "$T/haslink.js")" --timeout 45000 >/dev/null 2>&1
guard; bot_check_page "$ORIGIN"   # an interstitial can turn into a challenge while we wait

cat > "$T/link.js" <<'JS'
const f = document.querySelector('form.ft-download-content__form--pdf');
if (f) return 'POST ' + f.action;
const m = document.querySelector('meta[name=citation_pdf_url]');
if (m && m.content) return 'GET ' + m.content;
for (const s of ['a[href*="/doi/pdf/"]','a[href*="pdfdirect"]','a[href$=".pdf"]','a[href*=".pdf?"]','a[href^="/record/"]']) {
  const a = document.querySelector(s); if (a) return 'GET ' + a.href;
}
return '';
JS
guard; LINK=$("$BIN" js "${LOCK[@]}" --file "$T/link.js" 2>"$T/e") || fail "could not read the page's links: $(cat "$T/e")"
METHOD=${LINK%% *}; PAGE_LINK=${LINK#* }
RULE=$(python3 "$HERE/pdf_url_rules.py" "$FINAL" "$PAGE_LINK")
if [ -n "$RULE" ]; then PDFURL=$RULE METHOD=GET
elif [ -n "$LINK" ] && [[ "$PAGE_LINK" != */record/* ]]; then PDFURL=$PAGE_LINK
else echo "no PDF link on $FINAL" >&2; close_own_tab "$ORIGIN"; exit 3; fi
echo "pdf:  $METHOD $PDFURL"

python3 - "$T/fetch.js" "$PDFURL" "$METHOD" <<'PY'
import json, sys
path, url, method = sys.argv[1:]
body = "new FormData(document.querySelector('form.ft-download-content__form--pdf'))" if method == "POST" else "undefined"
open(path, "w").write(f"""
window.__aff = {{done:false}};
fetch({json.dumps(url)}, {{method:{json.dumps(method)}, credentials:'include', body:{body}}})
 .then(r => {{ window.__aff.status = r.status; window.__aff.ctype = r.headers.get('content-type'); return r.arrayBuffer(); }})
 .then(b => {{ const u = new Uint8Array(b); let s = '';
   for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
   window.__aff.b64 = btoa(s); window.__aff.len = u.length; window.__aff.done = true; }})
 .catch(e => {{ window.__aff.err = String(e); window.__aff.done = true; }});
return 'started';
""")
PY
guard; "$BIN" js "${LOCK[@]}" --file "$T/fetch.js" >/dev/null 2>"$T/e" || fail "fetch start: $(cat "$T/e")"
"$BIN" wait "${LOCK[@]}" --js "window.__aff && window.__aff.done" --timeout 120000 >/dev/null 2>&1 \
  || { guard; bot_stop "fetch stalled: no answer in 120 s" "$ORIGIN"; }
guard; META=$("$BIN" js "${LOCK[@]}" "return JSON.stringify({s:window.__aff.status,c:window.__aff.ctype,l:window.__aff.len,e:window.__aff.err||null})" 2>/dev/null)
echo "response: ${META:-<unreadable>}"
read -r STATUS LEN FERR < <(printf '%s' "$META" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin); print(d.get("s") or 0, d.get("l") or 0, "1" if d.get("e") else "0")
except Exception:
    print("x x x")')
[ "$STATUS" = x ] && bot_stop "response unreadable: could not check it" "$ORIGIN"
# A fetch that throws is usually the request being redirected off-site or
# refused — the same family as a challenge. An empty body is a stalled response.
[ "$FERR" = 1 ] && bot_stop "fetch error: $META" "$ORIGIN"
[ "$LEN" = 0 ] && bot_stop "empty response" "$ORIGIN"
guard; "$BIN" js "${LOCK[@]}" --large --output "$T/b64" "window.__aff.b64||''" >/dev/null 2>"$T/e" || fail "read: $(cat "$T/e")"
base64 -D -i "$T/b64" -o "$T/out.pdf" 2>"$T/e" || fail "base64 decode failed: $(cat "$T/e")"
"$BIN" js "${LOCK[@]}" "delete window.__aff; return 'ok'" >/dev/null 2>&1

if [ "$(head -c 5 "$T/out.pdf")" != "%PDF-" ]; then
  # Suspicion first: a challenge page is also "not a PDF", and must not be
  # reported as a mere failure the caller might retry.
  hit=$(python3 "$HERE/bot_signals.py" --status "$STATUS" < "$T/out.pdf") && bot_stop "$hit (fetch response)" "$ORIGIN"
  size=$(wc -c < "$T/out.pdf" | tr -d ' ')
  cp "$T/out.pdf" "$RESPONSE"
  close_own_tab "$ORIGIN"
  # PsycNet without entitlement answered 200 with an ~8 KB app shell reading
  # "Loading..." for every article (observed 2026-09-23): "no access", stop the site.
  if [ "$size" -lt 20000 ] && grep -qi 'loading' "$T/out.pdf"; then echo "no access: $size-byte shell from $ORIGIN (saved as $RESPONSE)" >&2; exit 4; fi
  echo "not a PDF ($size bytes, HTTP $STATUS; saved as $RESPONSE): $(head -c 80 "$T/out.pdf" | tr -cd '[:print:]')" >&2; exit 2
fi

close_own_tab "$ORIGIN"
if [ -n "$TITLE" ]; then
  args=("$T/out.pdf" --title "$TITLE"); [ -n "$PAGES" ] && args+=(--pages "$PAGES"); [ -n "$DOI" ] && args+=(--doi "$DOI")
  VERDICT=$(python3 "$HERE/verify_pdf.py" "${args[@]}"); vrc=$?
  echo "verify: $VERDICT"
  if [ $vrc -ne 0 ]; then mv "$T/out.pdf" "$UNVERIFIED"; echo "kept as $UNVERIFIED" >&2; exit 5; fi
fi
mv "$T/out.pdf" "$OUT"
echo "OK $(wc -c < "$OUT" | tr -d ' ') bytes -> $OUT"
