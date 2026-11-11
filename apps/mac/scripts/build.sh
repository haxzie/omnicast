#!/usr/bin/env bash
# Builds Omnicast.app from the SwiftPM executable.
# SwiftPM can't produce a bundle itself, so we assemble one around the binary.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
# Spotlight ignores any directory ending in .noindex, which keeps the dev build
# from showing up in Launchpad and search alongside an installed copy.
APP="build.noindex/Omnicast.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Omnicast"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Omnicast"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Omnicast.icns "$APP/Contents/Resources/Omnicast.icns"

# SwiftPM does not compile Metal sources, so the dictation shader is built here
# into default.metallib — the file ShaderLibrary.default loads from the bundle.
echo "▸ metal"
AIR="$(mktemp -t omnicast-shader).air"
xcrun -sdk macosx metal -O3 -c Sources/Omnicast/UI/SiriWave.metal -o "$AIR"
xcrun -sdk macosx metallib "$AIR" -o "$APP/Contents/Resources/default.metallib"
rm -f "$AIR"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# macOS identifies an app to TCC by its code signature, not its path or bundle
# id. An ad-hoc signature gets a fresh identity on every build, so each rebuild
# looks like a brand new app and Accessibility permission is asked for again —
# and the grant you just gave is silently orphaned. Signing with a stable
# Developer ID identity makes the grant stick across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"

if [ -n "$IDENTITY" ]; then
  echo "▸ codesign ($IDENTITY)"
  # Add --timestamp before notarising for distribution; it needs the network,
  # so local builds go without.
  codesign --force --sign "$IDENTITY" \
    --entitlements Resources/Omnicast.entitlements \
    --options runtime "$APP"
else
  echo "▸ codesign (ad-hoc — no Developer ID found)"
  echo "  note: macOS will re-ask for Accessibility permission after every build."
  codesign --force --sign - --entitlements Resources/Omnicast.entitlements "$APP"
fi

echo "✓ $APP"
