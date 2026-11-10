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
#   - package 路徑（COMPILED_PATHS）下有未追蹤的檔也算 `-dirty`，submodule 裡的也算：`git describe --dirty` 兩種都不看，
#     SwiftPM 卻會編譯它們，實作到一半的新檔就在 binary 裡。讀不出工作樹狀態時同樣加 `-dirty`——不宣稱是乾淨的建置。
#     看不到的只剩被 .gitignore 忽略、SwiftPM 仍會編譯的檔。
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
# （2026-11-10 實測）。Ctrl-C 由這支腳本接住，改送 TERM 給命令，再還原佔位檔。還原不等命令結束：不理會 TERM 的命令
# 之後讀到的是佔位值。
#
# 這是使用者自己啟動的建置，不是隔離的環境：`git describe`、`git status` 照這個 repo 與使用者的 git 設定執行
# （包括 `core.fsmonitor` 這類會執行程式的設定），被包的命令也照常繼承環境。
#
# **建置期間佔位檔是被改著的**：
#   - 同一個工作樹裡若有別的工作線在這幾分鐘內 commit，可能把戳記值掃進去。在沒有別人 commit 的 checkout 上建置；
#     萬一戳記值被 commit 了，看得出來（佔位值應為 `unknown`）。
#   - 佔位檔已經被戳記過時拒絕執行（結束碼 3）：否則這一次會把別人寫進去的戳記當成原檔備份、建完「還原」回去，
#     戳記就永久留在受追蹤的檔裡。檢查做兩次——一開始查原檔，備份之後查備份本身（兩次之間隔著幾個 git 查詢，別的
#     建置可能在這段時間寫入）。戳記過的檔帶一個標記（STAMP_MARK），所以戳記值本身是 `unknown` 時也認得出來。
#     被 SIGKILL 的建置留下戳記時同樣拒絕——確認沒有別的建置在跑，還原該檔（`git checkout -- <佔位檔>`）再重跑。
#   - 沒有鎖。兩次建置都在對方寫入之前備份到佔位檔時，兩邊都不會被拒絕：結束後檔案仍是佔位值，但後編譯的那個
#     binary 讀到的可能已經是還原後的佔位值，印 `unknown`。
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

# 佔位檔必須是佔位值（見檔頭）。查兩次：這裡先查原檔（查不過就什麼都不動），下面備份之後再查備份本身。
PLACEHOLDER='static let value = "unknown"'
# 戳記過的檔帶這個標記，佔位檔沒有。只看值分不出來：沒有 git、不在 repo 根目錄時，寫進去的戳記值也是 `unknown`。
STAMP_MARK='stamp-version:stamped'
is_placeholder() { grep -qF -- "$PLACEHOLDER" "$1" && ! grep -qF -- "$STAMP_MARK" "$1"; }
refuse_not_placeholder() {
  echo "stamp-version: $FILE does not hold the placeholder value: another stamped build is still running in this checkout, or an interrupted one left its value behind. Not running the command. Once no other build is running, restore the file (git checkout -- $FILE) and retry." >&2
  exit 3
}
is_placeholder "$FILE" || refuse_not_placeholder

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
      # describe 說乾淨之後，package 路徑下 status 還有任何一列就算 dirty：未追蹤檔（`??`），以及裡面有未追蹤或
      # 改過的檔的 submodule（` M`）。`--ignore-submodules=none` 蓋過 `submodule.<名字>.ignore`、`diff.ignoreSubmodules`
      # 的設定。讀不出狀態也算 dirty——失敗時輸出是空的，與「什麼都沒有」一樣，所以看結束碼。
      if STATUS="$(git status --porcelain --untracked-files=normal --ignore-submodules=none -- "${COMPILED_PATHS[@]}" 2>/dev/null)"; then
        [ -n "$STATUS" ] && VERSION="$VERSION-dirty"
      else
        VERSION="$VERSION-dirty"
      fi
      ;;
  esac
fi

BACKUP="$(mktemp "${TMPDIR:-/tmp}/stamp-version.XXXXXX")" || exit 2
cp "$FILE" "$BACKUP" || { rm -f "$BACKUP"; exit 2; }
# 備份到的必須是佔位值。上面那次檢查到這裡之間隔著幾次 git 查詢，別的建置可能已經把戳記寫進去了；
# 建完放回去的就是這份備份，所以查的是它——查原檔第二次仍然擋不住「查完、備份前」的那一刻。
if ! is_placeholder "$BACKUP"; then
  rm -f "$BACKUP"
  refuse_not_placeholder
fi

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
if ! printf '// %s\n/// 戳記值（scripts/stamp-version.sh 在建置期間寫入，建完還原）——不得 commit\nenum BuildVersion { static let value = "%s" }\n' "$STAMP_MARK" "$VERSION" > "$FILE"; then
  echo "stamp-version: could not write $FILE; not running the command" >&2
  exit 4
fi

"$@" <&0 &
CHILD=$!
wait "$CHILD"
CODE=$?
CHILD=""
exit "$CODE"
