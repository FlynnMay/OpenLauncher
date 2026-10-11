#!/usr/bin/env bash
# Release build: the web editor, then one APK for 32- and 64-bit ARM.
set -euo pipefail
cd "$(dirname "$0")/.."

tool/build_editor.sh release
flutter build apk --release --target-platform android-arm,android-arm64
