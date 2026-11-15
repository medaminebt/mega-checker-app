#!/bin/bash
# Build the release app:  build/macos/Build/Products/Release/mega-checker-app.app
#
#   ./build.sh            build only
#   ./build.sh --install  build, then copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

flutter pub get
flutter build macos --release

NAME="mega-checker-app.app"
APP="build/macos/Build/Products/Release/$NAME"
echo
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  # Also remove the copy installed under the app's old name.
  rm -rf "/Applications/mega_keepalive.app" "/Applications/$NAME"
  ditto "$APP" "/Applications/$NAME"
  echo "Installed: /Applications/$NAME  (open it from Launchpad / Spotlight)"
else
  echo "Open it with:  open \"$APP\""
  echo "Install it with:  ./build.sh --install"
fi
