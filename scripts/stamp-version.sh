#!/bin/bash
# 把建置時的 commit 寫進受追蹤的佔位檔、執行一個命令、把佔位檔放回去（#775）。
#
#   scripts/stamp-version.sh <佔位檔> -- <命令> [參數...]
#   scripts/stamp-version.sh Sources/akashic/BuildVersion.swift -- swift build -c release --product akashic
#
# 移植自 safari-browser 的 scripts/stamp-version.sh（safari-browser#278），在 repo 根目錄執行。
# `akashic --version` 印出這裡寫入的值；akashic-mcp plugin 的 SessionStart hook（plugin/hooks/check-cli.sh）
# 拿它跟原始碼 checkout 比，說出 CLI 落後幾個 commit。
#
# 版本字串是 `git describe --always --dirty --abbrev=12 --exclude='*'`，也就是裸的 `<12 位 hash>[-dirty]`：
#   - 排除所有 tag。這個 repo 的 tag 是 akashic-mcp-v*（server 的 release）、idd-*-baseline、idd-*-verified 等，
#     沒有一個描述 CLI 的建置；不排除時 main 會被描述成 `idd-700-verified-51-g<hash>`。hook 只解析裸 hash 一種形狀。
#   - 先算版本、再改檔。先寫戳記會讓每一次戳記過的建置都是 `-dirty`（戳記本身就是一個受追蹤的修改）。
#   - package 路徑（COMPILED_PATHS）下有未追蹤的檔也算 `-dirty`：`git describe --dirty` 不看未追蹤檔，SwiftPM 卻會
#     編譯它們，實作到一半的新檔就在 binary 裡。
#   - 白名單（字母、數字、`.`、`_`、`+`、`-`）以外的字元、任何 git 失敗（沒有 .git、沒有 git、沒有 commit）都變成 `unknown`。
#     這個值會放進 Swift 字串字面值裡，引號與換行不能進檔。
#   - 所在目錄必須是自己 repo 的根目錄。`git describe` 會往上找，解壓在別的 repo 裡的原始碼會被蓋上那個 repo 的值，
#     看起來是真的。
#
# 佔位檔從備份還原（不用 `git checkout`，沒有 .git 的原始碼也還原得了），而且每一種結束方式都還原：命令成功、失敗、
# 這支腳本收到 INT／QUIT／TERM／HUP。命令以子行程執行並等待它，因為 bash 會把 trap 延到前景子行程結束之後才跑，
# 一次 release 建置收到 TERM 不該等幾分鐘才清理。
#
# 被包的命令自己收不到 INT／QUIT：bash 讓背景命令忽略這兩個訊號，bash 3.2 在子 shell 裡 `trap - INT QUIT` 也還原不了
# （2026-11-10 實測）。Ctrl-C 由這支腳本接住，改送 TERM 給命令，再還原佔位檔。
#
# **建置期間佔位檔是被改著的**：
#   - 同一個工作樹裡若有別的工作線在這幾分鐘內 commit，可能把戳記值掃進去。在沒有別人 commit 的 checkout 上建置；
#     萬一戳記值被 commit 了，看得出來（佔位值應為 `unknown`）。
#   - 同一個工作樹裡的第二次戳記建置會被拒絕（結束碼 3）：它看到的是第一次寫進去的戳記值，把那個值當成原檔備份、
#     建完「還原」回去，戳記值就永久留在受追蹤的檔裡。被 SIGKILL 的建置留下戳記值時也一樣拒絕——確認沒有別的建置在跑，
#     還原該檔（`git checkout -- <佔位檔>`）再重跑。
#
# 結束碼：被包的命令的結束碼；2 用法錯誤或備份失敗；3 佔位檔不是佔位值；4 戳記寫不進去（3 與 4 都沒有執行命令）；
# 收到訊號時是 128+n。
#
# 這支是 shell 而不是 Swift：它要在 Swift binary 存在之前先跑（`.claude/rules/swift-is-the-implementation-language.md` 例外 1）。
set -u

usage() {
  echo "usage: $0 <version-file> -- <command> [args...]" >&2
  exit 2
}

[ $# -ge 3 ] && [ "$2" = "--" ] || usage
FILE="$1"
shift 2
[ -f "$FILE" ] || { echo "stamp-version: $FILE does not exist" >&2; exit 2; }

# 會被編進 binary 的路徑。plugin/hooks/check-cli.sh 有逐字相同的一行（StampVersionTests 比對）。
COMPILED_PATHS=(Sources Package.swift Package.resolved repos/biblatex-apa-swift)

# 佔位檔此刻必須是佔位值（見檔頭）。先查、再備份：查不過就什麼都不動。
if ! grep -qF -- 'static let value = "unknown"' "$FILE"; then
  echo "stamp-version: $FILE does not hold the placeholder value: another stamped build is still running in this checkout, or an interrupted one left its value behind. Not running the command. Once no other build is running, restore the file (git checkout -- $FILE) and retry." >&2
  exit 3
fi

# 只含白名單字元才成立。在 C locale 下比：bash 3.2 的字元範圍依 locale 的排序，en_US.UTF-8 下 A-Z 會放行非 ASCII 字母。
# 直接比字串，不把它送進 $(…)——那會吃掉換行，含換行的值就過得了檢查。
safe_version() {
  local LC_ALL=C
  case "$1" in
    ""|*[!A-Za-z0-9._+-]*) return 1 ;;
  esac
  return 0
}

VERSION="unknown"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" 2>/dev/null && pwd -P)"
HERE="$(pwd -P)"
if [ -n "${TOP:-}" ] && [ "$TOP" = "$HERE" ] \
   && DESCRIBED="$(git describe --always --dirty --abbrev=12 --exclude='*' 2>/dev/null)" && safe_version "$DESCRIBED"; then
  VERSION="$DESCRIBED"
  case "$VERSION" in
    *-dirty) ;;
    *)
      if git status --porcelain --untracked-files=normal -- "${COMPILED_PATHS[@]}" 2>/dev/null | grep -q '^??'; then
        VERSION="$VERSION-dirty"
      fi
      ;;
  esac
fi

BACKUP="$(mktemp "${TMPDIR:-/tmp}/stamp-version.XXXXXX")" || exit 2
cp "$FILE" "$BACKUP" || { rm -f "$BACKUP"; exit 2; }

CHILD=""
restore() {
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    if cmp -s "$BACKUP" "$FILE"; then
      rm -f "$BACKUP"   # 檔案沒被改到（寫入在動到它之前就失敗）
    elif cp "$BACKUP" "$FILE"; then
      rm -f "$BACKUP"
    else
      # 複製回去失敗就留著備份：那是原檔唯一的副本
      echo "stamp-version: could not restore $FILE; the original is kept at $BACKUP" >&2
    fi
  fi
  BACKUP=""
}
on_signal() { # 結束碼 128+n，shell 的慣例
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  restore
  exit "$1"
}
trap restore EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
trap 'on_signal 131' QUIT

# 戳記寫不進去就不建置：照樣建下去的 binary 印的是佔位值，而沒有人知道
if ! printf '/// 戳記值（scripts/stamp-version.sh 在建置期間寫入，建完還原）——不得 commit\nenum BuildVersion { static let value = "%s" }\n' "$VERSION" > "$FILE"; then
  echo "stamp-version: could not write $FILE; not running the command" >&2
  exit 4
fi

"$@" <&0 &
CHILD=$!
wait "$CHILD"
CODE=$?
CHILD=""
exit "$CODE"
