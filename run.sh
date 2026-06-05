#!/bin/bash
# Always launch on the macOS desktop target.
#
# Why this script: bare `flutter run` may target your iPhone / iPad (the other
# connected devices), but this is a macOS-only desktop app with no iOS support
# and no CocoaPods — that combination errors out in the terminal. The `-d macos`
# flag below avoids that entirely.
cd "$(dirname "$0")" || exit 1
exec flutter run -d macos --debug "$@"
