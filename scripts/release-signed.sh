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
  echo "✗ VERSION（${VERSION}）與 mcpb/manifest.json（${MANIFEST_VERSION}）不一致——先同步再 release"
  exit 1
}

# #630：release 出貨的必須是 tag 那一份程式。v0.12.0 出貨的是兩週前的舊產物——下方
# 三道檢查任一道存在，它都不會安靜地發出去。
[ -z "$(git status --porcelain)" ] || {
  echo "✗ 工作樹不乾淨——產物會與 tag（打在 HEAD）不是同一份程式："; git status --short; exit 1; }
git fetch -q --tags origin
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || {
    echo "✗ tag $TAG 已存在且指向 $(git rev-parse --short "$TAG^{commit}")，不是 HEAD——換版號，不覆蓋既有 release"; exit 1; }
fi

echo "→ [1/6] Universal release build"
# 產物路徑問 SwiftPM，不寫死：Swift 6.4 的多架構建置從 .build/apple 改寫到 .build/out，
# 舊路徑上殘留的產物讓 v0.12.0 的「檔案存在」檢查通過（#630）。
BUILD_ARGS=(-c release --arch arm64 --arch x86_64)
BUILT="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$BINARY"
# 先刪再建：建完仍存在，才證明是這次建出來的（比對 mtime 在「沒改程式、重跑發布」時會誤報）
rm -f "$BUILT"
swift build "${BUILD_ARGS[@]}"
[ -f "$BUILT" ] || { echo "✗ 這次建置沒有產生 $BUILT"; exit 1; }
# 冒煙：產物回報的 store format 必須等於原始碼。舊 binary 不認得旗標，stdin 為空時會直接
# 結束、輸出為空——同樣紅，不會卡住。
WANT=$(sed -nE 's/.*public static let supported = ([0-9]+).*/\1/p' Sources/AkashicStoreIO/StoreVersion.swift)
GOT=$("$BUILT" --store-format </dev/null 2>/dev/null || true)
[ -n "$WANT" ] && [ "$GOT" = "$WANT" ] || {
  echo "✗ 冒煙檢查失敗：產物回報 store format「${GOT}」，原始碼是「${WANT}」——產物不是由當下的原始碼建出"; exit 1; }
echo "  ✓ 產物 ${BUILT}（store format ${GOT}，與原始碼一致）"

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
git tag "$TAG" 2>/dev/null || echo "  （tag 已存在且指向 HEAD——開頭已檢查）"
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
