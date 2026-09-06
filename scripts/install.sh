#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OpenBar"
BUNDLE_ID="in.4nkitd.openbar"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST="$CONTENTS_DIR/Info.plist"

echo "Building release binary..."
cd "$ROOT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
cp "$ROOT_DIR/assets/CodexBarLite.icns" "$RESOURCES_DIR/OpenBar.icns"
cp "$ROOT_DIR/assets/codexbar-lite-blue-dot.png" "$RESOURCES_DIR/OpenBarLogo.png"
cp "$ROOT_DIR/assets/providers/claude.svg" "$RESOURCES_DIR/ProviderClaude.svg"
cp "$ROOT_DIR/assets/providers/opencode.svg" "$RESOURCES_DIR/ProviderOpenCode.svg"
cp "$ROOT_DIR/assets/providers/codex.pdf" "$RESOURCES_DIR/ProviderCodex.pdf"
cp "$ROOT_DIR/assets/providers/antigravity.png" "$RESOURCES_DIR/ProviderAntigravity.png"
cp "$ROOT_DIR/assets/providers/copilot.pdf" "$RESOURCES_DIR/ProviderCopilot.pdf"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT_DIR/licenses" "$RESOURCES_DIR/licenses"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIconFile</key>
    <string>OpenBar.icns</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>

    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>

    <key>LSUIElement</key>
    <true/>

    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

  </dict>
</plist>
EOF

if [[ -n "${SPARKLE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  : "${SPARKLE_FEED_URL:?Set an OpenBar update feed URL}"
  : "${SPARKLE_PUBLIC_KEY:?Set the matching OpenBar public signing key}"
  [[ "$SPARKLE_FEED_URL" == https://* ]] || { echo "The update feed must use HTTPS" >&2; exit 1; }
  plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$PLIST"
  plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$PLIST"
  plutil -insert SUEnableAutomaticChecks -bool YES "$PLIST"
  plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$PLIST"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  echo "Built $APP_DIR"
  exit 0
fi

echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_DIR" "/Applications/$APP_NAME.app"

echo "Migrating Launch at Login..."
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
rm -f "$LAUNCH_AGENT"

echo "Launching app..."
open "/Applications/$APP_NAME.app"

echo "Done. OpenBar should now appear in your top bar."
