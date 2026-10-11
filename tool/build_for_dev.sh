#!/usr/bin/env bash
# Debug build: the web editor, then an APK for 32-bit ARM (the TV's), both
# with assertions on.
set -euo pipefail
cd "$(dirname "$0")/.."

tool/build_editor.sh debug
flutter build apk --debug --target-platform android-arm
