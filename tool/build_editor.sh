#!/usr/bin/env bash
# Builds the web editor (lib/editor) and puts what a browser needs of it in
# assets/editor/, from where the TV serves it as its page. Run it before
# building the app. Takes the build mode: release (default) or debug.
#
# Flutter bundles an asset folder without its subfolders, so the files are
# laid flat: "/" in a path becomes "__". Each is gzipped, which is how the
# TV sends it. See lib/server/editor_files.dart.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-release}
out=build/editor
dest=assets/editor

flutter build web "--$mode" -t lib/editor/main.dart -o "$out" \
  --base-href / --no-web-resources-cdn --no-wasm-dry-run

find "$dest" -type f ! -name .gitkeep -delete

# The CanvasKit renderer in both its builds (Chromium's and everyone
# else's); the other renderers in the folder are not used by this build.
files=(
  index.html favicon.png flutter_bootstrap.js main.dart.js
  canvaskit/canvaskit.js canvaskit/canvaskit.wasm
  canvaskit/chromium/canvaskit.js canvaskit/chromium/canvaskit.wasm
  assets/AssetManifest.bin assets/AssetManifest.bin.json
  assets/FontManifest.json
)
while IFS= read -r file; do files+=("$file"); done \
  < <(cd "$out" && find assets/fonts assets/shaders -type f | sort)

for file in "${files[@]}"; do
  gzip -9nc "$out/$file" > "$dest/${file//\//__}"
done

# Changes whenever the editor does: the TV sends it as the ETag.
find "$dest" -type f ! -name version ! -name .gitkeep | sort | xargs cat \
  | sha256sum | cut -c1-16 > "$dest/version"

echo "Editor: ${#files[@]} files, $(du -sh "$dest" | cut -f1) in $dest"
