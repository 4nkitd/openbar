#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${CHECK_OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/openbar-updates.XXXXXX")}"
FRAMEWORKS="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
[[ -d "$FRAMEWORKS/Sparkle.framework" ]] || { echo "Run swift build to fetch Sparkle first." >&2; exit 1; }
mkdir -p "$OUT/SparkleChecks.app/Contents/MacOS"
swiftc -warnings-as-errors "$ROOT/scripts/validate-update.swift" -o "$OUT/validate-update"
swift "$ROOT/Tests/UpdateValidationChecks.swift" "$OUT"
swiftc -parse-as-library -warnings-as-errors -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" "$ROOT/Tests/SparkleChecks.swift" -o "$OUT/SparkleChecks.app/Contents/MacOS/SparkleChecks"
"$OUT/SparkleChecks.app/Contents/MacOS/SparkleChecks" "$OUT/appcast.xml"
echo "Update check fixtures: $OUT"
