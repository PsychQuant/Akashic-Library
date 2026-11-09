#!/bin/bash
# akashic-mcp plugin 的 SessionStart 檢查：`akashic` CLI 在不在、契約夠不夠新、是否落後原始碼（#775）。
#
# 移植自 safari-browser plugin 的 hooks/check-cli.sh（safari-browser#278 之後的版本），結構照搬，三處不同：
#
#   1. 契約比對。akashic-fetch-fulltext SKILL 第 0 步要求 `akashic fulltext contract` 印出的版本 ≥ N。那個 N 只寫在
#      SKILL 裡（同一件事只能有一份描述），這裡從 SKILL 抽出來比，不另寫一份；抽不到就說出來、不當成通過。
#      這一項不需要原始碼 checkout，所有人都會跑到。
#   2. 落後的基準是 `origin/main`（上次 fetch 時的狀態，不連網），沒有這個 ref 才用 checkout 的 HEAD。Akashic 的工作在
#      worktree 與 PR 上進行，主 checkout 不常 pull——拿 HEAD 當尺會系統性地少報落後（#775 診斷時本機主 checkout
#      落後 origin/main 308 個 commit）。
#   3. CLI 從 PATH 找（skill 呼叫的是 PATH 上的 `akashic`），沒有才看 `$HOME/bin/akashic`。原始碼目錄是
#      `$AKASHIC_SOURCE_DIR`，預設 `$HOME/Developer/Akashic-Library`。
#
# Akashic CLI 沒有發布版（#633），所以「落後」只能跟原始碼比，不能跟 release 比。
#
# 建置時的 commit 由 `akashic --version` 說出（`scripts/stamp-version.sh` 在建置期間寫入，裸的 `<hash>[-dirty]`）。
# 那個 commit 在基準的歷史裡時，只數之後「動到 package 原始碼」的 commit（`Sources`、`Package.swift`、`Package.resolved`、
# submodule `repos/biblatex-apa-swift`），只改文件的 commit 不算。`Sources` 也含 akashic-mcp、App、guards 等不進 CLI 的
# target，所以會過報——訊息因此寫「動到 package 原始碼」，不說「CLI 的程式碼」。
#
# 比不出祖先關係是常態，不是例外：這個 repo 用 squash merge，從 PR branch 建的 binary 永遠不會是 main 的祖先。那時若
# package 原始碼與基準相同就當作最新；否則說明原因，改比檔案時間（binary 的修改時間 vs 基準上最後一個動到 package
# 原始碼的 commit）。停在「無法比較」就再也不會提醒。沒有戳記的建置（印 `unknown`）與比 #775 舊的 CLI（`--version`
# 回 64）直接比檔案時間。
#
# 每個 session 開始時都會跑（plugin 是全域的），所以：不連網、不自動安裝、不覆蓋現有的 binary；兩次探測各有約 4 秒上限，
# `--version` 逾時就不再探契約；任何失敗都 exit 0、不寫 stderr。
#
# 這支是 shell 而不是 Swift：它要判斷的就是 `akashic` binary 本身（不存在、過舊、卡住），判斷者不能住在被判斷的 binary
# 裡（`.claude/rules/swift-is-the-implementation-language.md` 例外 1）。行為測試在 Tests/AkashicCLITests/CheckCLIHookTests.swift。

SOURCE_DIR="${AKASHIC_SOURCE_DIR:-$HOME/Developer/Akashic-Library}"
COMPILED_PATHS=(Sources Package.swift Package.resolved repos/biblatex-apa-swift)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
SKILL_FILE="$PLUGIN_ROOT/skills/akashic-fetch-fulltext/SKILL.md"
STEP0_NEEDLE='"${v#fulltext-contract }" -ge '

# 不連網：partial clone 的 rev-list／log 會在缺物件時去 fetch；也不要跳出帳密提示、不寫 index 的鎖
export GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0

# 探測的暫存檔與 process group，不論探測怎麼結束都要清掉。`probe` 在 $(...) 子 shell 裡跑，子 shell 不繼承之後才設的
# 變數值、也不繼承 trap，所以它自己裝這個清理。
PROBE_OUT=""
PROBE_PID=""
probe_cleanup() {
    [[ -n "$PROBE_PID" ]] && kill -KILL -- "-$PROBE_PID" 2>/dev/null
    [[ -n "$PROBE_OUT" ]] && rm -f "$PROBE_OUT"
    PROBE_PID=""
    PROBE_OUT=""
}

# `$CLI <參數>` 的第一行輸出，最壞約 4 秒。探測自己一個 process group（job control），子行程跟著一起停；先 TERM，
# 半秒後 KILL。group 另帶一個 4 秒的計時器（KILL 整組），因為自己一個 group 之後，送給 hook 本身 group 的 SIGKILL
# 碰不到它。命令失敗（例如舊 CLI 對 `--version` 回 64）時什麼都不印；逾時時回 2，呼叫端據此不再探第二次。
# 只讀前 4 KiB：答案是一行。呼叫時要丟掉 stderr——bash 會在那裡報告它 kill 掉的 job。
probe() {
    local waited=0 grace=0
    trap probe_cleanup EXIT
    trap 'exit 1' INT TERM HUP
    PROBE_OUT=$(mktemp "${TMPDIR:-/tmp}/akashic-check-cli.XXXXXX") || return 1
    set -m
    /bin/sh -c '(sleep 4; kill -KILL 0) & exec "$0" "$@"' "$CLI" "$@" \
        >"$PROBE_OUT" 2>/dev/null </dev/null &
    PROBE_PID=$!
    set +m
    while kill -0 "$PROBE_PID" 2>/dev/null; do
        if (( waited >= 30 )); then
            kill -TERM -- "-$PROBE_PID" 2>/dev/null
            while kill -0 "$PROBE_PID" 2>/dev/null && (( grace < 5 )); do
                sleep 0.1
                grace=$((grace + 1))
            done
            kill -KILL -- "-$PROBE_PID" 2>/dev/null
            wait "$PROBE_PID" 2>/dev/null
            probe_cleanup
            return 2
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    if wait "$PROBE_PID"; then
        head -c 4096 "$PROBE_OUT" | head -n 1
    fi
    probe_cleanup
}

# 印出來的 commit subject 與路徑只留可印字元
clean() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

print_install_hint() {
    local target="${CLI:-$HOME/bin/akashic}"
    if [[ -z "$SOURCE_TOP" ]]; then
        echo "   先取得原始碼："
        echo "     git clone https://github.com/PsychQuant/Akashic-Library.git $(clean "$SOURCE_DIR")"
    fi
    echo "   重建（在 $(clean "$SOURCE_DIR") 執行；install 換成新的檔案，不要原地覆寫已簽章的 binary）："
    echo "     git pull && git submodule update --init repos/biblatex-apa-swift"
    echo "     scripts/stamp-version.sh Sources/akashic/BuildVersion.swift -- swift build -c release --product akashic"
    echo "     install -m 755 \"\$(swift build -c release --show-bin-path)/akashic\" $(clean "$target")"
}

# 原始碼目錄要是它自己那個 repo 的根目錄（`.git` 是目錄或檔都算，worktree 是檔）。不檢查根目錄的話，
# 不存在的子目錄或剛好在別的 repo 裡（例如 HOME 是 dotfiles repo）會借到錯的歷史。
SOURCE_TOP=""
if [[ -d "$SOURCE_DIR" ]]; then
    top=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null) \
        && [[ "$(cd "$top" 2>/dev/null && pwd -P)" == "$(cd "$SOURCE_DIR" 2>/dev/null && pwd -P)" ]] \
        && SOURCE_TOP="$top"
fi

# ── CLI 在哪 ────────────────────────────────────────────────────────────────
CLI=""
OFF_PATH=""
if found=$(command -v akashic 2>/dev/null) && [[ "$found" == /* && -x "$found" ]]; then
    CLI="$found"
elif [[ -x "$HOME/bin/akashic" ]]; then
    CLI="$HOME/bin/akashic"
    OFF_PATH=1
fi

if [[ -z "$CLI" ]]; then
    echo "⚠️  找不到 akashic CLI（PATH 上沒有，$(clean "$HOME")/bin/akashic 也不存在）。akashic-fetch-fulltext 等 skill 需要它；它沒有發布版（#633），要從原始碼建置。"
    print_install_hint
    exit 0
fi

# 純文字且短：這個值會被印出來，其中一段會變成 git 的參數
VERSION=$(probe --version 2>/dev/null)
VERSION_RC=$?
(( ${#VERSION} <= 128 )) || VERSION=""
[[ "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || VERSION=""

echo "✓ akashic CLI：$(clean "$CLI")${VERSION:+（$VERSION）}"
[[ -n "$OFF_PATH" ]] && echo "   它不在 PATH 上：akashic-fetch-fulltext 等 skill 呼叫的是 PATH 上的 akashic。"

NEEDS_REBUILD=""

# ── 契約 ───────────────────────────────────────────────────────────────────
if (( VERSION_RC == 2 )); then
    echo "ℹ️  akashic CLI 在約 4 秒內沒有回應 --version：沒有比對契約。"
else
    REQUIRED=""
    if [[ -r "$SKILL_FILE" ]] \
       && [[ "$(grep -oF -- "$STEP0_NEEDLE" "$SKILL_FILE" 2>/dev/null | wc -l | tr -d ' ')" == 1 ]]; then
        line=$(grep -F -- "$STEP0_NEEDLE" "$SKILL_FILE" 2>/dev/null)
        rest="${line#*"$STEP0_NEEDLE"}"
        [[ "$rest" =~ ^([0-9]{1,6}) ]] && REQUIRED="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$REQUIRED" ]]; then
        echo "ℹ️  讀不到 akashic-fetch-fulltext 要求的契約版本（SKILL 第 0 步的格式變了？）：沒有比對契約。"
    else
        HAVE=""
        CONTRACT_LINE=$(probe fulltext contract 2>/dev/null)
        [[ "$CONTRACT_LINE" =~ ^fulltext-contract\ ([0-9]{1,6})$ ]] && HAVE="${BASH_REMATCH[1]}"
        if [[ -z "$HAVE" ]]; then
            echo "⬆️  讀不到 akashic CLI 的 fulltext 契約（沒有 fulltext contract 子命令，或執行失敗），akashic-fetch-fulltext 要求 ≥ $REQUIRED：先重建 CLI 再跑那個 skill。"
            NEEDS_REBUILD=1
        elif (( 10#$HAVE < 10#$REQUIRED )); then
            echo "⬆️  akashic CLI 的 fulltext 契約是 $HAVE，akashic-fetch-fulltext 要求 ≥ $REQUIRED：先重建 CLI 再跑那個 skill。"
            NEEDS_REBUILD=1
        fi
    fi
fi

# ── 落後原始碼 ──────────────────────────────────────────────────────────────
# 建置的 commit 與基準比。比不出祖先關係時說明原因並回 1，呼叫端改比檔案時間。
report_by_commit() {
    local commit count latest noun
    commit=$(git -C "$SOURCE_TOP" rev-parse --verify --quiet "$BUILD_REF^{commit}" 2>/dev/null) || {
        echo "ℹ️  akashic CLI 建置自 $BUILD_REF，$(clean "$SOURCE_TOP") 裡沒有這個 commit（在別處建置，或 checkout 沒有 fetch）：改比檔案時間。"
        return 1
    }
    if ! git -C "$SOURCE_TOP" merge-base --is-ancestor "$commit" "$BASE_COMMIT" 2>/dev/null; then
        # 常態：binary 從 PR branch 建置，那個 branch 之後被 squash merge。package 原始碼與基準相同就沒有東西更新。
        if git -C "$SOURCE_TOP" diff --quiet "$commit" "$BASE_COMMIT" -- "${COMPILED_PATHS[@]}" 2>/dev/null; then
            return 0
        fi
        if git -C "$SOURCE_TOP" merge-base --is-ancestor "$BASE_COMMIT" "$commit" 2>/dev/null; then
            echo "ℹ️  akashic CLI 建置自 $BUILD_REF，比 $BASE_NAME 新（從尚未合併的 branch 建置，或 checkout 沒有 fetch）：改比檔案時間。"
        else
            echo "ℹ️  akashic CLI 建置自 $BUILD_REF，它不在 $BASE_NAME 的歷史裡（別的 branch，或 commit 被 squash／rebase 掉）：改比檔案時間。"
        fi
        return 1
    fi
    count=$(git -C "$SOURCE_TOP" rev-list --count "$commit..$BASE_COMMIT" -- "${COMPILED_PATHS[@]}" 2>/dev/null)
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
    if (( count > 0 )); then
        latest=$(git -C "$SOURCE_TOP" log -1 --format='%h %s' "$BASE_COMMIT" -- "${COMPILED_PATHS[@]}" 2>/dev/null)
        echo "⬆️  akashic CLI 落後原始碼：這次建置（$VERSION）之後，$BASE_LABEL 有 $count 個 commit 動到 package 原始碼。"
        echo "   最新一個：$(clean "$latest")"
        if [[ "$VERSION" == *-dirty ]]; then
            echo "   建置時工作樹有未 commit 的修改，其中一些可能已經在 binary 裡。"
        fi
        NEEDS_REBUILD=1
    fi
    return 0
}

# 說不出自己是哪個 commit 的 binary，或那個 commit 比不出來時用的訊號。
report_by_file_times() {
    local src_line src_ts bin_ts bin_date src_date
    src_line=$(git -C "$SOURCE_TOP" log -1 --format='%ct %h %s' "$BASE_COMMIT" -- "${COMPILED_PATHS[@]}" 2>/dev/null)
    src_ts="${src_line%% *}"
    bin_ts=$(stat -f %m "$CLI" 2>/dev/null)
    if [[ "$src_ts" =~ ^[0-9]+$ && "$bin_ts" =~ ^[0-9]+$ ]] && (( src_ts > bin_ts )); then
        bin_date=$(date -r "$bin_ts" '+%Y-%m-%d %H:%M')
        src_date=$(date -r "$src_ts" '+%Y-%m-%d %H:%M')
        echo "⬆️  akashic CLI 比原始碼舊：binary $bin_date，$BASE_LABEL 最後一次動到 package 原始碼是 $src_date。"
        echo "   最後一次：$(clean "${src_line#* }")"
        NEEDS_REBUILD=1
    fi
}

if [[ -n "$SOURCE_TOP" ]]; then
    if BASE_COMMIT=$(git -C "$SOURCE_TOP" rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}' 2>/dev/null); then
        BASE_NAME="origin/main"
        BASE_LABEL="origin/main（上次 fetch 時）"
    elif BASE_COMMIT=$(git -C "$SOURCE_TOP" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null); then
        BASE_NAME="HEAD"
        BASE_LABEL="HEAD"
    else
        BASE_COMMIT=""
    fi
    if [[ -n "$BASE_COMMIT" ]]; then
        # 建置的 commit：裸 hash（stamp-version.sh 的格式），可帶 `-dirty`；`unknown` 與舊 CLI 沒有
        BUILD_REF=""
        [[ "$VERSION" =~ ^([0-9a-f]{7,40})(-dirty)?$ ]] && BUILD_REF="${BASH_REMATCH[1]}"
        if [[ -z "$BUILD_REF" ]] || ! report_by_commit; then
            report_by_file_times
        fi
    fi
fi

[[ -n "$NEEDS_REBUILD" ]] && print_install_hint
exit 0
