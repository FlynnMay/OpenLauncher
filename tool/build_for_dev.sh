#!/usr/bin/env bash
# Debug build: the packs, the web editor, then an APK for 32-bit ARM (the
# TV's), the last two with assertions on.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run tool/build_packs.dart
tool/build_editor.sh debug
flutter build apk --debug --target-platform android-arm
