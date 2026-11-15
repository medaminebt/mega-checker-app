#!/bin/bash
# Build the web version:  build/web/   (upload that folder to any static host)
#
#   ./build_web.sh                     build for the root of a domain
#   ./build_web.sh --base-href /app/   build for https://example.com/app/
#   ./build_web.sh --serve             build, then preview on http://localhost:8080
#
# --no-web-resources-cdn bundles Flutter's renderer (CanvasKit) instead of
# loading it from Google's CDN: the app then makes no third-party requests
# except to your Supabase project.
set -euo pipefail
cd "$(dirname "$0")"

SERVE=false
ARGS=()
for a in "$@"; do
  if [[ "$a" == "--serve" ]]; then SERVE=true; else ARGS+=("$a"); fi
done

flutter pub get
flutter build web --release --no-web-resources-cdn ${ARGS[@]+"${ARGS[@]}"}

echo
echo "Built: $PWD/build/web"
echo "Upload the CONTENTS of build/web to your host (see BUILD.md → Web)."

if $SERVE; then
  echo "Preview: http://localhost:8080   (Ctrl+C to stop)"
  cd build/web && exec python3 -m http.server 8080 --bind 127.0.0.1
fi
