#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${CHECK_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/openbar-check.XXXXXX")}"
mkdir -p "$OUT/Checks.app/Contents/MacOS" "$OUT/Checks.app/Contents/Resources"
printf '%s\n' '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Checks</string><key>CFBundleIdentifier</key><string>dev.codexbar.regression-checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' > "$OUT/Checks.app/Contents/Info.plist"
FILES=()
for file in "$ROOT"/Sources/OpenBar/*.swift; do
    [[ "$file" == */App.swift ]] || FILES+=("$file")
done
swiftc -parse-as-library -warnings-as-errors "${FILES[@]}" "$ROOT/Tests/RegressionChecks.swift" -o "$OUT/Checks.app/Contents/MacOS/Checks"
cp "$ROOT/assets/providers/claude.svg" "$OUT/Checks.app/Contents/Resources/ProviderClaude.svg"
cp "$ROOT/assets/providers/codex.pdf" "$OUT/Checks.app/Contents/Resources/ProviderCodex.pdf"
cp "$ROOT/assets/providers/opencode.svg" "$OUT/Checks.app/Contents/Resources/ProviderOpenCode.svg"
cp "$ROOT/assets/providers/copilot.pdf" "$OUT/Checks.app/Contents/Resources/ProviderCopilot.pdf"
cp "$ROOT/assets/providers/antigravity.png" "$OUT/Checks.app/Contents/Resources/ProviderAntigravity.png"
"$OUT/Checks.app/Contents/MacOS/Checks" "$OUT" | tee "$OUT/checks.log"
grep -q '^ALL CHECKS PASSED$' "$OUT/checks.log"
echo "Screenshots and test cache: $OUT"
