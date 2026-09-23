#!/bin/bash
# Fetch one work's full-text PDF through the user's own Safari session.
#
# The PDF is fetched from INSIDE the article page (same origin, the page's
# cookies), not by navigating to the PDF URL: Safari's PDF viewer is not a page
# JavaScript can read, and headless fetches were refused (403 / JS challenge) on
# sites the user's session could read (observed 2026-09-23).
#
# Usage:
#   fetch-fulltext.sh --window N --landing URL --out FILE.pdf
#                     [--title "record title" --pages 71--98]
#                     [--prime URL] [--bin /path/to/safari-browser]
#
#   --window   Safari window (1-based) that belongs to the user's OWN profile.
#              The script prints that window's profile; choosing it is the
#              caller's job (other profiles are other people's sessions).
#   --prime    Open this URL in its own tab first and close it — for sites whose
#              PDF sits behind a challenge a real navigation solves (PMC).
#   --title/--pages  Run verify_pdf.py; a file that fails is kept as
#              FILE.unverified.pdf, never under the requested name.
#
# Exit codes:
#   0 stored and (if --title) verified    3 no PDF link found on the page
#   1 automation failure (see stderr)     4 no access (site served its login shell)
#   2 response was not a PDF              5 PDF did not verify as this work
#   6 THE SITE SUSPECTS AUTOMATION — stop the whole run, not just this work.
#     The tab is left open for the user to look at (SKILL.md「中止條款」).
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=safari-browser WINDOW="" LANDING="" OUT="" TITLE="" PAGES="" PRIME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window) WINDOW=$2; shift 2 ;;   --landing) LANDING=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;         --title) TITLE=$2; shift 2 ;;
    --pages) PAGES=$2; shift 2 ;;     --prime) PRIME=$2; shift 2 ;;
    --bin) BIN=$2; shift 2 ;;         *) echo "✗ unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$WINDOW" ] && [ -n "$LANDING" ] && [ -n "$OUT" ] || { echo "✗ --window, --landing and --out are required" >&2; exit 1; }
command -v "$BIN" >/dev/null 2>&1 || [ -x "$BIN" ] || { echo "✗ safari-browser not found: $BIN" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# JSON helpers over `documents --json` — never parse the human table.
docs() { "$BIN" documents --json 2>/dev/null; }
current_tab() {  # prints "<tab_in_window>\t<url>" of window $WINDOW's current tab
  docs | python3 -c "import json,sys
d=[x for x in json.load(sys.stdin) if x['window']==$WINDOW and x['is_current']]
print(f\"{d[0]['tab_in_window']}\t{d[0]['url']}\" if d else '')"
}
tab_url() {      # URL of tab $1 in window $WINDOW
  docs | python3 -c "import json,sys
d=[x for x in json.load(sys.stdin) if x['window']==$WINDOW and x['tab_in_window']==$1]
print(d[0]['url'] if d else '')"
}
origin() { python3 -c 'import sys,urllib.parse as u;p=u.urlsplit(sys.argv[1]);print(f"{p.scheme}://{p.netloc}")' "$1"; }

PROFILE=$(docs | python3 -c "import json,sys
d={x.get('profile') for x in json.load(sys.stdin) if x['window']==$WINDOW}
print(','.join(sorted(p for p in d if p)) if d else '')")
[ -n "$PROFILE" ] || { echo "✗ Safari window $WINDOW not found" >&2; exit 1; }
echo "window $WINDOW profile: $PROFILE"

# Open a tab, remember WHICH tab by position, and close only that tab later.
# Position, not URL: when the user already has the same page open, a URL lock
# matches two tabs and safari-browser fail-closes (observed 2026-09-23).
open_own_tab() {
  "$BIN" open --new-tab --window "$WINDOW" "$1" >/dev/null 2>"$T/e" || { echo "✗ open: $(cat "$T/e")" >&2; return 1; }
  local cur; cur=$(current_tab); OWN_TAB=${cur%%$'\t'*}
  [ -n "$OWN_TAB" ] || { echo "✗ cannot identify the tab just opened" >&2; return 1; }
}
close_own_tab() {  # only if tab $OWN_TAB still shows the origin we opened
  local u; u=$(tab_url "$OWN_TAB")
  if [ -n "$u" ] && [ "$(origin "$u")" = "$1" ]; then
    "$BIN" close --window "$WINDOW" --tab-in-window "$OWN_TAB" >/dev/null 2>&1 && echo "tab closed"
  else
    echo "⚠ tab $OWN_TAB no longer shows $1 — left open, not closed (tabs may have moved)" >&2
  fi
}

# Stop clause. Any sign the site suspects automation ends the run with exit 6
# and leaves the tab open — no retry, no fallback source, no closing the
# evidence. bot_signals.py holds the patterns and their provenance.
bot_stop() {
  echo "✋ SITE SUSPECTS AUTOMATION ($1) on ${2:-?} — STOP THE WHOLE RUN." >&2
  echo "   tab $OWN_TAB in window $WINDOW left open for you to look at." >&2
  exit 6
}
bot_check_page() {  # $1 = origin label
  local t hit
  t=$("$BIN" js --window "$WINDOW" --tab-in-window "$OWN_TAB" \
      "return document.title + '\\n' + (document.body ? document.body.innerText.slice(0, 3000) : '')" 2>/dev/null)
  hit=$(printf '%s' "$t" | python3 "$HERE/bot_signals.py") && bot_stop "$hit" "$1"
  return 0
}

if [ -n "$PRIME" ]; then
  open_own_tab "$PRIME" || exit 1; sleep 12
  bot_check_page "$(origin "$PRIME")"
  close_own_tab "$(origin "$PRIME")"
fi

open_own_tab "$LANDING" || exit 1
LOCK=(--window "$WINDOW" --tab-in-window "$OWN_TAB")

# Settle: past doi.org, and the DOM past "loading". An interstitial can report
# readyState=complete before the article page replaces it, so the real gate is
# the next step (a PDF link appearing), not this one.
FINAL=""
for _ in $(seq 1 30); do
  sleep 2
  u=$(tab_url "$OWN_TAB")
  case "$u" in ""|*://doi.org/*|*://dx.doi.org/*) continue ;; esac
  rs=$("$BIN" js "${LOCK[@]}" "return document.readyState" 2>/dev/null)
  [ "$rs" = complete ] || [ "$rs" = interactive ] && { FINAL=$u; break; }
done
[ -n "$FINAL" ] || { echo "✗ page did not settle (tab $OWN_TAB: $(tab_url "$OWN_TAB"))" >&2; exit 1; }
ORIGIN=$(origin "$FINAL"); echo "page: $FINAL"
bot_check_page "$ORIGIN"

guard() {  # refuse to act if the tab no longer shows this site
  [ "$(origin "$(tab_url "$OWN_TAB")")" = "$ORIGIN" ] || { echo "✗ tab $OWN_TAB changed site — stopping" >&2; exit 1; }
}

cat > "$T/haslink.js" <<'JS'
return !!(document.querySelector('meta[name=citation_pdf_url]')
  || document.querySelector('a[href*="/doi/pdf/"],a[href*="pdfdirect"],a[href$=".pdf"],a[href*=".pdf?"],a[href^="/record/"]')
  || document.querySelector('form.ft-download-content__form--pdf'))
JS
guard; "$BIN" wait "${LOCK[@]}" --js "$(cat "$T/haslink.js" | sed 's/^return //')" --timeout 45000 >/dev/null 2>&1
bot_check_page "$ORIGIN"   # an interstitial can turn into a challenge while we wait

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
guard; LINK=$("$BIN" js "${LOCK[@]}" --file "$T/link.js" 2>/dev/null)
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
guard; "$BIN" js "${LOCK[@]}" --file "$T/fetch.js" >/dev/null 2>"$T/e" || { echo "✗ fetch start: $(cat "$T/e")" >&2; exit 1; }
"$BIN" wait "${LOCK[@]}" --js "window.__aff && window.__aff.done" --timeout 120000 >/dev/null 2>&1 || { echo "✗ fetch did not finish" >&2; exit 1; }
META=$("$BIN" js "${LOCK[@]}" "return JSON.stringify({s:window.__aff.status,c:window.__aff.ctype,l:window.__aff.len,e:window.__aff.err||null})" 2>/dev/null)
echo "response: $META"
STATUS=$(printf '%s' "$META" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("s") or "")
except Exception: print("")')
guard; "$BIN" js "${LOCK[@]}" --large --output "$T/b64" "window.__aff.b64||''" >/dev/null 2>"$T/e" || { echo "✗ read: $(cat "$T/e")" >&2; exit 1; }
base64 -D -i "$T/b64" -o "$T/out.pdf" 2>/dev/null || base64 -d "$T/b64" > "$T/out.pdf" 2>/dev/null
"$BIN" js "${LOCK[@]}" "delete window.__aff; return 'ok'" >/dev/null 2>&1

if [ "$(head -c 5 "$T/out.pdf")" != "%PDF-" ]; then
  # Suspicion first: a challenge page is also "not a PDF", and must not be
  # reported as a mere failure the caller might retry.
  hit=$(python3 "$HERE/bot_signals.py" ${STATUS:+--status "$STATUS"} < "$T/out.pdf") && bot_stop "$hit (fetch response)" "$ORIGIN"
  # PsycNet without entitlement answered 200 with an ~8 KB app shell reading
  # "Loading..." for every article (observed 2026-09-23). Treat a small HTML
  # shell as "no access" so the caller stops instead of retrying.
  size=$(wc -c < "$T/out.pdf" | tr -d ' ')
  close_own_tab "$ORIGIN"
  if [ "$size" -lt 20000 ] && grep -qi 'loading' "$T/out.pdf"; then echo "no access: $size-byte shell from $ORIGIN" >&2; exit 4; fi
  echo "not a PDF ($size bytes): $(head -c 80 "$T/out.pdf" | tr -cd '[:print:]')" >&2; exit 2
fi

close_own_tab "$ORIGIN"
if [ -n "$TITLE" ]; then
  args=("$T/out.pdf" --title "$TITLE"); [ -n "$PAGES" ] && args+=(--pages "$PAGES")
  VERDICT=$(python3 "$HERE/verify_pdf.py" "${args[@]}"); vrc=$?
  echo "verify: $VERDICT"
  if [ $vrc -ne 0 ]; then mv "$T/out.pdf" "${OUT%.pdf}.unverified.pdf"; echo "kept as ${OUT%.pdf}.unverified.pdf" >&2; exit 5; fi
fi
mv "$T/out.pdf" "$OUT"
echo "OK $(wc -c < "$OUT" | tr -d ' ') bytes -> $OUT"
