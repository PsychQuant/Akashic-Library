#!/bin/bash
# akashic-mcp signed + notarized release（che-mcps pipeline 慣例）
# 需求：DEVELOPER_ID（cert SHA-1）、NOTARY_PROFILE（keychain profile）
set -euo pipefail

VERSION="${VERSION:?VERSION 必填（如 0.1.0）}"
DEVELOPER_ID="${DEVELOPER_ID:?DEVELOPER_ID 必填（cert SHA-1）}"
NOTARY_PROFILE="${NOTARY_PROFILE:?NOTARY_PROFILE 必填（keychain profile）}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="akashic-mcp"
MCPB_DIR="$REPO_ROOT/mcpb"
TAG="akashic-mcp-v${VERSION}"

cd "$REPO_ROOT"

MANIFEST_VERSION=$(python3 -c "import json;print(json.load(open('$MCPB_DIR/manifest.json'))['version'])")
[ "$MANIFEST_VERSION" = "$VERSION" ] || {
  echo "✗ VERSION（$VERSION）與 mcpb/manifest.json（$MANIFEST_VERSION）不一致——先同步再 release"
  exit 1
}

echo "→ [1/6] Universal release build"
swift build -c release --arch arm64 --arch x86_64
BUILT="$REPO_ROOT/.build/apple/Products/Release/$BINARY"
[ -f "$BUILT" ] || { echo "✗ build 產物不存在：$BUILT"; exit 1; }

echo "→ [2/6] Codesign（Developer ID + hardened runtime）"
mkdir -p "$MCPB_DIR/server"
cp "$BUILT" "$MCPB_DIR/server/$BINARY"
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID" "$MCPB_DIR/server/$BINARY"
codesign --verify --strict "$MCPB_DIR/server/$BINARY"

echo "→ [3/6] Notarize（round-trip 約 2–10 分鐘）"
NOTARIZE_ZIP="$(mktemp -d)/akashic-mcp-notarize.zip"
ditto -c -k "$MCPB_DIR/server/$BINARY" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ [4/6] SHA-256 + mcpb 打包"
shasum -a 256 "$MCPB_DIR/server/$BINARY" | awk '{print $1}' > "$MCPB_DIR/server/$BINARY.sha256"
MCPB_FILE="$MCPB_DIR/akashic-mcp-${VERSION}.mcpb"
( cd "$MCPB_DIR" && zip -qr "$(basename "$MCPB_FILE")" manifest.json server )
shasum -a 256 "$MCPB_FILE" | awk '{print $1}' > "$MCPB_FILE.sha256"

echo "→ [5/6] Git tag"
git tag "$TAG" 2>/dev/null || echo "  （tag 已存在，沿用）"
git push origin "$TAG"

echo "→ [6/6] GitHub release + assets"
gh release create "$TAG" --title "akashic-mcp v${VERSION}" \
  --notes "akashic-mcp v${VERSION} — signed + notarized universal binary（arm64+x86_64）" \
  "$MCPB_DIR/server/$BINARY#akashic-mcp-binary" \
  "$MCPB_DIR/server/$BINARY.sha256" \
  "$MCPB_FILE" "$MCPB_FILE.sha256" 2>/dev/null \
  || gh release upload "$TAG" --clobber \
       "$MCPB_DIR/server/$BINARY" \
       "$MCPB_DIR/server/$BINARY.sha256" "$MCPB_FILE" "$MCPB_FILE.sha256"

echo "✓ release 完成：$TAG"
