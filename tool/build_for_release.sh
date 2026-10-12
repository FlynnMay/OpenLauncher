#!/usr/bin/env bash
# Release build: the packs, the web editor, then one APK for 32- and 64-bit ARM.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run tool/build_packs.dart
tool/build_editor.sh release
flutter build apk --release --target-platform android-arm,android-arm64
