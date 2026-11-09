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
#   - 白名單（字母、數字、`.`、`_`、`+`、`-`）以外的字元、任何 git 失敗（沒有 .git、沒有 git、沒有 commit）都變成 `unknown`。
#     這個值會放進 Swift 字串字面值裡，引號不能進檔。
#   - 所在目錄必須是自己 repo 的根目錄。`git describe` 會往上找，解壓在別的 repo 裡的原始碼會被蓋上那個 repo 的值，
#     看起來是真的。
#
# 佔位檔從備份還原（不用 `git checkout`，沒有 .git 的原始碼也還原得了），而且每一種結束方式都還原：命令成功、失敗、
# 這支腳本收到 INT／QUIT／TERM／HUP。命令以子行程執行並等待它，因為 bash 會把 trap 延到前景子行程結束之後才跑，
# 一次 release 建置收到 TERM 不該等幾分鐘才清理。
#
# **建置期間佔位檔是被改著的**：同一個工作樹裡若有別的工作線在這幾分鐘內 commit，可能把戳記值掃進去。在沒有別人
# commit 的 checkout 上建置；萬一戳記值被 commit 了，看得出來（佔位值應為 `unknown`）。
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

VERSION="unknown"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" 2>/dev/null && pwd -P)"
HERE="$(pwd -P)"
if [ -n "${TOP:-}" ] && [ "$TOP" = "$HERE" ] \
   && DESCRIBED="$(git describe --always --dirty --abbrev=12 --exclude='*' 2>/dev/null)" && [ -n "$DESCRIBED" ]; then
  # LC_ALL=C：bash 3.2 的方括號範圍依 locale 的排序，en_US.UTF-8 下 A-Z 會放行非 ASCII 字母
  case "$(LC_ALL=C; printf '%s' "$DESCRIBED" | LC_ALL=C tr -d 'A-Za-z0-9._+-')" in
    "") VERSION="$DESCRIBED" ;;       # 沒有白名單以外的字元
    *) ;;                             # 不能放進 Swift 字面值：維持 unknown
  esac
fi

BACKUP="$(mktemp "${TMPDIR:-/tmp}/stamp-version.XXXXXX")" || exit 2
cp "$FILE" "$BACKUP" || { rm -f "$BACKUP"; exit 2; }

CHILD=""
restore() {
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
    # 複製回去失敗就留著備份：那是原檔唯一的副本
    if cp "$BACKUP" "$FILE"; then
      rm -f "$BACKUP"
    else
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

printf '/// 戳記值（scripts/stamp-version.sh 在建置期間寫入，建完還原）——不得 commit\nenum BuildVersion { static let value = "%s" }\n' "$VERSION" > "$FILE"

"$@" <&0 &
CHILD=$!
wait "$CHILD"
CODE=$?
CHILD=""
exit "$CODE"
