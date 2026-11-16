#!/bin/bash
# Packs mega-checker-app.app into the macOS installer: a .dmg whose window
# shows the app, a "Drag to install" arrow and the Applications folder.
#
#   tool/make_dmg.sh [path/to/mega-checker-app.app] [out.dmg]
#
# Defaults: the app from ./build.sh, written to dist/mega-checker-app-macos.dmg.
# Needs macOS (hdiutil, tiffutil) and python3; the Python packages are
# installed into a temporary venv from macos/packaging/requirements-dmg.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/macos/Build/Products/Release/mega-checker-app.app}"
OUT="${2:-dist/mega-checker-app-macos.dmg}"
[ -d "$APP" ] || { echo "No app at $APP. Build it first (./build.sh)." >&2; exit 1; }

WORK="$(mktemp -d)"
MNT="$WORK/mnt"
cleanup() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "• Python tools (dmgbuild)"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet --disable-pip-version-check \
  --require-hashes -r macos/packaging/requirements-dmg.txt

echo "• Background (1x + Retina)"
tiffutil -cathidpicheck macos/packaging/dmg-background.png \
  macos/packaging/dmg-background@2x.png -out "$WORK/background.tiff" >/dev/null 2>&1

echo "• Disk image"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# hdiutil prints deprecation warnings on newer macOS; they're harmless.
"$WORK/venv/bin/dmgbuild" -s macos/packaging/dmg_settings.py \
  -D app="$APP" \
  -D background="$WORK/background.tiff" \
  -D volume_icon="$APP/Contents/Resources/AppIcon.icns" \
  "MEGA Keep-Alive" "$OUT" 2> >(grep -v "is deprecated" >&2)

echo "• Checking the app inside"
mkdir "$MNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$OUT" >/dev/null 2>&1
codesign --verify --deep --strict "$MNT/$(basename "$APP")"
echo "  signature OK"
test -L "$MNT/Applications"
hdiutil detach "$MNT" -quiet

echo "✓ $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"
