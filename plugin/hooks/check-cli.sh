#!/bin/bash
# akashic-mcp plugin 的 SessionStart 檢查：`akashic` CLI 在不在、契約夠不夠新、是否落後原始碼（#775）。
#
# 移植自 safari-browser plugin 的 hooks/check-cli.sh（safari-browser#278 之後的版本），不同的地方：
#
#   1. 契約比對。akashic-fetch-fulltext SKILL 第 0 步要求 `akashic fulltext contract` 印出的版本 ≥ N。那個 N 只寫在
#      SKILL 裡（同一件事只能有一份描述），這裡從 SKILL 抽出來比，不另寫一份；抽不到就說出來、不當成通過。
#      這一項不需要原始碼 checkout，所有人都會跑到。
#   2. 落後的基準是 `origin/main`（上次 fetch 時的狀態，不連網），沒有這個 ref 才用 checkout 的 HEAD。Akashic 的工作在
#      worktree 與 PR 上進行，主 checkout 不常 pull——拿 HEAD 當尺會系統性地少報落後（#775 診斷時本機主 checkout
#      落後 origin/main 308 個 commit）。
#   3. CLI 從 PATH 找（skill 呼叫的是 PATH 上的 `akashic`），沒有才看 `$HOME/bin/akashic`。原始碼目錄是
#      `$AKASHIC_SOURCE_DIR`，預設 `$HOME/Developer/Akashic-Library`。
#   4. 落後與否看內容，不看祖先關係（見下）。這個 repo 用 squash merge，從 PR branch 建的 binary 永遠不會是 main 的祖先。
#
# Akashic CLI 沒有發布版（#633），所以「落後」只能跟原始碼比，不能跟 release 比。
#
# 怎麼判定落後。建置時的 commit 由 `akashic --version` 說出（`scripts/stamp-version.sh` 在建置期間寫入，裸的
# `<hash>[-dirty]`）。「package 原始碼」是 COMPILED_PATHS 那四個路徑；`Sources` 也含 akashic-mcp、App、guards 等不進 CLI
# 的 target，所以會過報——訊息因此寫「動到 package 原始碼」，不說「CLI 的程式碼」。
#   · 基準上沒有「不在這次建置的歷史裡、又動到 package 原始碼」的 commit → 最新。建置比基準新也落在這裡。
#   · 有的話看內容：從兩者的共同祖先到基準，基準改過哪些檔；那些檔在這次建置裡都與基準是同一份內容 → 最新。
#     squash 合併之後就是這樣（基準多了一個 squash commit，內容早就在建置裡）；基準改了又改回來也是。
#   · 其中有檔不同 → 落後，印 commit 數。建置不是基準的祖先時，那個數字含 squash 的 commit，訊息會說出來。
#   · checkout 裡沒有那個 commit、兩者沒有共同的歷史、git 讀不出來 → 說明原因，改比檔案時間（binary 的修改時間 vs
#     基準上最後一個動到 package 原始碼的 commit）。沒有戳記的建置（印 `unknown`）也比檔案時間。
#   · `--version` 回 64（比 #775 舊的 CLI）而基準上已經有 BuildVersion.swift → 必定落後；基準上還沒有 → 比檔案時間。
#   已知的界線：內容以檔為單位比。分支的前半被 squash 合併之後又改了同一個檔，會被報成落後。
#
# 每個 session 開始時都會跑（plugin 是全域的），輸出進的是模型的 context，所以：
#   · 不連網、不自動安裝、不覆蓋現有的 binary；提示寫明要不要重建由使用者決定。
#   · 兩次探測各有約 4 秒上限，`--version` 逾時就不再探契約；整支 hook 在 hooks.json 另有上限。
#   · 任何失敗都 exit 0、不寫 stderr。
#   · 不吃繼承的環境：清掉所有 `GIT_*`（`GIT_DIR` 會把 git 帶到別的 repo），`PATH` 只看絕對路徑的項目，
#     內部用的工具只從 /usr/bin、/bin 找。
#   · git 只用 plumbing（rev-parse、merge-base、rev-list、diff-tree、cat-file），不用 `git log`、`git diff`：
#     `log.showSignature`、`diff.external`、`diff.trustExitCode` 這類設定因此讀不到，gpg 與外部 diff 不會被執行。
#   · 不印 commit subject：那是別人寫的字（squash 時就是 PR 標題），只印 hash 與日期。
#
# 這支是 shell 而不是 Swift：它要判斷的就是 `akashic` binary 本身（不存在、過舊、卡住），判斷者不能住在被判斷的 binary
# 裡（`.claude/rules/swift-is-the-implementation-language.md` 例外 1）。行為測試在 Tests/AkashicCLITests/CheckCLIHookTests.swift。（這兩個是 repo 內的檔，plugin 安裝處讀不到。）

# 整支在 C locale 下跑：字元範圍（`[A-Za-z0-9]`）只認 ASCII，sort 與 comm 的順序一致；中文訊息照位元組原樣印出。
# 變數仍一律寫成 ${名字}，不寫 $名字：UTF-8 locale 下 bash 會把緊接在後面的全形標點當成名字的一部分（`$HAVE，` 被讀成
# 變數 `HAVE，`），印出半個字元。第一版就是這樣，測試跑在 C locale 而沒抓到，實機第一次跑整排亂碼（#775）。
export LC_ALL=C

# 不吃繼承的 GIT_*：`GIT_DIR`、`GIT_WORK_TREE` 會把下面的 git 帶到別的 repo（`-C` 蓋不掉），`GIT_EXTERNAL_DIFF`、
# `GIT_EXEC_PATH` 會讓它執行別的程式。之後才設自己要的三個——不連網（partial clone 的 rev-list 會在缺物件時去 fetch）、
# 不跳帳密提示、不寫 index 的鎖。
for inherited in "${!GIT_@}"; do unset "${inherited}"; done
export GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0

SOURCE_DIR="${AKASHIC_SOURCE_DIR:-${HOME}/Developer/Akashic-Library}"
# 會被編進 binary 的路徑。scripts/stamp-version.sh 有逐字相同的一行（StampVersionTests 比對）。
COMPILED_PATHS=(Sources Package.swift Package.resolved repos/biblatex-apa-swift)
VERSION_FILE="Sources/akashic/BuildVersion.swift"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
SKILL_FILE="${PLUGIN_ROOT}/skills/akashic-fetch-fulltext/SKILL.md"
STEP0_NEEDLE='"${v#fulltext-contract }" -ge '

# `PATH` 只看絕對路徑的項目：`.`、空項與相對路徑指的是當前目錄（專案目錄），那裡的 `git`、`akashic` 不該在開 session 時
# 被執行。使用者的 PATH 只用來找 akashic 與 git；其餘工具（mktemp、stat、date、sort…）只從系統目錄找。
USER_PATH=""
rest="${PATH}:"
while [[ -n "${rest}" ]]; do
    entry="${rest%%:*}"
    rest="${rest#*:}"
    [[ "${entry}" == /* ]] && USER_PATH="${USER_PATH:+${USER_PATH}:}${entry}"
done
export PATH="/usr/bin:/bin"

# 在使用者的 PATH 上找一個命令，印出它的絕對路徑；找不到就不印
find_on_user_path() {
    local found
    found=$(PATH="${USER_PATH:-/usr/bin:/bin}" command -v "$1" 2>/dev/null) || return 1
    [[ "${found}" == /* && -x "${found}" && ! -d "${found}" ]] || return 1
    printf '%s' "${found}"
}

GIT=$(find_on_user_path git)
# 原始碼 repo 的 git（只呼叫 plumbing）
sgit() { "${GIT}" -C "${SOURCE_TOP}" "$@" 2>/dev/null; }

# 探測的暫存檔與 process group，不論探測怎麼結束都要清掉。`probe` 在 $(...) 子 shell 裡跑，子 shell 不繼承之後才設的
# 變數值、也不繼承 trap，所以它自己裝這個清理。
PROBE_OUT=""
PROBE_PID=""
probe_cleanup() {
    [[ -n "${PROBE_PID}" ]] && kill -KILL -- "-${PROBE_PID}" 2>/dev/null
    [[ -n "${PROBE_OUT}" ]] && rm -f "${PROBE_OUT}"
    PROBE_PID=""
    PROBE_OUT=""
}

# 執行 `$CLI <參數>`，成功時印它的第一行輸出。回傳值：
#     0    成功
#     64   CLI 回 64（ArgumentParser 的用法錯誤：不認得這個旗標或子命令）
#     124  逾時（約 4 秒）
#     其他 CLI 的結束碼（CLI 自己回 124 時改成 1，不與逾時混淆）
# 探測自己一個 process group（job control），子行程跟著一起停；逾時先 TERM，半秒後 KILL。逾時只由下面的迴圈判定。
# group 裡另有一個 8 秒的計時器（KILL 整組）：自己一個 group 之後，送給 hook 本身 group 的 SIGKILL 碰不到它，
# hook 被砍掉時由它收尾。迴圈慢到讓它先動手（系統很忙）時，結束碼是 137 而且已經過了 3 秒以上，照樣算逾時；
# 一執行就 137 的（例如原地覆寫過的已簽章 binary）不是逾時。
# 只讀前 4 KiB：答案是一行。呼叫時要丟掉 stderr——bash 會在那裡報告它 kill 掉的 job。
probe() {
    local waited=0 grace=0 rc=0 started=${SECONDS}
    trap probe_cleanup EXIT
    trap 'exit 1' INT TERM HUP
    PROBE_OUT=$(mktemp "${TMPDIR:-/tmp}/akashic-check-cli.XXXXXX") || return 1
    set -m
    /bin/sh -c '(sleep 8; kill -KILL 0) & exec "$0" "$@"' "${CLI}" "$@" \
        >"${PROBE_OUT}" 2>/dev/null </dev/null &
    PROBE_PID=$!
    set +m
    while kill -0 "${PROBE_PID}" 2>/dev/null; do
        if (( waited >= 30 )); then
            kill -TERM -- "-${PROBE_PID}" 2>/dev/null
            while kill -0 "${PROBE_PID}" 2>/dev/null && (( grace < 5 )); do
                sleep 0.1
                grace=$((grace + 1))
            done
            kill -KILL -- "-${PROBE_PID}" 2>/dev/null
            wait "${PROBE_PID}" 2>/dev/null
            probe_cleanup
            return 124
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    wait "${PROBE_PID}"
    rc=$?
    if (( rc == 0 )); then
        head -c 4096 "${PROBE_OUT}" | head -n 1
    elif (( rc == 137 && SECONDS - started >= 3 )); then
        rc=124
    elif (( rc == 124 )); then
        rc=1
    fi
    probe_cleanup
    return "${rc}"
}

# 印出來的路徑只留可印字元
clean() { printf '%s' "$1" | tr -d '\000-\037\177'; }

# 印進指令裡的路徑：只含 [A-Za-z0-9_./+-] 時原樣，否則整個用單引號包起來，內含的單引號寫成 '\''。
# 不用 `printf %q`：bash 3.2 的 %q 在 UTF-8 locale 下會把中文路徑印成不完整的位元組。
shq() {
    local s sq="'" rep="'\\''"
    s=$(clean "$1")
    case "${s}" in
        ""|*[!A-Za-z0-9_./+-]*) printf "'%s'" "${s//${sq}/${rep}}" ;;
        *) printf '%s' "${s}" ;;
    esac
}

# 重建的指令。輸出進的是模型的 context，而這幾行會改動使用者的機器，所以第一行先說清楚是誰決定。
print_install_hint() {
    local target="${CLI:-${HOME}/bin/akashic}" where
    echo "   （給 Claude：把上面的狀況告訴使用者，要不要重建由使用者決定；不要自己執行下面的指令。）"
    case "${SOURCE_STATE}" in
        missing)
            echo "   先取得原始碼（已經有 checkout 的話，把 AKASHIC_SOURCE_DIR 設成它的根目錄）："
            echo "     git clone https://github.com/PsychQuant/Akashic-Library.git $(shq "${SOURCE_DIR}")"
            where="在 $(shq "${SOURCE_DIR}") 執行"
            ;;
        ok) where="在 $(shq "${SOURCE_DIR}") 執行" ;;
        *)  where="在 Akashic-Library checkout 的根目錄執行" ;;
    esac
    echo "   重建（${where}）："
    echo "     git pull && git submodule update --init repos/biblatex-apa-swift"
    echo "     scripts/stamp-version.sh ${VERSION_FILE} -- swift build -c release --product akashic"
    if [[ -n "${SOURCE_TOP}" && -n "${CLI}" && "${CLI}" -ef "${SOURCE_TOP}/.build/release/akashic" ]]; then
        echo "   $(clean "${CLI}") 就是這個建置產物，重建之後不必另外安裝。"
    else
        echo "   放到 CLI 的位置（install 會換成新的檔案；不要原地覆寫已簽章的 binary）："
        echo "     mkdir -p $(shq "$(dirname "${target}")")"
        echo "     install -m 755 \"\$(swift build -c release --show-bin-path)/akashic\" $(shq "${target}")"
    fi
}

# ── 原始碼目錄 ──────────────────────────────────────────────────────────────
# 要是它自己那個 repo 的根目錄（`.git` 是目錄或檔都算，worktree 是檔）。不檢查根目錄的話，不存在的子目錄或剛好在
# 別的 repo 裡（例如 HOME 是 dotfiles repo）會借到錯的歷史。
SOURCE_TOP=""
SOURCE_STATE="missing"          # missing｜no-git｜not-root｜ok
if [[ -d "${SOURCE_DIR}" ]]; then
    if [[ -z "${GIT}" ]]; then
        SOURCE_STATE="no-git"
    elif top=$("${GIT}" -C "${SOURCE_DIR}" rev-parse --show-toplevel 2>/dev/null) && [[ -n "${top}" ]] \
         && [[ "$(cd "${top}" 2>/dev/null && pwd -P)" == "$(cd "${SOURCE_DIR}" 2>/dev/null && pwd -P)" ]]; then
        SOURCE_TOP="${top}"
        SOURCE_STATE="ok"
    else
        SOURCE_STATE="not-root"
    fi
fi

# ── CLI 在哪 ────────────────────────────────────────────────────────────────
OFF_PATH=""
if ! CLI=$(find_on_user_path akashic); then
    CLI=""
    if [[ -x "${HOME}/bin/akashic" && ! -d "${HOME}/bin/akashic" ]]; then
        CLI="${HOME}/bin/akashic"
        OFF_PATH=1
    fi
fi

if [[ -z "${CLI}" ]]; then
    echo "⚠️  找不到 akashic CLI（PATH 上沒有，$(clean "${HOME}")/bin/akashic 也不存在）。akashic-fetch-fulltext 等 skill 需要它；它沒有發布版（#633），要從原始碼建置。"
    print_install_hint
    exit 0
fi

# 純文字且短：這個值會被印出來，其中一段會變成 git 的參數
VERSION=$(probe --version 2>/dev/null)
VERSION_RC=$?
(( ${#VERSION} <= 128 )) || VERSION=""
[[ "${VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || VERSION=""

# ✓ 只給有回應的 CLI：0 是正常，64 是「活著，但不認得 --version」（比 #775 舊）
case "${VERSION_RC}" in
    0)   echo "✓ akashic CLI：$(clean "${CLI}")${VERSION:+（${VERSION}）}" ;;
    64)  echo "✓ akashic CLI：$(clean "${CLI}")" ;;
    124) echo "⚠️  akashic CLI（$(clean "${CLI}")）在約 4 秒內沒有回應 --version：沒有比對契約。" ;;
    *)   echo "⚠️  akashic CLI（$(clean "${CLI}")）執行 --version 失敗（結束碼 ${VERSION_RC}）。" ;;
esac
[[ -n "${OFF_PATH}" ]] && echo "   它不在 PATH 上：akashic-fetch-fulltext 等 skill 呼叫的是 PATH 上的 akashic。"

NEEDS_REBUILD=""

# ── 契約 ───────────────────────────────────────────────────────────────────
if (( VERSION_RC != 124 )); then
    REQUIRED=""
    if [[ -r "${SKILL_FILE}" ]] \
       && [[ "$(grep -oF -- "${STEP0_NEEDLE}" "${SKILL_FILE}" 2>/dev/null | wc -l | tr -d ' ')" == 1 ]]; then
        line=$(grep -F -- "${STEP0_NEEDLE}" "${SKILL_FILE}" 2>/dev/null)
        rest="${line#*"${STEP0_NEEDLE}"}"
        [[ "${rest}" =~ ^([0-9]{1,6}) ]] && REQUIRED="${BASH_REMATCH[1]}"
    fi
    if [[ -z "${REQUIRED}" ]]; then
        echo "ℹ️  讀不到 akashic-fetch-fulltext 要求的契約版本（SKILL 第 0 步的格式變了？）：沒有比對契約。"
    else
        HAVE=""
        CONTRACT_LINE=$(probe fulltext contract 2>/dev/null)
        [[ "${CONTRACT_LINE}" =~ ^fulltext-contract\ ([0-9]{1,6})$ ]] && HAVE="${BASH_REMATCH[1]}"
        if [[ -z "${HAVE}" ]]; then
            echo "⬆️  讀不到 akashic CLI 的 fulltext 契約（沒有 fulltext contract 子命令，或執行失敗），akashic-fetch-fulltext 要求 ≥ ${REQUIRED}：先重建 CLI 再跑那個 skill。"
            NEEDS_REBUILD=1
        elif (( 10#${HAVE} < 10#${REQUIRED} )); then
            echo "⬆️  akashic CLI 的 fulltext 契約是 ${HAVE}，akashic-fetch-fulltext 要求 ≥ ${REQUIRED}：先重建 CLI 再跑那個 skill。"
            NEEDS_REBUILD=1
        fi
    fi
fi

# ── 落後原始碼 ──────────────────────────────────────────────────────────────
format_time() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null; }

# 基準上最後一個動到 package 原始碼的 commit：印 `<秒> <hash>`，讀不出來就不印。
# `rev-list --timestamp` 是 plumbing，輸出只有這兩欄——不經過 `git log` 的格式與簽章顯示。
latest_source_commit() {
    local line
    line=$(sgit rev-list -1 --timestamp --abbrev-commit --abbrev=12 "${BASE_COMMIT}" -- "${COMPILED_PATHS[@]}")
    [[ "${line}" =~ ^([0-9]{1,12})\ ([0-9a-f]{7,64})$ ]] && echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
}

# 建置的 commit 與基準比。比不出來時說明原因並回 1，呼叫端改比檔案時間。
report_by_commit() {
    local commit count mb changed differs missing latest
    commit=$(sgit rev-parse --verify --quiet "${BUILD_REF}^{commit}") || {
        echo "ℹ️  akashic CLI 建置自 ${BUILD_REF}，$(clean "${SOURCE_TOP}") 裡沒有這個 commit（在別處建置，或 checkout 沒有 fetch）：改比檔案時間。"
        return 1
    }
    # 基準上、不在這次建置的歷史裡、動到 package 原始碼的 commit
    count=$(sgit rev-list --count "${commit}..${BASE_COMMIT}" -- "${COMPILED_PATHS[@]}")
    [[ "${count}" =~ ^[0-9]+$ ]] || {
        echo "ℹ️  讀不出 ${BUILD_REF} 與 ${BASE_NAME} 之間的歷史：改比檔案時間。"
        return 1
    }
    (( count == 0 )) && return 0
    mb=$(sgit merge-base "${commit}" "${BASE_COMMIT}") && [[ -n "${mb}" ]] || {
        echo "ℹ️  akashic CLI 建置自 ${BUILD_REF}，它與 ${BASE_NAME} 沒有共同的歷史：改比檔案時間。"
        return 1
    }
    # 內容：共同祖先到基準之間基準改過的檔（changed），其中有沒有在這次建置裡與基準不同的（differs）
    changed=$(sgit diff-tree -r --name-only --no-renames "${mb}" "${BASE_COMMIT}" -- "${COMPILED_PATHS[@]}") \
        && differs=$(sgit diff-tree -r --name-only --no-renames "${commit}" "${BASE_COMMIT}" -- "${COMPILED_PATHS[@]}") || {
        echo "ℹ️  讀不出 ${BUILD_REF} 與 ${BASE_NAME} 的內容差異：改比檔案時間。"
        return 1
    }
    # 兩份清單的交集有幾行。`grep -c` 在 0 行時結束碼是 1——0 是答案不是失敗，所以只看它印的數字
    missing=$(comm -12 <(printf '%s\n' "${changed}" | sort) <(printf '%s\n' "${differs}" | sort) 2>/dev/null | grep -c .)
    [[ "${missing}" =~ ^[0-9]+$ ]] || {
        echo "ℹ️  讀不出 ${BUILD_REF} 與 ${BASE_NAME} 的內容差異：改比檔案時間。"
        return 1
    }
    (( missing == 0 )) && return 0
    if [[ "${mb}" == "${commit}" ]]; then
        echo "⬆️  akashic CLI 落後原始碼：這次建置（${VERSION}）之後，${BASE_LABEL} 有 ${count} 個 commit 動到 package 原始碼。"
    else
        echo "⬆️  akashic CLI 落後原始碼：這次建置（${VERSION}）不在 ${BASE_NAME} 的歷史裡，而 ${BASE_LABEL} 有 ${count} 個動到 package 原始碼的 commit 不在這次建置的歷史裡（squash 合併的 commit 也算，實際缺的可能較少）。"
    fi
    latest=$(latest_source_commit)
    [[ -n "${latest}" ]] && echo "   最新一個：${latest#* }（$(format_time "${latest%% *}")）"
    if [[ "${VERSION}" == *-dirty ]]; then
        echo "   建置時工作樹有未 commit 的修改，其中一些可能已經在 binary 裡。"
    fi
    NEEDS_REBUILD=1
    return 0
}

# 說不出自己是哪個 commit 的 binary，或那個 commit 比不出來時用的訊號。symlink 的 CLI 比它指向的檔（-L）。
report_by_file_times() {
    local latest src_ts bin_ts
    latest=$(latest_source_commit)
    [[ -n "${latest}" ]] || return 0
    src_ts="${latest%% *}"
    bin_ts=$(stat -L -f %m "${CLI}" 2>/dev/null)
    if [[ "${bin_ts}" =~ ^[0-9]+$ ]] && (( src_ts > bin_ts )); then
        echo "⬆️  akashic CLI 比原始碼舊：binary $(format_time "${bin_ts}")，${BASE_LABEL} 最後一次動到 package 原始碼是 $(format_time "${src_ts}")（${latest#* }）。"
        NEEDS_REBUILD=1
    fi
}

case "${SOURCE_STATE}" in
    not-root) echo "ℹ️  $(clean "${SOURCE_DIR}") 不是一個 git repo 的根目錄：沒有拿 CLI 跟原始碼比新舊。把 AKASHIC_SOURCE_DIR 設成 Akashic-Library checkout 的根目錄。" ;;
    no-git)   echo "ℹ️  PATH 上找不到 git：沒有拿 CLI 跟原始碼比新舊。" ;;
esac

if [[ -n "${SOURCE_TOP}" ]]; then
    if BASE_COMMIT=$(sgit rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}'); then
        BASE_NAME="origin/main"
        BASE_LABEL="origin/main（上次 fetch 時）"
    elif BASE_COMMIT=$(sgit rev-parse --verify --quiet 'HEAD^{commit}'); then
        BASE_NAME="HEAD"
        BASE_LABEL="HEAD"
    else
        BASE_COMMIT=""
    fi
    if [[ -n "${BASE_COMMIT}" ]]; then
        # 建置的 commit：裸 hash（stamp-version.sh 的格式），可帶 `-dirty`；`unknown` 與舊 CLI 沒有
        BUILD_REF=""
        [[ "${VERSION}" =~ ^([0-9a-f]{7,40})(-dirty)?$ ]] && BUILD_REF="${BASH_REMATCH[1]}"
        if (( VERSION_RC == 64 )) && sgit cat-file -e "${BASE_COMMIT}:${VERSION_FILE}"; then
            # 64 本身就是證據：這個 CLI 建置自加入 --version 的 commit 之前，而基準已經過了那個 commit
            echo "⬆️  akashic CLI 不認得 --version：它建置自加入這個旗標（#775）之前，而 ${BASE_LABEL} 已經有了，必定落後。"
            NEEDS_REBUILD=1
        elif [[ -z "${BUILD_REF}" ]] || ! report_by_commit; then
            report_by_file_times
        fi
    fi
fi

[[ -n "${NEEDS_REBUILD}" ]] && print_install_hint
exit 0
