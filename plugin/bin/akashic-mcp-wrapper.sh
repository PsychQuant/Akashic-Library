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
    TAG="akashic-mcp-v${DESIRED_VERSION}"
    TMP_DIR="$(mktemp -d)"
    OK=false
    if command -v gh >/dev/null 2>&1; then
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
        URL="https://github.com/$REPO/releases/download/$TAG/$ASSET_NAME"
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
            echo "$BINARY_NAME: ERROR — download failed（private repo 需 gh auth login）" >&2
            exit 1
        fi
    fi
    rm -rf "$TMP_DIR" 2>/dev/null
fi

exec "$BINARY" "$@"
