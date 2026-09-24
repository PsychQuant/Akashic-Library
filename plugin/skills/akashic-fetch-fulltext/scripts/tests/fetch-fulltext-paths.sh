#!/bin/bash
# Path tests for fetch-fulltext.sh against a STUB browser — no Safari, no network.
#
# The script's exit codes are its contract with the agent: 6 means "stop the
# whole run" (the stop clause), 1 means "look, then maybe retry". A path that
# lands on the wrong code is the stop clause silently turned into a retry — the
# defect the 2026-09-24 review found in three places. Each scenario below pins
# one path to its code, and checks the side effects the contract promises:
# on 6 our tab is NOT closed and nothing is written under the requested name;
# on 0 only our own tab is closed and the user's tab is untouched.
#
#     bash plugin/skills/akashic-fetch-fulltext/scripts/tests/fetch-fulltext-paths.sh
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../fetch-fulltext.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export FETCH_FULLTEXT_NAP=0

# --- the stub: one Python file answering documents / open / close / js / wait --
cat > "$W/stub" <<'PY'
#!/usr/bin/env python3
import base64, json, os, sys
S = os.environ["STUB_DIR"]
scn = json.load(open(f"{S}/scn.json"))
st_path = f"{S}/state.json"
st = json.load(open(st_path)) if os.path.exists(st_path) else {
    "tabs": [{"url": "https://user.example/mine", "title": "the user's own tab"}], "current": 1, "checked": False}
def save(): json.dump(st, open(st_path, "w"))
def log(msg): open(f"{S}/calls", "a").write(msg + "\n")
def opt(name):
    a = sys.argv; return a[a.index(name) + 1] if name in a else None
cmd = sys.argv[1]
if cmd == "documents":
    print(json.dumps([{"window": 5, "index": i, "tab_in_window": i, "url": t["url"], "title": t["title"],
                       "profile": scn.get("profile", "own"), "is_current": i == st["current"]}
                      for i, t in enumerate(st["tabs"], 1)]))
elif cmd == "open":
    url = sys.argv[-1]; log(f"open {url}")
    if url == scn.get("prime"):
        st["tabs"].append({"url": scn.get("prime_lands_on", url), "title": "x.pdf"})
    else:
        st["tabs"].append({"url": scn["landing_final"], "title": scn.get("tab_title", "Article")})
    st["current"] = len(st["tabs"]); save()
elif cmd == "close":
    k = int(opt("--tab-in-window")); log(f"close {k} {st['tabs'][k-1]['url']}")
    del st["tabs"][k - 1]; st["current"] = min(st["current"], len(st["tabs"])); save()
elif cmd == "js":
    k = int(opt("--tab-in-window"))
    f = opt("--file"); src = open(f).read() if f else sys.argv[-1]
    if "document.readyState" in src: print(scn.get("ready_state", "complete"))
    elif "innerText.slice" in src:
        if scn.get("page_js_fails"): sys.exit(1)
        print(scn.get("page_text", "Article\nAbstract text"))
        if scn.get("redirect_after_check") and not st["checked"]:
            st["tabs"][k - 1]["url"] = scn["redirect_after_check"]; st["checked"] = True; save()
    elif "window.__aff = " in src: print("started")
    elif f: print(scn.get("link", ""))
    elif "JSON.stringify({s:" in src: print(scn["meta_raw"] if "meta_raw" in scn else json.dumps(scn["meta"]))
    elif "--output" in sys.argv:
        body = open(scn["body_file"], "rb").read()
        open(opt("--output"), "w").write(base64.b64encode(body).decode())
    elif "delete window.__aff" in src: print("ok")
elif cmd == "wait":
    sys.exit(scn.get("fetch_wait_rc", 0) if "__aff" in (opt("--js") or "") else 0)
PY
chmod +x "$W/stub"

PASS=0 FAIL=0
LANDING=https://doi.org/10.1/x
FINAL=https://pub.example/doi/10.1/x
LINK="GET https://pub.example/doi/pdf/10.1/x"

# run NAME EXPECTED_EXIT SCENARIO_JSON [extra args...]; sets $S for the checks
run() {
  local name=$1 want=$2 scn=$3; shift 3
  S="$W/$name"; mkdir -p "$S/out"; printf '%s' "$scn" > "$S/scn.json"
  STUB_DIR="$S" bash "$SCRIPT" --bin "$W/stub" --window 5 --landing "$LANDING" \
    --out "$S/out/w.pdf" "$@" >"$S/stdout" 2>"$S/stderr"
  local got=$?
  if [ "$got" = "$want" ]; then CUR_OK=1; else CUR_OK=0; echo "  exit $got, wanted $want"; sed 's/^/    | /' "$S/stderr"; fi
  CUR=$name
}
check() {  # check DESCRIPTION CONDITION...
  local d=$1; shift
  if "$@"; then :; else CUR_OK=0; echo "  ✗ $d"; fi
}
done_case() {
  if [ "$CUR_OK" = 1 ]; then PASS=$((PASS+1)); echo "✓ $CUR"; else FAIL=$((FAIL+1)); echo "✗ $CUR"; fi
}
closed_nothing() { ! grep -q '^close' "$S/calls" 2>/dev/null; }
opened_nothing() { ! grep -q '^open' "$S/calls" 2>/dev/null; }
no_output() { [ ! -e "$S/out/w.pdf" ]; }
user_tab_kept() { ! grep -q 'close .*user.example' "$S/calls" 2>/dev/null; }
said_stop() { grep -q 'STOP THE WHOLE RUN' "$S/stderr"; }

printf '%%PDF-1.4\n%% stub body\n' > "$W/pdf.bin"
# Real one-page PDFs for the verify step (pdfinfo/pdftotext must read them).
python3 - "$W" <<'MK'
import sys
def mkpdf(lines, path):
    text = "BT /F1 12 Tf 72 720 Td 14 TL " + " ".join(f"({l}) Tj T*" for l in lines) + " ET"
    objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            f"<< /Length {len(text)} >>\nstream\n{text}\nendstream"]
    out = b"%PDF-1.4\n"; offs = []
    for i, o in enumerate(objs, 1):
        offs.append(len(out)); out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    x = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode() + b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    open(path, "wb").write(out)
w = sys.argv[1]
mkpdf(["A Stub Title For Path Tests", "doi:10.1234/x", "Abstract"], f"{w}/own.pdf")
mkpdf(["A Stub Title For Path Tests", "doi:10.1234/someone-else", "Abstract"], f"{w}/other.pdf")
MK
printf '<html><body><div>Loading...</div></body></html>' > "$W/shell.bin"
printf '<html><body>Forbidden</body></html>' > "$W/forbidden.bin"
PDFLEN=$(wc -c < "$W/pdf.bin" | tr -d ' ')
ok_meta='{"s":200,"c":"application/pdf","l":'$PDFLEN',"e":null}'
base='"landing_final":"'$FINAL'","link":"'$LINK'"'

run happy-path 0 '{'"$base"',"meta":'"$ok_meta"',"body_file":"'"$W/pdf.bin"'"}'
check "output written" test -s "$S/out/w.pdf"
check "our tab closed" grep -q "^close 2 $FINAL" "$S/calls"
check "user tab untouched" user_tab_kept
done_case

run primed-happy-path 0 '{'"$base"',"prime":"https://pub.example/x.pdf","meta":'"$ok_meta"',"body_file":"'"$W/pdf.bin"'"}' \
  --prime https://pub.example/x.pdf
check "prime tab closed" grep -q '^close 2 https://pub.example/x.pdf' "$S/calls"
check "landing tab closed" grep -q "^close 2 $FINAL" "$S/calls"
check "user tab untouched" user_tab_kept
done_case

run challenge-on-landing 6 '{'"$base"',"page_text":"Just a moment...\nChecking"}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run tab-moves-to-another-site 6 '{'"$base"',"redirect_after_check":"https://verify.other.example/c"}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run page-unreadable 6 '{'"$base"',"page_js_fails":true}'
check "stop announced" said_stop; check "tab left open" closed_nothing
done_case

# Body unreadable, but the TAB TITLE (read without JS) shows a challenge: the stop
# must name that signal. Checked by label, because the unreadable-page fallback
# would also exit 6 — only the label shows the title check actually ran.
run challenge-in-title-when-body-unreadable 6 '{'"$base"',"page_js_fails":true,"tab_title":"Just a moment..."}'
check "stop names the title's signal" grep -q 'cloudflare-challenge' "$S/stderr"
check "tab left open" closed_nothing
done_case

run fetch-stalls 6 '{'"$base"',"fetch_wait_rc":1}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run http-403-response 6 '{'"$base"',"meta":{"s":403,"c":"text/html","l":40,"e":null},"body_file":"'"$W/forbidden.bin"'"}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run empty-response 6 '{'"$base"',"meta":{"s":200,"c":"application/pdf","l":0,"e":null},"body_file":"'"$W/pdf.bin"'"}'
check "stop announced" said_stop; check "tab left open" closed_nothing
done_case

run fetch-throws 6 '{'"$base"',"meta":{"s":null,"c":null,"l":null,"e":"TypeError: Load failed"},"body_file":"'"$W/pdf.bin"'"}'
check "stop announced" said_stop; check "tab left open" closed_nothing
done_case

# The verify step, end to end: the DOI comes from the doi.org landing URL.
own_meta='{"s":200,"c":"application/pdf","l":'$(wc -c < "$W/own.pdf" | tr -d ' ')',"e":null}'
other_meta='{"s":200,"c":"application/pdf","l":'$(wc -c < "$W/other.pdf" | tr -d ' ')',"e":null}'
LANDING=https://doi.org/10.1234/x
run verified-by-title-and-landing-doi 0 '{'"$base"',"meta":'"$own_meta"',"body_file":"'"$W/own.pdf"'"}' \
  --title "A Stub Title For Path Tests" --pages 1--1
check "stored under the requested name" test -s "$S/out/w.pdf"
check "verdict shows the printed DOI matched" grep -q '"doi_state": "page-match"' "$S/stdout"
done_case

run another-works-doi-is-not-verified 5 '{'"$base"',"meta":'"$other_meta"',"body_file":"'"$W/other.pdf"'"}' \
  --title "A Stub Title For Path Tests" --pages 1--1
check "kept as unverified" test -s "$S/out/w.unverified.pdf"
check "not under the requested name" no_output
done_case
LANDING=https://doi.org/10.1/x

run page-never-settles 6 '{'"$base"',"ready_state":"loading"}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run response-metadata-unreadable 6 '{'"$base"',"meta_raw":"not json","body_file":"'"$W/pdf.bin"'"}'
check "stop announced" said_stop; check "tab left open" closed_nothing; check "nothing written" no_output
done_case

run primed-tab-sent-elsewhere 6 '{'"$base"',"prime":"https://pub.example/x.pdf","prime_lands_on":"https://verify.other.example/c"}' \
  --prime https://pub.example/x.pdf
check "stop announced" said_stop; check "tab left open" closed_nothing
check "never went on to the article" bash -c "! grep -q '^open $LANDING' '$S/calls'"
done_case

run paywall-shell-is-no-access 4 '{'"$base"',"meta":{"s":200,"c":"text/html","l":48,"e":null},"body_file":"'"$W/shell.bin"'"}'
check "not the stop clause" bash -c "! grep -q 'STOP THE WHOLE RUN' '$S/stderr'"
check "response saved for a human" test -s "$S/out/w.response.txt"
check "our tab closed" grep -q "^close 2 $FINAL" "$S/calls"
done_case

run no-pdf-link 3 '{"landing_final":"'$FINAL'","link":""}'
check "our tab closed" grep -q "^close 2 $FINAL" "$S/calls"
done_case

run wrong-profile-refused 1 '{'"$base"',"profile":"someone-else"}' --expect-profile own
check "never opened a tab" opened_nothing
done_case

# --out inside a git tree that does not ignore it: refused before any browser call
G="$W/repo"; mkdir -p "$G"; git -C "$G" init -q
S="$W/out-in-git"; mkdir -p "$S"; printf '%s' '{'"$base"'}' > "$S/scn.json"
STUB_DIR="$S" bash "$SCRIPT" --bin "$W/stub" --window 5 --landing "$LANDING" --out "$G/w.pdf" >"$S/stdout" 2>"$S/stderr"
got=$?; CUR=out-in-git-tree-refused; CUR_OK=1
[ "$got" = 1 ] || { CUR_OK=0; echo "  exit $got, wanted 1"; }
check "never opened a tab" opened_nothing
check "says why" grep -q 'working tree' "$S/stderr"
done_case

echo "── $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
