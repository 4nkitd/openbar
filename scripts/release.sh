#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <version> <build-number>"
  exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must use X.Y.Z" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Build number must be numeric" >&2; exit 1; }
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OpenBar"
ARCH="$(uname -m)"
ARCHIVE_NAME="$APP_NAME-$VERSION-macos-$ARCH.zip"
UPDATES_DIR="$ROOT_DIR/dist/releases/v$VERSION"
SPARKLE_TOOLS="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

cd "$ROOT_DIR"
BUILD_ONLY=1 APP_VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./scripts/install.sh

mkdir -p "$UPDATES_DIR"
codesign --verify --deep --strict "$ROOT_DIR/dist/$APP_NAME.app"
ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/$APP_NAME.app" "$UPDATES_DIR/$ARCHIVE_NAME"

if [[ -n "${SPARKLE_FEED_URL:-}" && -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  "$SPARKLE_TOOLS/generate_appcast" \
    --download-url-prefix "https://github.com/4nkitd/openbar/releases/download/v$VERSION/" \
    "$UPDATES_DIR"
  cp "$UPDATES_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
fi

cp "$UPDATES_DIR/$ARCHIVE_NAME" "$ROOT_DIR/dist/$ARCHIVE_NAME"
shasum -a 256 "$ROOT_DIR/dist/$ARCHIVE_NAME"

echo "Built dist/$ARCHIVE_NAME"
