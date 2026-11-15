#!/bin/bash
# Build the release app:  build/macos/Build/Products/Release/mega_keepalive.app
#
#   ./build.sh            build only
#   ./build.sh --install  build, then copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

flutter pub get
flutter build macos --release

APP="build/macos/Build/Products/Release/mega_keepalive.app"
echo
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/mega_keepalive.app"
  ditto "$APP" "/Applications/mega_keepalive.app"
  echo "Installed: /Applications/mega_keepalive.app  (open it from Launchpad / Spotlight)"
else
  echo "Open it with:  open \"$APP\""
  echo "Install it with:  ./build.sh --install"
fi
