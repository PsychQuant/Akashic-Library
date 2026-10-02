#!/bin/bash
# Version-aware auto-download wrapper for akashic-mcp.
# 優先 gh CLI 下載；repo 已公開，gh 不可用時 curl fallback 也拿得到。
set -u

REPO="PsychQuant/Akashic-Library"
BINARY_NAME="akashic-mcp"
ASSET_NAME="akashic-mcp"
INSTALL_DIR="$HOME/bin"
BINARY="$INSTALL_DIR/$BINARY_NAME"
VERSION_FILE="$INSTALL_DIR/.${BINARY_NAME}.version"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

DESIRED_VERSION=""
if [[ -f "$PLUGIN_JSON" ]]; then
    # binary_version 優先（#275：shell version 與 binary release tag 解耦——
    # shell-only bump 不得產生不存在的 release tag）；缺席時回讀 version（舊 plugin.json 相容）
    DESIRED_VERSION=$(grep -oE '"binary_version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
        | head -1 | cut -d'"' -f4 || true)
    if [[ -z "$DESIRED_VERSION" ]]; then
        DESIRED_VERSION=$(grep -oE '"version":[[:space:]]*"[^"]+"' "$PLUGIN_JSON" 2>/dev/null \
            | head -1 | cut -d'"' -f4 || true)
    fi
fi
INSTALLED_VERSION=""
[[ -f "$VERSION_FILE" ]] && INSTALLED_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)

NEED_DOWNLOAD=false
if [[ ! -x "$BINARY" ]]; then
    NEED_DOWNLOAD=true
elif [[ -n "$DESIRED_VERSION" ]] && [[ "$INSTALLED_VERSION" != "$DESIRED_VERSION" ]]; then
    NEED_DOWNLOAD=true
fi

if $NEED_DOWNLOAD; then
    echo "$BINARY_NAME: downloading v${DESIRED_VERSION:-latest} from $REPO..." >&2
    mkdir -p "$INSTALL_DIR"
    # 沒有指定版本（plugin.json 讀不到）時不組出 `akashic-mcp-v` 這種不存在的 tag：gh 那條下載 latest，
    # curl 這條也走 latest 的固定網址，訊息裡也不點名 tag（#693 LOW）。
    if [[ -n "$DESIRED_VERSION" ]]; then
        TAG="akashic-mcp-v${DESIRED_VERSION}"
        URL="https://github.com/$REPO/releases/download/$TAG/$ASSET_NAME"
        WHAT="${TAG} 的 release asset"
    else
        TAG=""
        URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
        WHAT="最新 release 的 asset"
    fi
    TMP_DIR="$(mktemp -d)"
    OK=false
    TRIED_GH=false
    if command -v gh >/dev/null 2>&1; then
        TRIED_GH=true
        # 指定了版本就只下載那個 tag，**不退回 latest**（#630）：2026-09-24 release 的 asset 還在
        # 上傳時，退回 latest 拿到舊版，卻把指定版本寫進版本檔——從此不再重試，binary 永遠是舊的。
        # 失敗時走下方的既有路徑：沿用現有 binary、版本檔不動，下次啟動重試。
        if [[ -n "$DESIRED_VERSION" ]]; then
            gh release download "$TAG" --repo "$REPO" --pattern "$ASSET_NAME" \
                --dir "$TMP_DIR" 2>/dev/null && OK=true
        elif gh release download --repo "$REPO" --pattern "$ASSET_NAME" \
                --dir "$TMP_DIR" 2>/dev/null; then
            OK=true
        fi
    fi
    if ! $OK; then
        curl -sL --max-time 120 -o "$TMP_DIR/$ASSET_NAME" "$URL" 2>/dev/null \
          && file "$TMP_DIR/$ASSET_NAME" 2>/dev/null | grep -q "Mach-O" && OK=true
    fi
    if $OK && [[ -s "$TMP_DIR/$ASSET_NAME" ]]; then
        chmod +x "$TMP_DIR/$ASSET_NAME"
        mv "$TMP_DIR/$ASSET_NAME" "$BINARY"
        echo "${DESIRED_VERSION:-unknown}" > "$VERSION_FILE"
        echo "$BINARY_NAME: installed v${DESIRED_VERSION:-latest}" >&2
    else
        rm -rf "$TMP_DIR"
        if [[ -x "$BINARY" ]]; then
            echo "$BINARY_NAME: WARNING — download failed, keeping existing binary" >&2
        else
            # 兩條都試過才會走到這裡：先 gh release download（有裝 gh 才試），再 curl 公開的 release 網址（repo 是公開的，
            # 兩條都不需要登入）。所以原因不是 gh 沒登入——是沒有網路、該版本的 asset 還沒上傳（#630 的情形），或下載的檔不是 Mach-O。
            # **變數一律用 ${VAR}**：全形標點緊接在 $VAR 後面時，UTF-8 locale 下的 bash 3.2 會把標點的第一個位元組讀成變數名的一部分，
            # 加上 `set -u` 整支腳本以 unbound variable 中止，訊息一行也印不出來（#693 R2 verify；C locale 下看不出來）。
            if $TRIED_GH; then GH_TRIED="gh release download ${TAG:+${TAG} }--repo ${REPO}（失敗）"; else GH_TRIED="gh（沒有安裝，略過）"; fi
            echo "${BINARY_NAME}: ERROR — download failed。已試：${GH_TRIED}；再 curl ${URL}（失敗，或下載的檔不是 Mach-O）。" >&2
            echo "${BINARY_NAME}: 可能原因：沒有網路；${WHAT} 還沒上傳（release 剛建好時）；網路擋住 github.com。repo 是公開的，不需要 gh auth login。" >&2
            exit 1
        fi
    fi
    rm -rf "$TMP_DIR" 2>/dev/null
fi

exec "$BINARY" "$@"
