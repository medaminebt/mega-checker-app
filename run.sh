#!/bin/bash
# Run the app from source on the macOS desktop (debug mode, hot reload).
#
# Why `-d macos`: a bare `flutter run` may pick a connected iPhone / iPad, but
# this is a macOS-only desktop app.
cd "$(dirname "$0")" || exit 1
exec flutter run -d macos --debug "$@"
